#!/bin/bash

# attuned to the following setup
# there is 1 disk, to become efi, /boot, system vg, data vg
# disks will be wiped
# disks are gpt labeled with bios boot partition
# disks are larger than 30GB
# there isn't any bcache
# there isn't any array

set -eux

# first step - we are _not_ partitioning the root device
# find it to exclude it - we assume it's partition 1!
rootdisk=$(awk '$2 == "/" { print $1 }' < /proc/mounts)
rootdisk=${rootdisk%1}

# hold lists of devices for raiding and grubbing
efi_sp_dev=''
boot_dev=''
sys_dev=''
data_dev=''
cache_dev=''

rootdisk=""
# wipe and label disks
for diskdev in /dev/[sv]d*[^0-9] ; do

  # skip the livefs disk
  if [ "${diskdev}" == "${rootdisk}" ] ; then continue ; fi

  shopt -s nullglob
  # wipe any existing partitions bits
  for part in ${diskdev}[0-9]* ; do
    wipefs -a "${part}"
  done
  shopt -u nullglob

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
  boot_dev="${boot_dev} ${diskdev}3"

  parted "${diskdev}" mkpart primary 800m 24g			# system
  sys_dev="${sys_dev} ${diskdev}4"

  parted "${diskdev}" mkpart primary 24g 100%			# data
  data_dev="${data_dev} ${diskdev}5"

  # build lvm
  lvopts="--dataalignment 8192s"
  # shellcheck disable=SC2086
  {
    pvcreate ${diskdev}4 ${lvopts}
    pvcreate ${diskdev}5 ${lvopts}
    lvopts="${lvopts} --autobackup n"
    vgcreate sysvg  ${diskdev}4 ${lvopts}
    vgcreate datavg ${diskdev}5 ${lvopts}
  }
  mkfs.ext2 ${diskdev}3
  mkfs.vfat ${diskdev}2
  rootdisk="${diskdev}"
done

lvopts="--autobackup n"
# shellcheck disable=SC2086
{
  lvcreate -nvar     -L8G      sysvg  ${lvopts}
  lvcreate -nroot    -l70%free sysvg  ${lvopts}
  lvcreate -nswap    -L4G      sysvg  ${lvopts}
  lvcreate -nlibvirt -L36G     datavg ${lvopts}
}
# create filesystems
mkfs.xfs  /dev/sysvg/root
mkfs.xfs  /dev/sysvg/var
mkfs.xfs  /dev/datavg/libvirt

# mounts
mount /dev/sysvg/root     /mnt/target
mkdir /mnt/target/{boot,var}
mount ${rootdisk}3        /mnt/target/boot
mkdir /mnt/target/boot/efi
mount ${rootdisk}2         /mnt/target/boot/efi
mount /dev/sysvg/var      /mnt/target/var
mkdir -p /mnt/target/var/lib/libvirt
mount /dev/datavg/libvirt /mnt/target/var/lib/libvirt

# save fstab
mkdir -p /mnt/target/etc
{
  printf '/dev/sysvg/root     /                xfs  defaults                   1 1\n'
  printf '/dev/sysvg/var      /var             xfs  defaults                   1 2\n'
  printf '%s          /boot            ext2 defaults                   1 2\n' "${rootdisk}3"
  printf '%s          /boot/efi        vfat umask=0077,shortname=winnt 0 2\n' "${rootdisk}2"
  printf '/dev/datavg/libvirt /var/lib/libvirt xfs  defaults                   1 2\n'
} > /mnt/target/etc/fstab
