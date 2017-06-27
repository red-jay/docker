#!/bin/bash

# this assumes you've got a RAID setup that blockdev-init provided.
# this will reformat everything for LUKS up, but leave the raid volumes intact for speed.

set -eux

# *start* all array volumes
set +e
mdadm --assemble --scan
set -e

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
  read ro < "/sys/block/${shortdev}/md/array_state"
  if [ "${ro}" == "read-auto" ] ; then
    # readwrite the array
    mdadm -w "${raiddev}"
  fi

done

sys_luks_dev=(/dev/md/*system*)
data_luks_dev=(/dev/md/*:data)
boot_md_dev=(/dev/md/*:boot)
efi_md_dev=(/dev/md/*:efi)

# see if we have two fios - if we do, try to set up the cache volume
if [ -b /dev/fioa1 ] && [ -b /dev/fiob1 ] ; then

  # see if they are the same model fio...
  fio_uniqs=$(fio-status | awk '$3 == "Product" {print $1,$2}' | uniq | wc -l)
  if [ "${fio_uniqs}" == "1" ] ; then
    # assemble/start raid
    cachedev=/dev/md/cache
    set +e
    if [ ! -e ${cachedev} ] ; then
      set -e
      mdadm --assemble ${cachedev} /dev/fioa1 /dev/fiob1
    fi
    set -e

    # register bcache volume
    datadev=(/dev/md/*:data)

    # unwind symlink, register in bcache
    # shellcheck disable=SC2128
    {
      datapath="/dev/$(basename "$(readlink "${datadev}")")"
      cachepath="/dev/$(basename "$(readlink /dev/md/cache)")"
      set +e # in case bcache already picked it up
      echo "${datapath}" > /sys/fs/bcache/register
      echo "${cachepath}" > /sys/fs/bcache/register
      set -e
    }
    # HEADSUP: override the data vol for LUKS
    data_luks_dev=/dev/bcache0
  fi
fi


# unwind any symlinks
# shellcheck disable=SC2128
if [ -L "${sys_luks_dev}" ] ; then
  sys_luks_dev="$(dirname "${sys_luks_dev}")/$(readlink "${sys_luks_dev}")"
fi
# shellcheck disable=SC2128
if [ -L "${data_luks_dev}" ] ; then
  sys_luks_dev="$(dirname "${data_luks_dev}")/$(readlink "${data_luks_dev}")"
fi

# reformat luks volumes at this point
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

lvcreate -nvar  -L8G      sysvg
lvcreate -nroot -l70%free sysvg
lvcreate -nswap -L4G      sysvg

# create filesystems
mkfs.xfs  /dev/sysvg/root
mkfs.xfs  /dev/sysvg/var
# shellcheck disable=SC2128
{
  mkfs.ext2 "${boot_md_dev}"
  mkfs.vfat "${efi_md_dev}"
}
# mounts
mkdir -p /mnt/target
mount /dev/sysvg/root  /mnt/target
mkdir /mnt/target/{boot,var}
# shellcheck disable=SC2128
mount "${boot_md_dev}" /mnt/target/boot
mkdir /mnt/target/boot/efi
# shellcheck disable=SC2128
mount "${efi_md_dev}"  /mnt/target/boot/efi
mount /dev/sysvg/var   /mnt/target/var

# save md config
mkdir -p /mnt/target/etc/mdadm
mdadm --examine --scan > /mnt/target/etc/mdadm/mdadm.conf

# re-key data partition
mkdir -p /mnt/target/etc/keys
dd if=/dev/random of=/mnt/target/etc/keys/datavol.luks bs=1 count=32
printf 'changeit' | cryptsetup luksAddKey   ${data_luks_dev} /mnt/target/etc/keys/datavol.luks -
printf 'changeit' | cryptsetup luksRemoveKey ${data_luks_dev} -

# save crypttab
{
  printf '%s UUID=%s none                   luks\n' "${luks_sys_map}"  "${luks_sys_uuid}"
  printf '%s UUID=%s /etc/keys/datavol.luks luks\n' "${luks_data_map}" "${luks_data_uuid}"
} > /mnt/target/etc/crypttab

# save fstab
{
  printf '/dev/sysvg/root /         xfs  defaults                   1 1\n'
  printf '/dev/sysvg/var  /var      xfs  defaults                   1 2\n'
  printf '/dev/md/boot    /boot     ext2 defaults                   1 2\n'
  printf '/dev/md/efi     /boot/efi vfat umask=0077,shortname=winnt 0 2\n'
} > /mnt/target/etc/fstab
