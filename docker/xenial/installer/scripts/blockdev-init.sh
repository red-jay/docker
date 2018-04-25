#!/bin/bash

# attuned to the following setup
# there are 5 disks, to become raid1 efi, raid1 /boot, raid10+hs system vg, raid6 images vg
# vgs will be on LUKS
# disks will be wiped
# disks are gpt labeled with bios boot partition
# disks are larger than 30GB

set -eux

# first step - we are _not_ partitioning the root device
# find it to exclude it - we assume it's partition 1!
rootdisk=$(awk '$2 == "/" { print $1 }' < /proc/mounts)
rootdisk=${rootdisk%1}

# *start* all array volumes and stop any bcaches
# "Unless a more serious error occurred, mdadm will exit with a status of 2 if no changes were made to the array"
set +e
mdadm --assemble --scan
set -e

# walk all bcache...things and remove them
for bcachef in /sys/fs/bcache/*-*-*-*-* ; do
  if [ -f "${bcachef}/stop" ] ; then printf 1 > "${bcachef}/stop" ; fi
  if [ -f "${bcachef}/unregister" ] ; then printf 1 > "${bcachef}/unregister" ; fi
done

# walk all arrays
for raiddev in /dev/md[0-9]* ; do
  shortdev=$(basename "${raiddev}")

  # is the array dev wire up to _anything_?
  set +e
  grep -q "^${shortdev}" /proc/mdstat
  sta=$?
  set -e
  if [ $sta != 0 ] ; then continue ; fi

  # see if array is readwrite
  read -r ro < "/sys/block/${shortdev}/ro"
  if [ "${ro}" == 1 ] ; then
    # readwrite the array
    mdadm -w "${raiddev}"
  fi

  # stop any bcaches now
  while [ -f "/sys/block/${shortdev}/bcache/set/stop" ] || [ -f "/sys/block/${shortdev}/bcache/stop" ] ; do
    if [ -f "/sys/block/${shortdev}/bcache/set/stop" ] ; then echo 1 > "/sys/block/${shortdev}/bcache/set/stop" ; fi
    if [ -f "/sys/block/${shortdev}/bcache/stop" ] ; then echo 1 > "/sys/block/${shortdev}/bcache/stop" ; fi
    sleep 1
  done

  # stop the array
  mdadm -S "${raiddev}"
done

# hold lists of devices for raiding and grubbing
efi_sp_dev=''
boot_dev=''
sys_dev=''
data_dev=''
cache_dev=''

# wipe and label disks
for diskdev in /dev/sd*[^0-9] ; do

  # skip the livefs disk
  if [ "${diskdev}" == "${rootdisk}" ] ; then continue ; fi

  # wipe any existing partitions bits
  for part in ${diskdev}[0-9]* ; do
    wipefs -a "${part}"
  done

  # wipe the partition table
  wipefs -a "${diskdev}"

  # build a partition table on the disk
  parted "${diskdev}" mklabel gpt				# Label
  parted "${diskdev}" mkpart biosboot 1m 5m			# BIOS Boot
  parted "${diskdev}" toggle 1 bios_grub
  parted "${diskdev}" toggle 1 legacy_boot

  parted "${diskdev}" mkpart '"EFI System Partition"' 5m 300m	# EFI
  parted "${diskdev}" toggle 2 esp
  efi_sp_dev="${efi_sp_dev} ${diskdev}2"

  parted "${diskdev}" mkpart sysboot 300m 800m			# /boot
  parted "${diskdev}" toggle 3 raid
  boot_dev="${boot_dev} ${diskdev}3"

  parted "${diskdev}" mkpart primary 800m 24g			# system
  parted "${diskdev}" toggle 4 raid
  sys_dev="${sys_dev} ${diskdev}4"

  parted "${diskdev}" mkpart primary 24g 100%			# vmimages
  parted "${diskdev}" toggle 5 raid
  data_dev="${data_dev} ${diskdev}5"
done

# see if we have two fios - if we do, try to set up the cache volume
if [ -b /dev/fioa ] && [ -b /dev/fiob ] ; then

  # see if they are the same model fio...
  fio_uniqs=$(fio-status | awk '$3 == "Product" {print $1,$2}' | uniq | wc -l)
  if [ "${fio_uniqs}" == "1" ] ; then
    for fio in /dev/fio[ab] ; do

      # check low level block size and capacity.
      fioblklen=$(blockdev --getsize64 "${fio}")
      fiosectsz=$(blockdev --getss "${fio}")

      # table of factory fio sizes -> performance sizing
      case $fioblklen in
        640000000000) new_fioblklen=51200000000 ;; # fio 640 -> 512
        *) new_fioblklen=${fioblklen}           ;; # for devices we didn't map, just treat as okay
      esac

      # if the sector size is not 4k, or not performance sized, reformat fio.
      if [ "${new_fioblklen}" != "${fioblklen}" ] || [ "${fiosectsz}" != 4096 ] ; then
        # fio-detach/attach needs fct dev
        fct=$(fio-status -Fiom.ctrl_dev_path "${fio}")
        fio-detach "${fct}"
        fio-format -y -b4096 "-a${new_fioblklen}B" "${fct}"
        fio-attach "${fct}"
      fi

      # wipe partitions, label
      for part in $fio[0-9]* ; do
        if [ -b "${part}" ] ; then wipefs -a "${part}" ; fi
      done
      wipefs -a "${fio}"

      parted "${fio}" mklabel gpt
      parted "${fio}" mkpart cache 1m 100%
      parted "${fio}" toggle 1 raid
      cache_dev="${fio}1 ${cache_dev}"
    done
  fi
fi

# save the sys,data vols for LUKS
sys_luks_dev=/dev/md/system
data_luks_dev=/dev/md/data

# counts of devices by array fun
efi_sp_a=( ${efi_sp_dev} )
boot_a=( ${boot_dev} )
sys_a=( ${sys_dev} )
data_a=( ${data_dev} )

# RAID level configuration - efi, boot are _always_ 1
sys_raid_lev=1
data_raid_lev=1

# if we have 4 or more system disks, flip raid mode to 10
if [[ "${#sys_a[@]}" -ge 4 ]] ; then
  sys_raid_lev=10
fi
# if we have 4 data disks, flip data raid mode to 10
if [[ "${#data_a[@]}" -eq 4 ]] ; then
  data_raid_lev=10
fi
# if we have more than 4 data disks, flip data raid mode to 6
if [[ "${#data_a[@]}" -gt 4 ]] ; then
  data_raid_lev=6
fi

# create raid volumes - we want word splitting on the _dev variables
# shellcheck disable=SC2086
{
  mdadm --create /dev/md/efi        -Nefi    -l1                  -n"${#efi_sp_a[@]}" --metadata=1.0 ${efi_sp_dev}
  wipefs -a      /dev/md/efi
  mdadm --create /dev/md/boot       -Nboot   -l1                  -n"${#boot_a[@]}"   --metadata=1.0 ${boot_dev}
  wipefs -a      /dev/md/boot
  # linux lets you do this. don't think about how _too_ hard.
  mdadm --create "${sys_luks_dev}"  -Nsystem -l"${sys_raid_lev}"  -n"${#sys_a[@]}"    --metadata=1.1 ${sys_dev}
  wipefs -a      "${sys_luks_dev}"
  mdadm --create "${data_luks_dev}" -Ndata   -l"${data_raid_lev}" -n"${#data_a[@]}"   --metadata=1.1 ${data_dev}
  wipefs -a      "${data_luks_dev}"
}

# if we have cache_dev, make that array, then the bcache
if [ ! -z "${cache_dev}" ] ; then
# shellcheck disable=SC2086
mdadm --create /dev/md/cache  -Ncache  -l1  -n2 --metadata=1.1 ${cache_dev}
wipefs -a      /dev/md/cache

# create bcache volume - the data offset here is for RAID5/6
make-bcache --data-offset 161280k --block 4k --bucket 4M -B "${data_luks_dev}"
make-bcache --block 4k --bucket 4M -C /dev/md/cache
cacheuuid=$(bcache-super-show /dev/md/cache |awk '$1 ~ "cset.uuid" { print $2 }')
# sleep for bcache :x
while [ ! -f /sys/block/bcache0/bcache/attach ] ; do sleep 1 ; done
echo "${cacheuuid}" > /sys/block/bcache0/bcache/attach
echo writeback > /sys/block/bcache0/bcache/cache_mode

# HEADSUP: override the data vol for LUKS
data_luks_dev=/dev/bcache0
fi

# unwind any symlinks
if [ -L "${sys_luks_dev}" ] ; then
  sys_luks_dev="$(dirname "${sys_luks_dev}")/$(readlink "${sys_luks_dev}")"
fi
if [ -L "${data_luks_dev}" ] ; then
  data_luks_dev="$(dirname "${data_luks_dev}")/$(readlink "${data_luks_dev}")"
fi

# create luks volumes
luksopts="-c aes-xts-plain64 -s 512 -h sha256 -i 5000 --align-payload=8192"
# shellcheck disable=SC2086
printf 'changeit' | cryptsetup luksFormat ${luksopts} "${sys_luks_dev}" -
luks_sys_uuid=$(file -s "${sys_luks_dev}" | awk -F'UUID: ' '{print $2}')
luks_sys_map="luks-${luks_sys_uuid}"
printf 'changeit' | cryptsetup luksOpen "${sys_luks_dev}" "${luks_sys_map}" -

# shellcheck disable=SC2086
printf 'changeit' | cryptsetup luksFormat ${luksopts} "${data_luks_dev}" -
luks_data_uuid=$(file -s "${data_luks_dev}" | awk -F'UUID: ' '{print $2}')
luks_data_map="luks-${luks_data_uuid}"
printf 'changeit' | cryptsetup luksOpen "${data_luks_dev}" "${luks_data_map}" -

# create LVM structures
# shellcheck disable=SC2086
{
  lvopts="--dataalignment 8192s"
  pvcreate "/dev/mapper/${luks_sys_map}"  ${lvopts}
  pvcreate "/dev/mapper/${luks_data_map}" ${lvopts}

  vgcreate sysvg  "/dev/mapper/${luks_sys_map}"  ${lvopts}
  vgcreate datavg "/dev/mapper/${luks_data_map}" ${lvopts}
}

lvcreate -nvar     -L8G      sysvg
lvcreate -nroot    -l70%free sysvg
lvcreate -nswap    -L4G      sysvg
lvcreate -nlibvirt -L72G     datavg

# create filesystems
mkfs.xfs  /dev/sysvg/root
mkfs.xfs  /dev/sysvg/var
mkfs.ext2 /dev/md/boot
mkfs.vfat /dev/md/efi
mkfs.xfs  /dev/datavg/libvirt

# mounts
mount /dev/sysvg/root     /mnt/target
mkdir /mnt/target/{boot,var}
mount /dev/md/boot        /mnt/target/boot
mkdir /mnt/target/boot/efi
mount /dev/md/efi         /mnt/target/boot/efi
mount /dev/sysvg/var      /mnt/target/var
mkdir -p /mnt/target/var/lib/libvirt
mount /dev/datavg/libvirt /mnt/target/var/lib/libvirt

# save md config
mkdir -p /mnt/target/etc/mdadm
mdadm --examine --scan > /mnt/target/etc/mdadm/mdadm.conf

# re-key data partition
mkdir -p /mnt/target/etc/keys
dd if=/dev/random of=/mnt/target/etc/keys/datavol.luks bs=1 count=32
printf 'changeit' | cryptsetup luksAddKey    "${data_luks_dev}" /mnt/target/etc/keys/datavol.luks -
printf 'changeit' | cryptsetup luksRemoveKey "${data_luks_dev}" -

# save crypttab
{
  printf '%s UUID=%s none                   luks\n' "${luks_sys_map}"  "${luks_sys_uuid}"
  printf '%s UUID=%s /etc/keys/datavol.luks luks\n' "${luks_data_map}" "${luks_data_uuid}"
} > /mnt/target/etc/crypttab

# save fstab
{
  printf '/dev/sysvg/root     /                xfs  defaults                   1 1\n'
  printf '/dev/sysvg/var      /var             xfs  defaults                   1 2\n'
  printf '/dev/md/boot        /boot            ext2 defaults                   1 2\n'
  printf '/dev/md/efi         /boot/efi        vfat umask=0077,shortname=winnt 0 2\n'
  printf '/dev/datavg/libvirt /var/lib/libvirt xfs  defaults                   1 2\n'
} > /mnt/target/etc/fstab

# if the data array is trying to sync, idle it immediately
data_md_dev=$(basename "$(readlink /dev/md/data)")
printf 'idle' > "/sys/block/${data_md_dev}/md/sync_action"
