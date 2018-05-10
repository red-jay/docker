#!/usr/bin/env bash

set -eux

tar xpf "${1}" -C /mnt/sysimage

mount -o bind /dev/ /mnt/sysimage/dev/
mount -o bind /proc/ /mnt/sysimage/proc/
mount -o bind /sys/ /mnt/sysimage/sys/

chroot /mnt/sysimage /bin/run-parts /scripts/grub-config
chroot /mnt/sysimage /bin/run-parts /scripts/dracut-config

: >   /mnt/sysimage/etc/machine-id
rm -f /mnt/sysimage/var/lib/dbus/machine-id

rm -f /mnt/sysimage/etc/resolv.conf
ln -s /run/resolvconf/resolv.conf /mnt/sysimage/etc/resolv.conf
