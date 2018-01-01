#!/usr/bin/env bash

set -eu
set -o pipefail
shopt -s nullglob

# steal a fs here for de bugs
exec 3>&1
NOOP=1

get_lsblk_val() {
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

get_lsblk_dev() {
  local dev
  dev="${1}"
  if [ -b "/dev/${dev}" ] ; then
    dev="/dev/${dev}"
  elif [ -b "/dev/mapper/${dev}" ] ; then
    dev="/dev/mapper/${dev}"
  fi
  echo "${dev}"
}

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
      # stitch in device paths here.
      blkname=$(get_lsblk_dev "${blkname}")
      nblkname=$(get_lsblk_dev "${nblkname}")
    ;;
    part)
      local blkname disk part
      blkname=$(get_lsblk_val "${blk}" NAME)
      part=${blkname##*[[:alpha:]]}
      disk=${blkname%${part}}
      # if the disk needs a check we can ask now.
      key2disk "NAME=\"${disk}\""
      # resize the partition table. if there is nothing to do here, exit now.
      # rewrite the disk variable here for growpart.
      disk=$(get_lsblk_dev "${disk}")
    ;;
    disk)
      local blkname
      blkname=$(get_lsblk_val "${blk}" NAME)
      echo "${blkname}"
    ;;
  esac
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

make-bcache () {
  if [ "${NOOP}" -eq 0 ] ; then command make-bcache "${@}" ; else echo "make-bcache" "${@}" 1>&3 ; fi
}

cryptsetup () {
  if [ "${NOOP}" -eq 0 ] ; then command cryptsetup "${@}" ; else echo "cryptsetup" "${@}" 1>&3 ; fi
}

luks_open () {
  local linkunwind dir candidate luks_uuid
  candidate="${1}"
  dir="${candidate%/*}"
  if [ -L "${candidate}" ] ; then linkunwind="$(readlink "${candidate}")" ; else linkunwind="${candidate##*/}" ; fi
  luks_map=$(file -s "${dir}/${linkunwind}" | awk -F'UUID: ' '{print $2}')
  luks_map="luks-${luks_map}"
  printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksOpen "${candidate}" "${luks_map}" -
  echo "/dev/mapper/${luks_map}"
}

