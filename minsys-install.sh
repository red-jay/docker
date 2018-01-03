#!/bin/bash

set -eux

# clamp RAID speed while bootstrapping
sysctl -w dev.raid.speed_limit_max=1000

# unpack 
# FIXME: debootstrap _shouldn't_ return 1 here...
set +e
debootstrap archive /mnt/sysimage
set -e

# rewire apt to use the offline repository w/o screaming
printf 'deb [trusted=yes] file:///mnt/repository/ archive main\n' > /mnt/sysimage/etc/apt/sources.list
mkdir -p /mnt/sysimage/mnt/repository

# bind live fs to target
mount --bind /dev        /mnt/sysimage/dev
mount --bind /sys        /mnt/sysimage/sys
mount --bind /proc       /mnt/sysimage/proc
mount -t tmpfs tmpfs     /mnt/sysimage/run
mount --bind /repository /mnt/sysimage/mnt/repository

# install more stuff
chroot_ag() {
  chroot /mnt/sysimage env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get "${@}"
}

chroot_ag update
chroot_ag install -y debsums
chroot_ag install -y openssh-server
chroot_ag install -y linux-generic
chroot_ag install -y lvm2 thin-provisioning-tools cryptsetup mdadm xfsprogs bcache-tools

# get the target kernel version
target_kver=(/mnt/sysimage/boot/vmlinuz-*-generic)
target_kver=${target_kver#/mnt/sysimage/boot/vmlinuz-}

# disable grub os-prober unconditionally.
printf 'GRUB_DISABLE_OS_PROBER=true\n' >> /mnt/sysimage/etc/default/grub

# are you installing via a serial console _right now_? if so, config grub serialisms.
set +u
if [ -z "${CONFIG_SERIAL_INSTALL}" ] ; then
  set -u
  CONFIG_SERIAL_INSTALL=$(tty)
fi
set -u

# serial install flag can be.../dev/ttyS (serial) | /dev/? (not serial) | a number (forcedserial) | not a number (garbage)
case "${CONFIG_SERIAL_INSTALL}" in
  /dev/ttyS*) CONFIG_SERIAL_INSTALL="${CONFIG_SERIAL_INSTALL#/dev/ttyS}" ;;
  /dev/*) unset CONFIG_SERIAL_INSTALL ;;
  [0-9]*) : ;; # technically this line is just checking if it _starts_ with a number.
  *)
    echo "CONFIG_SERIAL_INSTALL should be set to the unit number of the serial port (likely 0 or 1)" 1>&2
    unset CONFIG_SERIAL_INSTALL
    ;;
esac

set +u
# now check if CONFIG_SERIAL_INSTALL is still set
if [ ! -z "${CONFIG_SERIAL_INSTALL}" ] ; then
  set -u
  {
    printf 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=%s --word=8 --parity=no --stop=1"\n' "${CONFIG_SERIAL_INSTALL}"
    printf 'GRUB_TERMINAL="serial"\n'
  } >> /mnt/sysimage/etc/default/grub
  cmdline=$(augtool -r /mnt/sysimage print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
  cmdline="${cmdline#* = }"
  cmdline="${cmdline/splash/}"
  # since we know the _last_ three characters of this are quoting, splice like this
  cmdline="${cmdline:0:-3} console=ttyS${CONFIG_SERIAL_INSTALL},115200n8${cmdline: -3}"
  augtool -r /mnt/sysimage -s set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "${cmdline}"
fi
set -u

# if we have a fio here, put a fio there
shopt -s nullglob
set +u
fio=(/dev/fio[a-z])
# shellcheck disable=SC2128
if [ ! -z "${fio}" ] ; then
  chroot_ag install -y dkms fio-* iomemory-vsl-dkms
  chroot /mnt/sysimage chmod +x /var/lib/dkms/iomemory-vsl/*/*/*.sh
  chroot /mnt/sysimage env LC_ALL=C dkms autoinstall -k "${target_kver}"
  printf 'iomemory-vsl\n' >> /mnt/sysimage/etc/initramfs-tools/modules
fi

# if we have a fio _array_, install the scripts for initramfs startup
fio_array=(/sys/block/md*/slaves/fio*)
# shellcheck disable=SC2128
if [ ! -z "${fio_array}" ] ; then
  fio_array=${fio_array%/slaves/fio*}
  fio_array=${fio_array#/sys/block/}
  read fio_raidlevel < "/sys/block/${fio_array}/md/level"
  fio_arrayname=$(mdadm -D /dev/"${fio_array}" | awk -F: '$1 ~ "Name" { gsub(" .*","",$3) ; print $3 }')
  fio_devs=''
  fio_slaves=(/sys/block/md123/slaves/fio*)
  for dev in "${fio_slaves[@]}" ; do
    fio_devs="/dev/${dev#/sys/block/${fio_array}/slaves/},${fio_devs}"
  done
  printf 'softdep %s pre: iomemory-vsl\n' "${fio_raidlevel}" >> /mnt/sysimage/etc/modprobe.d/iomemory-vsl.conf
  cp 'iomemory_md.sh' /mnt/sysimage/etc/initramfs-tools/scripts/local-top/iomemory_md
  cmdline=$(augtool -r /mnt/sysimage print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
  cmdline="${cmdline#* = }"
  # since we know the _last_ three characters of this are quoting, splice like this
  # while we're here, do not print the last character of fio_devs (a comma)
  cmdline="${cmdline:0:-3} iomemory_md=${fio_arrayname}:${fio_devs:0:-1}${cmdline: -3}"
  augtool -r /mnt/sysimage -s set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "${cmdline}"
fi
set -u
shopt -u nullglob

# rebuild the initrd now, install grub, generate config
chroot /mnt/sysimage env LC_ALL=C mkinitramfs -o "/boot/initrd.img-${target_kver}" "${target_kver}"

bootdev=$(basename "$(awk '$2 == "/mnt/sysimage/boot" { print $1 }' < /proc/mounts)")
bootdisk=''
if [ -d "/sys/class/block/${bootdev}/slaves" ] ; then
  # md device
  for slave in /sys/class/block/${bootdev}/slaves/* ; do
    sdev=$(basename "${slave}")
    sdev="${sdev/[0-9]*/}"
    bootdisk="/dev/${sdev} ${bootdisk}"
  done
else
  # disk?
  bootdisk="/dev/${bootdev/[0-9]*/}"
fi

for disk in ${bootdisk} ; do
  chroot /mnt/sysimage grub-install "${disk}"
done

chroot /mnt/sysimage grub-mkconfig -o /boot/grub/grub.cfg

# set the root password
# shellcheck disable=SC2016
rpw_hash='$6$C8gWRNlF$TVgBTa9Pu8CRIkDoWS2lK2gHaV9egxVmh2HOWExRvxQeN30O/D7vqtPu89lJDVTVY6ImGwiVQLJ2hZyWPLFdZ.' # changeit
rpw_date=$(($(date +%s) / 86400))
augtool -r /mnt/sysimage -s set /files/etc/shadow/root/password "${rpw_hash}"
augtool -r /mnt/sysimage -s set /files/etc/shadow/root/lastchange_date "${rpw_date}"

# explicitly install resolvconf so we can configure it
chroot_ag install -y resolvconf
sed -i -e '/lo.*/d' /mnt/sysimage/etc/resolvconf/interface-order

# additional software
chroot_ag install -y ethtool apparmor irqbalance
