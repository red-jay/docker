#!/usr/bin/env bash

set -eu
set -o pipefail
shopt -s nullglob

# steal a fd here for de bugs
exec 3>&1
NOOP=1

# minimum required disk size
MINSZ=32036093952	# 32G

# mounted system path
TARGETPATH=/mnt/sysimage

# create a scratch fstab. use it. love it.
FSTAB=$(mktemp)

# password for LUKS volumes
LUKS_PASSWORD=""

# file for kickstart directives
KS_INCLUDE=""

# create data partition?
DATA_PARTITION="yes"

# counter for making sure calls to ready_md are unique
MD_COUNTER=0

# file to record disks used for later grub shenanigans
ENV_OUTPUT_FILE="/tmp/fs-layout.env"

cleanup () {
  rm -f "${FSTAB}"
}

trap cleanup EXIT

# option parser
parse_opts () {
  local switch
  while getopts "SWhk:m:p:t:" switch ; do
    case "${switch}" in
      S) DATA_PARTITION="no" ;;
      W) NOOP=0 ;;
      k) KS_INCLUDE="${OPTARG}" ;;
      m) MINSZ="${OPTARG}" ;;
      p) LUKS_PASSWORD="${OPTARG}" ;;
      t) TARGETPATH="${OPTARG}" ;;
    esac
  done
}

# lsblk groveling, get a value...
get_lsblk_val () {
  local blkline blk key
  declare -A blkline
  blk="${1}"
  key="${2}"
  for word in $blk ; do
    if [[ $word = *"="* ]] ; then
      val=${word#*=}
      val=${val#'"'}
      val=${val%'"'}
      blkline[${word%%=*}]=${val}
    fi
  done
  echo "${blkline[$key]}"
}

# guessing at lsblk devices
get_lsblk_dev () {
  local dev
  dev="${1}"
  if [ -b "/dev/${dev}" ] ; then
    dev="/dev/${dev}"
  elif [ -b "/dev/mapper/${dev}" ] ; then
    dev="/dev/mapper/${dev}"
  fi
  echo "${dev}"
}

# run dmsetup to get block device underlying a dm-synthetic device (luks, lvm)
grovel_dm() {
  local blkname type dmoutput
  blkname="${1}"
  type="${2}"
  blkname=$(get_lsblk_dev "${blkname}")
  dmoutput=$(dmsetup table "${blkname}")
  dma=(${dmoutput})
  # yes, these are magic numbers.
  case "${type}" in
    lvm)
      echo "${dma[3]}"
      ;;
    crypt)
      echo "${dma[6]}"
      ;;
  esac
}

# given a lsblk k/v pair, try to find the actual disk behind it
# NOTE: recursive ;)
key2disk () {
  local filt blk type
  filt="${1}"
  blk=$(lsblk -P | grep -F "${filt}")
  [ ! -z "${blk}" ] || return 0
  type=$(get_lsblk_val "${blk}" TYPE)
  case "${type}" in
    lvm|crypt)
      local dmblk nblk blkname nblkname
      blkname=$(get_lsblk_val "${blk}" NAME)
      dmblk=$(grovel_dm "${blkname}" "${type}")
      nblk=$(lsblk -P | grep -F "MAJ:MIN=\"${dmblk}\"")
      nblkname=$(get_lsblk_val "${nblk}" NAME)
      key2disk "NAME=\"${nblkname}\""
    ;;
    part)
      local blkname disk part
      blkname=$(get_lsblk_val "${blk}" NAME)
      part=${blkname##*[[:alpha:]]}
      disk=${blkname%${part}}
      key2disk "NAME=\"${disk}\""
    ;;
    disk)
      local blkname
      blkname=$(get_lsblk_val "${blk}" NAME)
      echo "${blkname}"
    ;;
  esac
}

# return all disk devices _except_ the ones we booted from sans partitions
# shellcheck disable=SC2120
get_baseblocks() {
  local dev shortdev candidates topdev results check value scratch blocks
  check="" ; value="" ; results=""

  # we don't _require_ an argument (this is why we have the SC2120 exception)
  [ ! -z "${1+x}" ] && {
    # if we do have one, it's (/sys/class/block/$foo/)check == value
    check="${1%%=*}"
    value="${1##*=}"
  }

  # if you have cciss adapters you probably care about right here.
  candidates=( /dev/[hsv]d* /dev/xvd* /dev/fio* )

  # okay, walk all the diskdevs we got and ask pointed questions.
  for dev in "${candidates[@]}" ; do

    # remove everything to the last /
    shortdev="${dev##*/}"
    # we secretly turn partitions into toplevel devs
    topdev="${shortdev%[0-9]*}"

    # filter out our installation/boot disk
    case "${installdisks}" in *"${topdev}"*) continue ;; esac

    # shortcut - if we already have a topdev we don't need to ask _again_
    case "${results}" in *"${topdev}"*) continue ;; esac

    # compare blocks against our MINSZ
    blocks=$(blockdev --getsize64 "/dev/${topdev}")
    if [ "${blocks}" -lt "${MINSZ}" ] ; then continue ; fi

    # if we have a check, do that comparison now. note the reverse logic of "do I skip here?"
    if [ ! -z "${check}" ] ; then
      read -r scratch < "/sys/class/block/${topdev}/${check}"
      if [ "${scratch}" != "${value}" ] ; then continue ; fi
    fi

    # if we got to this point, add our topdev to the result list
    results="${results}${topdev} "
  done

  # return result list
  echo "${results}"
}