# get rootdisk, and the repodisk if there
repodisk=$(key2disk 'MOUNTPOINT="/run/install/repo"')
repodisk=${repodisk##*/}
rootdisk=$(key2disk 'MOUNTPOINT="/"')
rootdisk=${rootdisk##*/}

# these disks are skipped while partitioning as they have our installers (and are in use!)
installdisks=" ${repodisk} ${rootdisk} "

# determine if we are running in anaconda or not - this will set up functions to either directly format the disk or spit out kickstart directives.
# we need the _grandparent_ pid if we're called from %pre (and not embedded in ks!)
in_anaconda=0
ppid=$(cut -d' ' -f4 < /proc/$$/stat)
gpid=$(cut -d' ' -f4 < "/proc/${ppid}/stat")
# parsing /proc/pid/cmdline sucks.
while read -r -d $'\0' cmdl ; do
  case $cmdl in
    /sbin/anaconda) in_anaconda=1 ;;
  esac
done < "/proc/${gpid}/cmdline"

# if the installer set aside the luks_flag, set the password now.
LUKS_PASSWORD=""
if [ -f /tmp/luks_flag ] ; then LUKS_PASSWORD="changeit" ; fi

# minimum required disk size
MINSZ=32036093952	# 32G

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
    if [ -f "${bcachef}/unregister" ] ; then if [ "${NOOP}" -eq 0 ] ; then printf 1 > "${bcachef}/unregister" ; else echo "${bcachef}/unregister" ; fi ; fi
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

wipedisk () {
  local part disk
  disk="${1}"
  for part in /dev/${disk}[0-9]* ; do wipefs -a "${part}" ; done
  wipefs -a "/dev/${disk}" > /dev/null
}

partition_disk () {
  local disk raidflag partition
  partition="0"
  raidflag="1"
  disk="/dev/${1}"
  [ ! -z "${2+x}" ] && {
    raidflag="${2}"
  }
  # partition label
  parted "${disk}" mklabel gpt > /dev/null

  # legacy BIOS boot partition
  {
    parted "${disk}" mkpart biosboot 1m 5m && partition=$((partition + 1))
    parted "${disk}" toggle "${partition}" bios_grub
    parted "${disk}" toggle "${partition}" legacy_boot
  } > /dev/null 2>&1
  echo "biosboot=${disk}${partition}"

  # EFI system partition
  {
    parted "${disk}" mkpart '"EFI System Partition"' 5m 300m && partition=$((partition + 1))
    parted "${disk}" toggle "${partition}" boot
  } > /dev/null 2>&1
  echo "efiboot=${disk}${partition}"

  # /boot partition
  {
    parted "${disk}" mkpart sysboot 300m 800m && partition=$((partition + 1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null 2>&1
  echo "sysboot=${disk}${partition}"

  # system partition
  {
    parted "${disk}" mkpart system 800m 24g && partition=$((partition + 1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null 2>&1
  echo "system=${disk}${partition}"

  # data partition
  {
    parted "${disk}" mkpart data 24g 100% && partition=$((partition + 1))
    if [ "${raidflag}" -gt 1 ] ; then
      parted "${disk}" toggle "${partition}" raid
    fi
  } > /dev/null 2>&1
  echo "data=${disk}${partition}"
}

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

# call get_arrays _once_ for stopping
arraylist=$(get_arrays)
# stop bcache here (which also flips arrays on)
stop_bcache

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
elif [ "${disknr}" -gt "2" ] ; then
  # do we have flash or spinny disks?
  candidate_disks=$(get_baseblocks queue/rotational=1)
  flash_disks=$(get_baseblocks queue/rotational=0)
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
if [ "${in_anaconda}" -eq 1 ] ; then
  for part in ${bios_bootdevs} ; do s=${part##*/} ; printf 'part biosboot --fstype=biosboot --onpart=%s\n' "${s}" ; done > /tmp/part-include
fi

# create arrays, write kickstart config or setup LVM
if [ "${candidate_disk_nr}" -gt 1 ] ; then
  # shellcheck disable=SC2086
  {
    mdadm --create /dev/md/efi    -Nefi    -l"${efiboot_raid_level}" -n "$(count_words "${efi_bootdevs}")" --metadata=1.0 ${efi_bootdevs}
    wipefs      -a /dev/md/efi
    mdadm --create /dev/md/boot   -Nboot   -l"${sysboot_raid_level}" -n "$(count_words "${sys_bootdevs}")" --metadata=1.0 ${sys_bootdevs}
    wipefs      -a /dev/md/boot
    mdadm --create /dev/md/system -Nsystem -l"${system_raid_level}"  -n "$(count_words "${sys_devs}")"     --metadata=1.1 ${sys_devs}
    wipefs      -a /dev/md/system
    mdadm --create /dev/md/data   -Ndata   -l"${data_raid_level}"    -n "$(count_words "${data_devs}")"    --metadata=1.1 ${data_devs}
    wipefs      -a /dev/md/data
  }

  # format EFI ESP
  mkfs.vfat -F32 /dev/md/efi

  if [ "${in_anaconda}" -eq 1 ] ; then
    {
      # partitions
      i=0 ; for part in ${efi_bootdevs}  ; do s=${part##*/} ; i=$(( i + 1 ))
        printf 'part raid.0%s --fstype="mdmember" --noformat --onpart=%s\n' "${i}" "${s}" ; done
      i=0 ; for part in ${sys_bootdevs}  ; do s=${part##*/} ; i=$(( i + 1 ))
        printf 'part raid.1%s --fstype="mdmember" --noformat --onpart=%s\n' "${i}" "${s}" ; done
      i=0 ; for part in ${sys_devs}      ; do s=${part##*/} ; i=$(( i + 1 ))
        printf 'part raid.2%s --fstype="mdmember" --noformat --onpart=%s\n' "${i}" "${s}" ; done
      i=0 ; for part in ${data_devs}     ; do s=${part##*/} ; i=$(( i + 1 ))
        printf 'part raid.3%s --fstype="mdmember" --noformat --onpart=%s\n' "${i}" "${s}" ; done

      # RAIDs
      printf 'raid pv.0      --device=system --fstype="lvmpv" --level=%s --useexisting\n' "${system_raid_level}"
      printf 'raid /boot     --device=boot   --fstype="ext2"  --useexisting --label="/boot"\n'
      printf 'raid /boot/efi --device=efi    --fstype="efi"   --useexisting --label="EFISP" --noformat --fsoptions="umask=0077,shortname=winnt"\n'
      printf 'raid pv.1      --device=data   --fstype="lvmpv" --level=%s --useexisting\n' "${data_raid_level}"
    } >> /tmp/part-include
  fi
else
  if [ "${in_anaconda}" -eq 1 ] ; then
    {
      # partitions
      for part in ${efi_bootdevs} ; do s=${part##*/} ; printf 'part /boot/efi --fstype="efi"   --onpart=%s\n' "${s}" ; done
      for part in ${sys_bootdevs} ; do s=${part##*/} ; printf 'part /boot     --fstype="ext2"  --onpart=%s\n' "${s}" ; done
      for part in ${sys_devs}     ; do s=${part##*/} ; printf 'part pv.0      --fstype="lvmpv" --onpart=%s\n' "${s}" ; done
      for part in ${data_devs}    ; do s=${part##*/} ; printf 'part pv.1      --fstype="lvmpv" --onpart=%s\n' "${s}" ; done
    } >> /tmp/part-include
  fi
fi

if [ "${flash_disk_nr}" -gt 1 ] ; then
  # shellchek disable=SC2086
  mdadm --create /dev/md/cache -Ncache -l"${cache_raid_level}" -n "$(count_words "${cache_devs}")" --metadata=1.1 ${cache_devs}
  # run stop_bcache here as it may awaken upon RAID assembly(!)
  stop_bcache
  wipefs      -a /dev/md/cache

  if [ "${in_anaconda}" -eq 1 ] ; then
    {
      # partitions
      i=0 ; for part in ${cache_devs} ; do s=${part##*/} ; i=$(( i + 1 ))
        printf 'part raid9%s --fstype="mdmember" --noformat --onpart=%s\n' "${i}" "${s}" ; done

      # RAIDs
      # RHEL/Fedora don't know what bcache is, so don't...tell them directly ;)
    } >> /tmp/part-include
  fi
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
    wipefs -a /dev/bcache0
  fi
  # this is where we trick anaconda by replacing pv.1
  if [ "${in_anaconda}" -eq 1 ] ; then
    sed -i -e 's/.* pv.1 .*/part pv.1 --fstype="lvmpv" --onpart="bcache0"/' /tmp/part-include
  fi
fi

# if we're asked to encrypt do that here...
data_luks_source=""
sys_luks_source=""
if [ -b /dev/bcache0 ] ; then
  data_luks_source="/dev/bcache0"
elif [ -e /dev/md/data ] ; then
  data_luks_source=$(readlink /dev/md/data)
  data_luks_source="/dev/md/${data_luks_source}"
else
  for part in ${data_devs} ; do data_luks_source="${part}" ; done
fi

if [ -e /dev/md/system ] ; then
  sys_luks_source="/dev/md/system"
else
  for part in ${sys_devs} ; do sys_luks_source="${part}" ; done
fi

if [ ! -z "${LUKS_PASSWORD}" ] ; then
  if [ "${in_anaconda}" -eq 1 ] ; then
    # rewrite part-include pv.0, pv.1 devices
    sed -i -e 's/(.* pv.0 .*)/\1 --encrypted --passphrase="'"${LUKS_PASSWORD}"'"/' /tmp/part-include
    sed -i -e 's/(.* pv.1 .*)/\1 --encrypted --passphrase="'"${LUKS_PASSWORD}"'"/' /tmp/part-include
  else
    # set up encryption via cryptsetup
    # anaconda sets the aes-xts-plain64 cipher out of the box. no bets on the rest tho. YOLO.
    luksopts="-c aes-xts-plain64 -s 512 -h sha256 -i 5000 --align-payload=8192"
    # shellcheck disable=SC2086
    {
      printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksFormat ${luksopts} "${sys_luks_source}"
      printf '%s' "${LUKS_PASSWORD}" | cryptsetup luksFormat ${luksopts} "${data_luks_source}"
    }
  fi
fi

# write LVM config for kickstart here for handoff
if [ "${in_anaconda}" -eq 1 ] ; then
  {
    printf '%s\n' 'volgroup system pv.0'
    printf '%s\n' 'logvol /    --vgname=system --fstype=ext4 --name=root --size=18432'
    printf '%s\n' 'logvol swap --vgname=system               --name=swap --size=512'

    printf '%s\n' 'volgroup data pv.1'
    printf '%s '  'logvol none                            --vgname=data --thinpool                 --name=thinpool'
    printf '%s\n'        '--size=18432 --grow'
    printf '%s '  'logvol /var/lib/libvirt                --vgname=data --thin --poolname=thinpool --name=libvirt'
    printf '%s\n'        '--size=18432 --fsoptions="defaults,discard" --fstype=ext4'
    printf '%s '  'logvol /usr/share/nginx/html           --vgname=data --thin --poolname=thinpool --name=http_sys'
    printf '%s\n'        '--size=512   --fsoptions="defaults,discard" --fstype=ext4'
    printf '%s '  'logvol /usr/share/nginx/html/bootstrap --vgname=data --thin --poolname=thinpool --name=http_bootstrap'
    printf '%s\n'        '--size=8192  --fsoptions="defaults,discard" --fstype=ext4'
  } >> /tmp/part-include
else
  # we're *making* LVM volumes here. and formatting/mounting. ;)

  # /
  root_pv=""
  if [ ! -z "${sys_luks_source}" ] ; then
    if [ -e /dev/md/system ] ; then
      root_pv=/dev/md/system
    else
      for part in ${sys_devs} ; do root_pv="${part}" ; done
    fi
  else
    # we have a cryptodev, open it and get the uuid
    root_pv=$(luks_open "${sys_luks_source}")
  fi
  lvm_create system "${root_pv}"
fi

# install bootloader
if [ "${in_anaconda}" -eq 1 ] ; then
  printf 'bootloader --append=" crashkernel auto" --location=mbr\n' >> /tmp/part-include
fi
