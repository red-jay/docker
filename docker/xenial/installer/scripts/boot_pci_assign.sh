#!/bin/sh

PREREQ="udev"
prereqs() {
  echo "$PREREQ"
}
case "${1}" in prereqs) prereqs ; exit 0 ;; esac

# shellcheck disable=SC2013
for x in $(cat /proc/cmdline) ; do
  case "${x}" in
    pciback_force=*)
      pcif_args=$( echo "${x}" | sed 's/^pciback_force=//' )
      pcif_mod=$( echo "${pcif_args}" | sed 's/:.*//' )
      pcif_dev=$( echo "${pcif_args}" | sed "s/${pcif_mod}://" )
      pcif_dev=$( echo "${pcif_dev}" | sed 's/,/ /g' )
      for pcidev in ${pcif_dev} ; do
        if [ -e "/sys/bus/pci/devices/${pcidev}/driver" ] ; then
          curdrv=$(basename "$(readlink "/sys/bus/pci/devices/${pcidev}/driver")")
          if [ "${curdrv}" != "${pcif_mod}" ] ; then
            echo "${pcidev}" > "/sys/bus/pci/devices/${pcidev}/driver/unbind"
            echo "${pcidev}" > "/sys/bus/pci/drivers/${pcif_mod}/new_slot"
            echo "${pcidev}" > "/sys/bus/pci/drivers/${pcif_mod}/bind"
          fi
        fi
      done
    ;;
  esac
done
