#!/usr/bin/env bash

while read i ; do
  [ ! -z "${i}" ] && systemctl start "serial-getty@ttyS${i}"
done <<< "$(awk -F: '$3 == "16550A port" { print $1 }' < /proc/tty/driver/serial)"