# given a string (or rather, any collection of 1 or more arguments), count the words by whitespace in it.
count_words() {
  local count word
  count=0
  # shellcheck disable=SC2034,SC2068
  for word in ${@} ; do
    count=$((count + 1))
  done
  echo "${count}"
}

# return all array devices (why would the installer be on an array?)
get_arrays() {
  local raiddev shortdev results
  results=" "
  mdadm --assemble --scan || true
  for raiddev in /dev/md[0-9]* ; do
    # skip raid _partitions_
    case "${raiddev}" in *p*) continue ;; esac
    # is the array dev wired up to _anything_?
    shortdev="${raiddev##*/}"
    grep -q "^${shortdev}" /proc/mdstat || continue
    results="${results}${shortdev} "
  done
  echo "${results}"
}

# force readwrite arrays -  so we can destroy them cleanly
rw_arrays() {
  local shortdev ro
  for shortdev in ${arraylist} ; do
    # see if array is readwrite
    read -r ro < "/sys/block/${shortdev}/ro"
    if [ "${ro}" == 1 ] ; then
      # readwrite the array
      mdadm -w "/dev/${shortdev}" || true
    fi
  done
}

# stop arrays
stop_arrays() {
  local shortdev
  for shortdev in ${arraylist} ; do
    mdadm -S "/dev/${shortdev}"
  done
}

