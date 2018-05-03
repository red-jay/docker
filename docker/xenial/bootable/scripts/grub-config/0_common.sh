#!/usr/bin/env bash

set -ex

# are you installing via a serial console _right now_? if so, config grub serialisms.
if [ -z "${CONFIG_SERIAL_INSTALL}" ] ; then
  CONFIG_SERIAL_INSTALL=$(tty)
fi

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

# now check if CONFIG_SERIAL_INSTALL is still set
if [ ! -z "${CONFIG_SERIAL_INSTALL}" ] ; then
  {
    printf 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=%s --word=8 --parity=no --stop=1"\n' "${CONFIG_SERIAL_INSTALL}"
    printf 'GRUB_TERMINAL="serial"\n'
  } >> /etc/default/grub
  cmdline=$(augtool print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
  cmdline="${cmdline#* = }"
  cmdline="${cmdline/splash/}"
  # since we know the _last_ three characters of this are quoting, splice like this
  cmdline="${cmdline:0:-3} console=ttyS${CONFIG_SERIAL_INSTALL},115200n8${cmdline: -3}"
  augtool -s set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "${cmdline}"
fi
