#!/bin/sh

kick_fio_array(){
  local line word name uuid
  test -e "${1}" || return 1
  info "Attempting FIO/MD array startup"
  while read line ; do
    [ -z "${line%%#*}" ] && continue # skip comment lines
    for word in ${line} ; do
      name='' ; uuid=''
      case "${word}" in
        name=*) name=${word#name=} ; name=${name##*:} ;;
        UUID=*) uuid=${word#UUID=} ;;
      esac
    done
    [ -e "/dev/md/${name}" ] || mdadm --assemble "/dev/md/${name}" -u "${uuid#UUID=}"
  done < "${1}" | vinfo
}

modprobe iomemory-vsl
kick_fio_array /etc/mdadm/fio.conf