# stop all bcache devices - requires all underlying devices be writeable
stop_bcache () {
  local bcachef shortdev
  rw_arrays
  # walk all assembled/active(?) bcaches
  for bcachef in /sys/fs/bcache/*-*-*-*-* ; do
    if [ -f "${bcachef}/stop" ] ; then if [ "${NOOP}" -eq 0 ] ; then printf 1 > "${bcachef}/stop" ; else echo "${bcachef}/stop" ; fi ; fi
    sleep 1
    if [ -f "${bcachef}/stop" ] ; then if [ "${NOOP}" -eq 0 ] ; then printf 1 > "${bcachef}/stop" ; else echo "${bcachef}/stop" ; fi ; fi
    sleep 1
    if [ -f "${bcachef}/unregister" ] ; then if [ "${NOOP}" -eq 0 ] ; then printf 1 > "${bcachef}/unregister" ; else echo "${bcachef}/unregister" ; fi ; fi
    sleep 1
  done

  # walk all arrays and stop bcache children on those, too
  for shortdev in ${arraylist} ; do
    # stop any bcaches now
    while [ -f "/sys/block/${shortdev}/bcache/set/stop" ] || [ -f "/sys/block/${shortdev}/bcache/stop" ] ; do
      if [ "${NOOP}" -ne 0 ] ; then break ; fi
      if [ -f "/sys/block/${shortdev}/bcache/set/stop" ] ; then printf 1 > "/sys/block/${shortdev}/bcache/set/stop" ; fi
      if [ -f "/sys/block/${shortdev}/bcache/stop" ] ; then printf 1 > "/sys/block/${shortdev}/bcache/stop" ; fi
      sleep 1
    done
  done
}

# wipe all partition data from a disk, then the disk partition table
wipedisk () {
  local part disk
  disk="${1}"
  for part in /dev/${disk}[0-9]* ; do wipefs -a "${part}" ; done
  wipefs -a "/dev/${disk}" > /dev/null
}

# this is actually what partitions disks - can set raidflags but doesn't set up RAIDs.
# it returns which device got which partition encoded here (biosboot,efiboot,sysboot,system,data)
# I use it with a while loop to create strings of partitions _to_ RAID.
partition_disk () {
  local disk name raidflag partition syssz pblsz align optio chunk mult biosend pstart efiend bootend
  partition="0"
  raidflag="1"
  name="${1}"
  disk="/dev/${name}"
  [ ! -z "${2+x}" ] && {
    raidflag="${2}"
  }
  # calculate partition alignment
  read -r pblsz < "/sys/class/block/${name}/queue/physical_block_size"
  read -r optio < "/sys/class/block/${name}/queue/optimal_io_size"
  read -r align < "/sys/class/block/${name}/alignment_offset"

  chunk=$(($((optio + align)) / pblsz))
  [ "${chunk}" -eq 0 ] && chunk=4096
  # we use 4096 bytes as a 'base' unit for small partition calculations
  mult=$((4096 / pblsz))

  # partition label
  parted "${disk}" mklabel gpt > /dev/null

  # legacy BIOS boot partition
  {
    biosend=$(($((mult * 1024)) + chunk))
    parted -a optimal "${disk}" mkpart biosboot "${chunk}s" "${biosend}s" && partition=$((partition + 1))
    parted "${disk}" toggle "${partition}" bios_grub
    parted "${disk}" toggle "${partition}" legacy_boot
  } > /dev/null 2>&1
  echo "biosboot=${disk}${partition}"

  # EFI system partition
  {
    pstart=1 ; while [ $((pstart * chunk)) -lt "${biosend}" ] ; do pstart=$((pstart + 1)) ; done ; pstart=$((pstart + 1))
    parted -a optimal "${disk}" mkpart '"EFI System Partition"' "$((pstart * chunk))s" 300MB && partition=$((partition + 1))
    parted "${disk}" toggle "${partition}" boot
  } > /dev/null 2>&1
  echo "efiboot=${disk}${partition}"

  # /boot partition
  {
    efiend=$(printf 'unit s\nprint' | parted "${disk}" | awk -F' ' "\$1 == ${partition} { print \$3; }")
    efiend="${efiend%s}"
    pstart=1 ; while [ $((pstart * chunk)) -lt "${efiend}" ] ; do pstart=$((pstart + 1)) ; done
    parted "${disk}" mkpart sysboot "$((pstart * chunk))s" 800m && partition=$((partition + 1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null 2>&1
  echo "sysboot=${disk}${partition}"

  # system partition
  if [ "${DATA_PARTITION}" == "yes" ] ; then
    syssz="24g"
  else
    syssz="100%"
  fi
  {
    bootend=$(printf 'unit s\nprint' | parted "${disk}" | awk -F' ' "\$1 == ${partition} { print \$3; }")
    bootend="${bootend%s}"
    pstart=1 ; while [ $((pstart * chunk)) -lt "${bootend}" ] ; do pstart=$((pstart + 1)) ; done
    parted "${disk}" mkpart system "$((pstart * chunk))s" "${syssz}" && partition=$((partition + 1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null 2>&1
  echo "system=${disk}${partition}"

  # data partition
  if [ "${DATA_PARTITION}" == "yes" ] ; then
    {
      parted "${disk}" mkpart data 24g 100% && partition=$((partition + 1))
      if [ "${raidflag}" -gt 1 ] ; then
        parted "${disk}" toggle "${partition}" raid
      fi
    } > /dev/null 2>&1
    echo "data=${disk}${partition}"
  fi
  sleep 1
}

# this does partitioning for cache disks. same sort of deal, but only returns 'cache' value.
partition_cache () {
  local disk raidflag partition
  partition="0"
  raidflag="1"
  disk="/dev/${1}"
  [ ! -z "${2+x}" ] && {
    raidflag="${2}"
  }
  # partition label
  parted "${disk}" mklabel gpt > /dev/null

  # cache partition
  {
    parted "${disk}" mkpart cache 1m 100% && partition=$((partition +1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null
  echo "cache=${disk}${partition}"
}

lvm_create () {
  local pv vg
  pv="${2}"
  vg="${1}"
  wipefs -a "${pv}"
  pvcreate "${pv}"
  vgcreate "${vg}" "${pv}"
}

ready_lv () {
  local lvname vgname fstyp sizeM lmount devpath mpath fs_opts fs_nos
  lvname="${1}"
  vgname="${2}"
  fstyp="${3}"
  sizeM="${4}"
  lmount=""
  fs_opts="defaults"
  fs_nos="1 2"
  case "${fstyp}" in swap) lmount="swap" ; mpath="swap" fs_nos="0 0" ;; esac
  [ ! -z "${5+x}" ] && {
    lmount="${5}" ; mpath="${TARGETPATH}${lmount}"
    case "${lmount}" in /) fs_nos="1 1" ;; esac
  }
  devpath="/dev/${vgname}/${lvname}"
  printf '%s %s %s %s %s\n' "${devpath}" "${mpath}" "${fstyp}" "${fs_opts}" "${fs_nos}" >> "${FSTAB}"
  if [ ! -z "${KS_INCLUDE}" ] ; then
    if [ "${DATA_PARTITION}" == "yes" ] ; then
      printf 'logvol %s --vgname=%s --fstype=%s --name=%s --size=%s\n' "${lmount}" "${vgname}" "${fstyp}" "${lvname}" "${sizeM}" >> "${KS_INCLUDE}"
    else
      case "${lvname}" in
       root) printf 'logvol %s --vgname=%s --fstype=%s --name=%s --size=%s --grow\n' "${lmount}" "${vgname}" "${fstyp}" "${lvname}" "1024" >> "${KS_INCLUDE}";;
       *)    printf 'logvol %s --vgname=%s --fstype=%s --name=%s --size=%s\n'    "${lmount}" "${vgname}" "${fstyp}" "${lvname}" "${sizeM}" >> "${KS_INCLUDE}";;
      esac
    fi
  else
    lvcreate -Wy "-L${sizeM}M" "-n${lvname}" "${vgname}"
    wipefs -a "${devpath}"
    case "${fstyp}" in
      ext4) mkfs.ext4 "${devpath}" ;;
      swap) mkswap    "${devpath}" ;;
    esac
  fi
}

ready_thin () {
  local lvname vgname tpoolname fstyp sizeM lmount devpath mpath fs_opts fs_nos
  lvname="${1}"
  vgname="${2}"
  tpoolname="${3}"
  fstyp="${4}"
  sizeM="${5}"
  lmount=""
  fs_opts="defaults,discard"
  fs_nos="1 2"
  [ ! -z "${6+x}" ] && { lmount="${6}" ; mpath="${TARGETPATH}${lmount}" ; }
  devpath="/dev/${vgname}/${lvname}"
  printf '%s %s %s %s %s\n' "${devpath}" "${mpath}" "${fstyp}" "${fs_opts}" "${fs_nos}" >> "${FSTAB}"
  if [ ! -z "${KS_INCLUDE}" ] ; then
    printf 'logvol %s --vgname=%s --fstype=%s --name=%s --size=%s --thin --poolname=%s --fsoptions="%s"\n' \
      "${lmount}" "${vgname}" "${fstyp}" "${lvname}" "${sizeM}" "${tpoolname}" "${fs_opts}" >> "${KS_INCLUDE}"
  else
    lvcreate "-V${sizeM}M" "-n${lvname}" --thinpool "${tpoolname}" "${vgname}"
    case "${fstyp}" in
      ext4) mkfs.ext4 "${devpath}" ;;
      swap) mkswap    "${devpath}" ;;
    esac
  fi
}

# create a md device
ready_md () {
  local mdname mdlevel datalevel mddev i s fstyp mount extra fs_opts fs_nos rname
  datalevel="1.0"
  mdname="${1}"
  mdlevel="${2}"
  mddev="${3}"
  fstyp="${4}"
  mount="${5}"
  extra=""
  fs_opts="defaults"
  fs_nos="1 2"
  MD_COUNTER=$(( MD_COUNTER + 1 ))
  mpath="${TARGETPATH}${mount}"
  # efi and boot mds get 1.0 metadata, others 1.1
  case "${mdname}" in
    efi)
      extra='--label="EFISP" --noformat --fsoptions="umask=0077,shortname=winnt"'
      fs_opts='umask=0077,shortname=winnt'
      fs_nos='0 2'
    ;;
    boot) extra='--label="/boot"' ;;
    *)    datalevel="1.1" ;;
  esac
  # shellcheck disable=SC2086
  mdadm --create "/dev/md/${mdname}" -N"${mdname}" -l"${mdlevel}" -n "$(count_words "${mddev}")" --metadata="${datalevel}" ${mddev}
  wipefs -a "/dev/md/${mdname}"
  case "${fstyp}" in
    efi)  mkfs.vfat -F32 -nEFISP "/dev/md/${mdname}" ;;
    ext2) mkfs.ext2 "/dev/md/${mdname}" ;;
  esac
  if [ ! -z "${KS_INCLUDE}" ] ; then
    i=0 ; for part in ${mddev} ; do
      s=${part##*/} ; i=$(( i + 1 ))
      printf 'part raid.%s%s --fstype="mdmember" --noformat --onpart=%s\n' "${MD_COUNTER}" "${i}" "${s}" >> "${KS_INCLUDE}"
    done
    case "${fstyp}" in
      bcache) : ;;
      *)
        printf 'raid %s --device=%s --fstype="%s" --level=%s --useexisting %s\n' "${mount}" "${mdname}" "${fstyp}" "${mdlevel}" "${extra}" >> "${KS_INCLUDE}"
      ;;
    esac
  fi
  case "${fstyp}" in
    lvmpv|bcache) : ;;
    efi)   printf '/dev/md/%s %s %s %s %s\n' "${mdname}" "${mpath}" "vfat" "${fs_opts}" "${fs_nos}" >> "${FSTAB}" ;;
    *)     printf '/dev/md/%s %s %s %s %s\n' "${mdname}" "${mpath}" "${fstyp}" "${fs_opts}" "${fs_nos}" >> "${FSTAB}" ;;
  esac
  sleep 1
  case "${mdname}" in
    data)
      rname=$(readlink "/dev/md/${mdname}")
      rname=${rname##*/}
      printf 'idle' > "/sys/class/block/${rname}/md/sync_action"
    ;;
  esac
}

