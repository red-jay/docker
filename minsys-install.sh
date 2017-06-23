#!/bin/bash

set -eux

# clamp RAID speed while bootstrapping
sysctl -w dev.raid.speed_limit_max=1000

# unpack 
# FIXME: debootstrap _shouldn't_ return 1 here...
set +e
debootstrap archive /mnt/target
set -e

# rewire apt to use the offline repository w/o screaming
printf 'deb [trusted=yes] file:///mnt/repository/ archive main\n' > /mnt/target/etc/apt/sources.list
mkdir -p /mnt/target/mnt/repository

# bind live fs to target
mount --bind /dev /mnt/target/dev
mount --bind /sys /mnt/target/sys
mount --bind /proc /mnt/target/proc
mount --bind /repository /mnt/target/mnt/repository

# install more stuff
chroot_ag() {
  chroot /mnt/target env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get "${@}"
}

chroot_ag update
chroot_ag install -y debsums
chroot_ag install -y linux-generic
chroot_ag install -y lvm2 thin-provisioning-tools cryptsetup mdadm xfsprogs bcache-tools

# get the target kernel version
target_kver=(/mnt/target/boot/vmlinuz-*-generic)
target_kver=${target_kver#/mnt/target/boot/vmlinuz-}

# if we have a fio here, put a fio there
fio=(/dev/fio[a-z])
# shellcheck disable=SC2128
if [ ! -z "${fio}" ] ; then
  chroot_ag install -y dkms fio-* iomemory-vsl-dkms
  chroot /mnt/target chmod +x /var/lib/dkms/iomemory-vsl/*/*/*.sh
  chroot /mnt/target env LC_ALL=C dkms autoinstall ${target_kver}
  printf 'iomemory-vsl\n' >> /mnt/target/etc/initramfs-tools/modules
fi

# if we have a fio _array_, install the scripts for initramfs startup
fio_array=(/sys/block/md*/slaves/fio*)
# shellcheck disable=SC2128
if [ ! -z "${fio_array}" ] ; then
  fio_array=${fio_array%/slaves/fio*}
  fio_array=${fio_array#/sys/block/}
  read fio_raidlevel < "/sys/block/${fio_array}/md/level"
  fio_arrayname=$(mdadm -D /dev/${fio_array} | awk -F: '$1 ~ "Name" { gsub(" .*","",$3) ; print $3 }')
  fio_devs=''
  fio_slaves=(/sys/block/md123/slaves/fio*)
  for dev in ${fio_slaves[@]} ; do
    fio_devs="/dev/${dev#/sys/block/${fio_array}/slaves/},${fio_devs}"
  done
  printf 'softdep %s pre: iomemory-vsl\n' "${fio_raidlevel}" >> /mnt/target/etc/modprobe.d/iomemory-vsl.conf
  cp 'iomemory_md.sh' /mnt/target/etc/initramfs-tools/scripts/local-top/iomemory_md
  cmdline=$(augtool -r /mnt/target print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
  cmdline="${cmdline#* = }"
  # since we know the _last_ three characters of this are quoting, splice like this
  # while we're here, do not print the last character of fio_devs (a comma)
  cmdline="${cmdline:0:-3} iomemory_md=${fio_arrayname}:${fio_devs:0:-1}${cmdline: -3}"
  augtool -r /mnt/target set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "${cmdline}"
fi
