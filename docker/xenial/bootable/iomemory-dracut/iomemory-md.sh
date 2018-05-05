#!/bin/sh

kick_fio_array(){
  local line word name uuid re
  test -e "${1}" || return 0 # if we don't have a config, silently get lost
  re=1
  info "Attempting FIO/MD array startup"
  while read line ; do
    [ -z "${line%%#*}" ] && continue # skip comment lines
    name='' ; uuid=''
    for word in ${line} ; do
      case "${word}" in
        name=*) name=${word#name=} ; name=${name##*:} ;;
        UUID=*) uuid=${word#UUID=} ;;
      esac
    done
    # we have an array, cool.
    [ -e "/dev/md/${name}" ] && return 0
    # try assembly
    mdadm --assemble "/dev/md/${name}" -u "${uuid#UUID=}"
  done < "${1}" | vinfo
  return "${PIPESTATUS[0]}"
}

modprobe iomemory-vsl
kick_fio_array /etc/mdadm/fio.conf