# create a partition, unless we're just piping to kickstart.
ready_part () {
  local partition fstyp mount extra fs_opts fs_nos mpath fsuuid
  partition="${1}"
  fstyp="${2}"
  mount="${3}"
  extra=""
  fs_opts="defaults"
  fs_nos="1 2"
  mpath="${TARGETPATH}${mount}"
  # always update fstab, though we may rewrite later.
  case "${fstyp}" in
    lvmpv|bcache) : ;;
    efi)   printf '%s %s %s %s %s\n' "${partition}" "${mpath}" "vfat" "${fs_opts}" "${fs_nos}" >> "${FSTAB}" ;;
    *)     printf '%s %s %s %s %s\n' "${partition}" "${mpath}" "${fstyp}" "${fs_opts}" "${fs_nos}" >> "${FSTAB}" ;;
  esac
  if [ ! -z "${KS_INCLUDE}" ] ; then
    case "${fstyp}" in
      bcache) : ;;
      *)      printf 'part %s --fstype="%s" --onpart=%s\n' "${mount}" "${fstyp}" "${partition}" >> "${KS_INCLUDE}" ;;
    esac
  else
    # format and update faketab
    case "${fstyp}" in
      lvmpv|bcache) : ;;
      efi)
        mkfs.vfat -F32 -nEFISP "${partition}"
      ;;
      *)
        "mkfs.${fstyp}" "${partition}"
      ;;
    esac
    # handle efi for the next bit..
    case "${fstyp}" in efi) fstyp="vfat" ;; esac
    # rewrite fstab with UUID now.
    # shellcheck disable=SC2015
    grep -q "${partition}" "${FSTAB}" && {
      fsuuid="$(blkid -s UUID "${partition}")"
      fsuuid="${fsuuid#*UUID=\"}"
      fsuuid="${fsuuid%\"}"
      sed -i -e 's@^'"${partition}"'.*@UUID='"${fsuuid} ${mpath} ${fstyp} ${fs_opts} ${fs_nos}"'@' "${FSTAB}"
    } || true
  fi
}

