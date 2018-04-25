#!/usr/bin/env bash

. /tmp/fs-layout.env

board_name=""
[ -f /sys/class/dmi/id/board_name ] && read -r board_name < /sys/class/dmi/id/board_name

# install grub cross-bootably
if [ -d /sys/firmware/efi/efivars ] ; then
  # install i386 grub in efi
  for disk in ${BIOS_BOOTDEVS} ; do
    grub2-install --target=i386-pc /dev/${disk}
  done
  grub2-mkconfig | sed 's@linuxefi@linux16@g' | sed 's@initrdefi@initrd16@g' > /boot/grub2/grub.cfg
else
  # install efi grub in i386
  grub2-mkconfig | sed 's@linux16@linuxefi@g' | sed 's@initrd16@initrdefi@g' > /boot/efi/EFI/centos/grub.cfg
fi

# board specific hacks
case "${board_name}" in
  Stumpy)
    cp /boot/efi/EFI/centos/grubx64.efi /boot/efi/EFI/BOOT/grubx64.efi
  ;;
esac