# walk our fstab and mkdir/mount as needed
make_n_mount () {
  local pass found dev path fstyp fsopt dump chk
  pass=0
  found=1
  while [ "${found}" -eq 1 ] ; do
    found=0
    # shellcheck disable=SC2034
    while read -r dev path fstyp fsopt dump chk ; do
      if [ "${chk}" -eq "${pass}" ] ; then
        found=1
        case "${fstyp}" in swap) continue ;; esac
        fsopt="${fsopt#defaults,}"
        fsopt="${fsopt#defaults}"
        mkdir "${path}"
        if [ ! -z "${fsopt}" ] ; then
          mount  -t "${fstyp}" -o "${fsopt}" "${dev}" "${path}"
        else
          mount -t "${fstyp}" "${dev}" "${path}"
        fi
      fi
    done < "${FSTAB}"
    pass=$(( pass + 1 ))
  done
}

# this is a stack of functions overloading commands for NOOP tests.
blockdev () {
  if [ "${NOOP}" -eq 0 ] ; then command blockdev "${@}" ; else echo "blockdev" "${@}" 1>&3 ; echo "${MINSZ}" ; fi
}

dmsetup () {
  if [ "${NOOP}" -eq 0 ] ; then command dmsetup "${@}" ; else echo "dmsetup" "${@}" 1>&3 ; fi
}

wipefs () {
  if [ "${NOOP}" -eq 0 ] ; then command wipefs "${@}" ; else echo "wipefs" "${@}" 1>&3 ; fi
}

mdadm () {
  if [ "${NOOP}" -eq 0 ] ; then command mdadm "${@}" ; else echo "mdadm" "${@}" 1>&3 ; fi
}

parted () {
  if [ "${NOOP}" -eq 0 ] ; then command parted "${@}" ; else echo "parted" "${@}" 1>&3 ; fi
}

mkfs.vfat () {
  if [ "${NOOP}" -eq 0 ] ; then command mkfs.vfat "${@}" ; else echo "mkfs.vfat" "${@}" 1>&3 ; fi
}

mkfs.ext2 () {
  if [ "${NOOP}" -eq 0 ] ; then command mkfs.ext2 "${@}" ; else echo "mkfs.ext2" "${@}" 1>&3 ; fi
}

mkfs.ext4 () {
  if [ "${NOOP}" -eq 0 ] ; then command mkfs.ext4 "${@}" ; else echo "mkfs.ext4" "${@}" 1>&3 ; fi
}

mkswap () {
  if [ "${NOOP}" -eq 0 ] ; then command mkswap "${@}" ; else echo "mkswap" "${@}" 1>&3 ; fi
}

make-bcache () {
  if [ "${NOOP}" -eq 0 ] ; then command make-bcache "${@}" ; else echo "make-bcache" "${@}" 1>&3 ; fi
}

cryptsetup () {
  if [ "${NOOP}" -eq 0 ] ; then command cryptsetup "${@}" ; else echo "cryptsetup" "${@}" 1>&3 ; fi
}

pvcreate () {
  if [ "${NOOP}" -eq 0 ] ; then command pvcreate "${@}" --dataalignment 8192s
                           else echo    pvcreate "${@}" --dataalignment 8192s ; fi
}

vgcreate () {
  if [ "${NOOP}" -eq 0 ] ; then command vgcreate "${@}" -An --dataalignment 8192s
                           else echo    vgcreate "${@}" -An --dataalignment 8192s ; fi
}

lvcreate () {
  if [ "${NOOP}" -eq 0 ] ; then command lvcreate "${@}" -An
                           else echo    lvcreate "${@}" -An ; fi
}

vgchange () {
  if [ "${NOOP}" -eq 0 ] ; then command vgchange "${@}"
                           else echo    vgchange "${@}" ; fi
}

mkdir () {
  if [ "${NOOP}" -eq 0 ] ; then command mkdir -p "${@}" ; else echo "mkdir" -p "${@}" 1>&3 ; fi
}

mount () {
  if [ "${NOOP}" -eq 0 ] ; then command mount "${@}" ; else echo "mount" "${@}" 1>&3 ; fi
}

# open a luks device and return what we mapped it to (/dev/mapper/luks-UUID)
luks_open () {
  local linkunwind dir candidate luks_map
  candidate="${1}"
  dir="${candidate%/*}"
  if [ -L "${candidate}" ] ; then linkunwind="$(readlink "${candidate}")" ; else linkunwind="${candidate##*/}" ; fi
  luks_map=$(file -s "${dir}/${linkunwind}" | awk -F'UUID: ' '{print $2}')
  luks_map="luks-${luks_map}"
  printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksOpen "${candidate}" "${luks_map}" -
  echo "/dev/mapper/${luks_map}"
}

parse_opts "${@}"

# get rootdisk, and the repodisk if there
repodisk=$(key2disk 'MOUNTPOINT="/run/install/repo"')
repodisk=${repodisk##*/}
rootdisk=$(key2disk 'MOUNTPOINT="/"')
rootdisk=${rootdisk##*/}

# these disks are skipped while partitioning as they have our installers (and are in use!)
installdisks=" ${repodisk} ${rootdisk} "

# determine if we are running in anaconda or not - this will set up functions to either directly format the disk or spit out kickstart directives.
# we need the _grandparent_ pid if we're called from %pre (and not embedded in ks!)
if [ -z "${KS_INCLUDE}" ] ; then
  ppid=$(cut -d' ' -f4 < /proc/$$/stat)
  gpid=$(cut -d' ' -f4 < "/proc/${ppid}/stat")
  # parsing /proc/pid/cmdline sucks.
  while read -r -d $'\0' cmdl ; do
    case $cmdl in
      /sbin/anaconda) KS_INCLUDE=/tmp/part-include ;;
    esac
  done < "/proc/${gpid}/cmdline"
fi

# try to stop lvm, but don't die!
vgchange -a n || true

# call get_arrays _once_ for stopping
arraylist=$(get_arrays)
# stop bcache here (which also flips arrays on)
stop_bcache

vgchange -a n || true

# and stop the arrays
stop_arrays

# shellcheck disable=SC2119
all_disks=$(get_baseblocks)
disknr=$(count_words "${all_disks}")

candidate_disks=""
flash_disks=""

if [ "${disknr}" -eq "1" ] ; then
  # if we only have one disk do this
  candidate_disks="${all_disks}"
elif [ "${disknr}" -eq "2" ] ; then
  # we're going to guess raid1...
  candidate_disks="${all_disks}"
elif [ "${disknr}" -gt "2" ] ; then
  # do we have flash or spinny disks?
  candidate_disks=$(get_baseblocks queue/rotational=1)
  flash_disks=$(get_baseblocks queue/rotational=0)
else
  echo "I didn't find any disks!" 1>&2
  exit 1
fi

candidate_disk_nr=$(count_words "${candidate_disks}")
flash_disk_nr=$(count_words "${flash_disks}")

# wipe partitions now
for disk in ${candidate_disks} ${flash_disks} ; do
  wipedisk "${disk}"
done

# holding variables for mdadm and such
bios_bootdevs=""
efi_bootdevs=""
sys_bootdevs=""
sys_devs=""
data_devs=""
cache_devs=""

# new partition table(s)
for disk in ${candidate_disks} ; do
  while read -r kv ; do
    key=${kv%=*} ;val=${kv#*=}
    case ${key} in
      biosboot) printf -v bios_bootdevs '%s%s ' "${bios_bootdevs}" "${val}" ;;
      efiboot)  printf -v efi_bootdevs  '%s%s ' "${efi_bootdevs}"  "${val}" ;;
      sysboot)  printf -v sys_bootdevs  '%s%s ' "${sys_bootdevs}"  "${val}" ;;
      system)   printf -v sys_devs      '%s%s ' "${sys_devs}"      "${val}" ;;
      data)     printf -v data_devs     '%s%s ' "${data_devs}"     "${val}" ;;
    esac
  done < <(partition_disk "${disk}" "${candidate_disk_nr}")
done

# take a moment to consider the flash drives.
for disk in ${flash_disks} ; do
  while read -r kv ; do
    key=${kv%=*} ;val=${kv#*=}
    case ${key} in
      cache) printf -v cache_devs '%s%s ' "${cache_devs}" "${val}" ;;
    esac
  done < <(partition_cache "${disk}" "${flash_disk_nr}")
done

# adjust raid levels depending on numbers of disks
efiboot_raid_level=1
sysboot_raid_level=1
system_raid_level=1
data_raid_level=1
cache_raid_level=1

# if we have 4 or more drives, switch to raid10/raid6 for system/data
if [ "${candidate_disk_nr}" -ge 4 ] ; then
  system_raid_level=10
  data_raid_level=6
fi

# record biosboot partition
if [ ! -z "${KS_INCLUDE}" ] ; then
  for part in ${bios_bootdevs} ; do s=${part##*/} ; printf 'part biosboot --fstype=biosboot --onpart=%s\n' "${s}" ; done > "${KS_INCLUDE}"
fi

# create arrays/partitions
if [ "${candidate_disk_nr}" -gt 1 ] ; then
  ready_md efi    "${efiboot_raid_level}" "${efi_bootdevs}" "efi"   "/boot/efi"
  ready_md boot   "${sysboot_raid_level}" "${sys_bootdevs}" "ext2"  "/boot"
  ready_md system "${system_raid_level}"  "${sys_devs}"     "lvmpv" "pv.0"
  if [ "${DATA_PARTITION}" == "yes" ] ; then
    ready_md data   "${data_raid_level}"    "${data_devs}"    "lvmpv" "pv.1"
  fi
else
  for part in ${efi_bootdevs} ; do ready_part "${part}" "efi"   "/boot/efi" ; done
  for part in ${sys_bootdevs} ; do ready_part "${part}" "ext2"  "/boot"     ; done
  for part in ${sys_devs}     ; do ready_part "${part}" "lvmpv" "pv.0"      ; done
  if [ "${DATA_PARTITION}" == "yes" ] ; then
    for part in ${data_devs}    ; do ready_part "${part}" "lvmpv" "pv.1"      ; done
  fi
fi

# arrays/partitions for bcache - note the immediate stop/wipe here since bcache triggers kernel level grabbing
if [ "${DATA_PARTITION}" == "yes" ] ; then
  if [ "${flash_disk_nr}" -gt 1 ] ; then
    # shellcheck disable=SC2086
    ready_md cache "${cache_raid_level}" "${cache_devs}" "bcache" "bcache0"
    # run stop_bcache here as it may awaken upon RAID assembly(!)
    stop_bcache
    vgchange -a n
    wipefs -a /dev/md/cache
  elif [ "${flash_disk_nr}" -eq 1 ] ; then
    for part in ${cache_devs} ; do
      ready_part "${part}" "bcache" "bcache0"
      stop_bcache
      wipefs -a "${part}"
    done
  fi

  # create bcache device if we have flash disks
  bcache_backing=""
  bcache_cache=""

  if [ "${candidate_disk_nr}" -gt 1 ] ; then
    bcache_backing=/dev/md/data
  else
    for part in ${data_devs} ; do bcache_backing="${part}" ; done
  fi

  if [ "${flash_disk_nr}" -eq 1 ] ; then
    for part in ${cache_devs} ; do bcache_cache="${part}" ; done
  elif [ "${flash_disk_nr}" -gt 1 ] ; then
    bcache_cache=/dev/md/cache
  fi

  if [ ! -z "${bcache_cache}" ] ; then
    make-bcache --data-offset 161280k --block 4k --bucket 4M -B "${bcache_backing}"
    make-bcache                       --block 4k --bucket 4M -C "${bcache_cache}"
    if [ "${NOOP}" -eq 0 ] ; then
      cacheuuid=$(bcache-super-show "${bcache_cache}" | awk '$1 ~ "cset.uuid" { print $2 }')
      while [ ! -f /sys/block/bcache0/bcache/attach ] ; do sleep 1 ; done
      echo "${cacheuuid}" > /sys/block/bcache0/bcache/attach
      echo writeback > /sys/block/bcache0/bcache/cache_mode
      vgchange -a n
      wipefs -a /dev/bcache0
    fi
    # this is where we trick anaconda by replacing pv.1
    if [ ! -z "${KS_INCLUDE}" ] ; then
      sed -i -e 's/.* pv.1 .*/part pv.1 --fstype="lvmpv" --onpart="bcache0"/' "${KS_INCLUDE}"
    fi
  fi
fi

# if we're asked to encrypt do that here...
data_luks_source=""
sys_luks_source=""
if [ "${DATA_PARTITION}" == "yes" ] ; then
  if [ -b /dev/bcache0 ] ; then
    data_luks_source="/dev/bcache0"
  elif [ -e /dev/md/data ] ; then
    data_luks_source=$(readlink /dev/md/data)
    data_luks_source="/dev/md/${data_luks_source}"
  else
    for part in ${data_devs} ; do data_luks_source="${part}" ; done
  fi
fi

if [ -e /dev/md/system ] ; then
  sys_luks_source="/dev/md/system"
else
  for part in ${sys_devs} ; do sys_luks_source="${part}" ; done
fi

if [ ! -z "${LUKS_PASSWORD}" ] ; then
  if [ ! -z "${KS_INCLUDE}" ] ; then
    # rewrite ks-include pv.0, pv.1 devices - we can get away with system and data pvs because sed REs fall through
    sed -i -re 's/^(.* pv.0 .*)$/\1 --encrypted --passphrase="'"${LUKS_PASSWORD}"'"/' \
           -re 's/^(.* pv.1 .*)$/\1 --encrypted --passphrase="'"${LUKS_PASSWORD}"'"/' "${KS_INCLUDE}"
  else
    # set up encryption via cryptsetup
    # anaconda sets the aes-xts-plain64 cipher out of the box. no bets on the rest tho. YOLO.
    luksopts="-c aes-xts-plain64 -s 512 -h sha256 -i 5000 --align-payload=8192"
    # shellcheck disable=SC2086
    {
      printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksFormat ${luksopts} "${sys_luks_source}"
      if [ ! -z "${data_luks_source}" ] ; then
        printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksFormat ${luksopts} "${data_luks_source}"
      fi
    }
  fi
fi

if [ ! -z "${KS_INCLUDE}" ] ; then
  # write LVM volgroup config for kickstart here for handoff
  {
    printf '%s\n' 'volgroup system pv.0'
    if [ "${DATA_PARTITION}" == "yes" ] ; then
      printf '%s\n' 'volgroup data pv.1'
      printf '%s\n'  'logvol none --vgname=data --thinpool --name=thinpool --size=18432 --grow'
    fi
  } >> "${KS_INCLUDE}"
else
  # we're *making* LVM volume groups here

  # system
  system_pv=""
  if [ -z "${LUKS_PASSWORD}" ] ; then
    if [ -e /dev/md/system ] ; then
      system_pv=/dev/md/system
    else
      for part in ${sys_devs} ; do system_pv="${part}" ; done
    fi
  else
    # we have a cryptodev, open it and get the uuid
    system_pv=$(luks_open "${sys_luks_source}")
  fi
  lvm_create system "${system_pv}"

  if [ "${DATA_PARTITION}" == "yes" ] ; then
    # data
    data_pv=""
    if [ -z "${LUKS_PASSWORD}" ] ; then
      if [ -e /dev/bcache0 ] ; then
        data_pv=/dev/bcache0
      elif [ -e /dev/md/data ] ; then
        data_pv=/dev/md/data
      else
        for part in ${data_devs} ; do data_pv="${part}" ; done
      fi
    else
      data_pv=$(luks_open "${data_luks_source}")
    fi
    lvm_create data "${data_pv}"

    lvcreate -l100%FREE --type thin-pool --thinpool thinpool data
    sleep 1
  fi

fi

# at this point we've virtualized away block devices :) go forth and create logical volumes!

# lvname vgname fstype sizeM (lmount)
ready_lv swap system swap 512
ready_lv root system ext4 18432 /

if [ "${DATA_PARTITION}" == "yes" ] ; then
  ready_thin libvirt        data thinpool ext4 18432 /var/lib/libvirt
  ready_thin http_sys       data thinpool ext4 512   /usr/share/nginx/html
  ready_thin http_bootstrap data thinpool ext4 8192  /usr/share/nginx/html/bootstrap
fi

if [ ! -z "${KS_INCLUDE}" ] ; then
  # install bootloader
  printf 'bootloader --append=" crashkernel auto" --location=mbr\n' >> "${KS_INCLUDE}"
else
  # mount errything
  make_n_mount

  # save fstab to new system
  mkdir "${TARGETPATH}/etc"
  sed 's@'"${TARGETPATH}"'@@g' < "${FSTAB}" > "${TARGETPATH}/etc/fstab"

  # do we have arrays?
  mds_defined=( /dev/md/* )
  if [ ! -z "${mds_defined[*]+x}" ] ; then
    mkdir  "${TARGETPATH}/etc/mdadm"
    mdadm --examine --scan > "${TARGETPATH}/etc/mdadm/mdadm.conf"
  fi

  if [ ! -z "${LUKS_PASSWORD}" ] ; then
    if [ "${DATA_PARTITION}" == "yes" ] ; then
      # if we set up luks, rekey the data pv now.
      mkdir "${TARGETPATH}/etc/keys"
      dd if=/dev/random of="${TARGETPATH}/etc/keys/datavol.luks" bs=1 count=32
      printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksAddKey "${data_luks_source}" "${TARGETPATH}/etc/keys/datavol.luks" -
      printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksRemoveKey "${data_luks_source}"
      dataluks=$(pvs -S vg_name=data --noheadings -o pv_name)
      dataluks="${dataluks##*/luks-}"
      printf 'luks-%s UUID=%s /etc/keys/datavol.luks luks\n' "${dataluks}" "${dataluks}" >> "${TARGETPATH}/etc/crypttab"
    fi

    # configure crypttab
    sysluks=$(pvs -S vg_name=system --noheadings -o pv_name)
    sysluks="${sysluks##*/luks-}"

    {
      printf 'luks-%s UUID=%s none luks\n'                   "${sysluks}"  "${sysluks}"
    } >> "${TARGETPATH}/etc/crypttab"
  fi
fi

# write down the bios_bootdevs for grub handoff later
printf 'BIOS_BOOTDEVS="%s"\n' "${bios_bootdevs}" >> "${ENV_OUTPUT_FILE}"

mkdir -p "${TARGETPATH}/root"
cp "${ENV_OUTPUT_FILE}" /mnt/sysimage/root/fs-env
