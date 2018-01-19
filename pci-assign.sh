#!/bin/bash

set -eux

set -o pipefail

pciback_mod="xen-pciback"
pciback_arg=''
force_arg=''
driver_list=''

for d in /sys/bus/pci/devices/* ; do
  # get pci information
  path=$(readlink "${d}")
  path=${path#../../../devices/}
  pathct=${path//[^\/]}
  slot=$(basename "${d}")
  dclass=''
  read class < "${d}/class"
  read vendor < "${d}/vendor"
  vendor=${vendor:2}
  read device < "${d}/device"
  device=${device:2}
  read sub_ven < "${d}/subsystem_vendor"
  sub_ven=${sub_ven:2}
  read sub_dev < "${d}/subsystem_device"
  sub_dev=${sub_dev:2}

  # if we _have_ a driver, get the driver.
  driver='NONE'
  if [ -e "$d/driver" ] ; then
    driver=$(readlink "${d}/driver")
    driver=$(basename "${driver}")
  fi

  # a display helper, not really _needed_
  case $class in
    0x00*)   dclass='uncla' ;;
    0x01*)   dclass='store' ;;
    0x02*)   dclass='netct' ;;
    0x03*)   dclass='disct' ;;
    0x04*)   dclass='mulct' ;;
    0x05*)   dclass='memct' ;;
    0x06*)   dclass='bridg' ;;
    0x07*)   dclass='comct' ;;
    0x08*)   dclass='perif' ;;
    0x09*)   dclass='input' ;;
    0x0a*)   dclass='docks' ;;
    0x0b*)   dclass='procs' ;;
    0x0c00*) dclass='fwire' ;;
    0x0c05*) dclass='smbus' ;;
    0x0c03*) dclass='usbct' ;;
    0x0d*)   dclass='wictl' ;;
    0x0e*)   dclass='i20ct' ;;
    0x0f*)   dclass='satct' ;;
    0x10*)   dclass='crypt' ;;
    0x11*)   dclass='spctl' ;;
    0x12*)   dclass='accel' ;;
    0x13*)   dclass='instr' ;;
    0x40*)   dclass='coprc' ;;
    0xff*)   dclass='unass' ;;
  esac

  # output - hide bridges, pci-peripherals
  case $class in
   #bridg|perif|store|smbus
    0x06*|0x08*|0x01*|0x0c05*) : ;; # nop
    0x02*)
      # if we have a netdriver, get the mac if this _should_ be passthrough'd
      if [ -f ${d}/net/*/address ] ; then
        read net_mac < ${d}/net/*/address
        case "${net_mac}" in
          "00:25:64:a7:7b:63"|"b8:ac:6f:3f:0c:b3")
            pciback_arg="(${slot})${pciback_arg}"
            force_arg="${slot},${force_arg}"
            # uniq driver_list upon insertion
            case "${driver_list}" in
              *${driver}*) : ;;
              *) driver_list="${driver} ${driver_list}" ;;
            esac
            ;;
          *) : ;; # nop
        esac
      fi
      ;;
    *)
      # if we are behind a bridge, get the _bridge_ information here.
      if [ "${#pathct}" -gt 1 ] ; then
        br_dev=${path%/*}
        read br_ven < "/sys/devices/${br_dev}/vendor"
        br_ven=${br_ven:2}
        read br_dev < "/sys/devices/${br_dev}/device"
        br_dev=${br_dev:2}
        # skip around pcie->pci bridges, painfully via known vendor:id pairs
        if [ "${br_ven}" == "12d8" ] && [ "${br_dev}" == "e130" ] ; then continue ; fi
        if [ "${br_ven}" == "8086" ] && [ "${br_dev}" == "244e" ] ; then continue ; fi
      fi
      # xen's pciback wants (), the boot script wants , - just make two different arglists
      pciback_arg="(${slot})${pciback_arg}"
      force_arg="${slot},${force_arg}"
      # uniq driver_list upon insertion
      case "${driver_list}" in
        *${driver}*) : ;;
        *) driver_list="${driver} ${driver_list}" ;;
      esac
      ;;
  esac
done

# remove trailing comma
force_arg=${force_arg:0:-1}

# module configuration - arguments
{
  printf 'options %s hide=%s\n' "${pciback_mod}" "${pciback_arg}" 
  for driver in ${driver_list} ; do
    printf 'softdep %s pre: %s\n' "${driver}" "${pciback_mod}"
  done
} > "/mnt/sysimage/etc/modprobe.d/${pciback_mod}.conf"

# add to initrd
printf '%s\n' "${pciback_mod}" >> /mnt/sysimage/etc/initramfs-tools/modules

cp boot_pci_assign.sh /mnt/sysimage/etc/initramfs-tools/scripts/init-top/pciback_force

# regnerate initrd
target_kver=(/mnt/sysimage/boot/vmlinuz-*-generic)
target_kver=${target_kver#/mnt/sysimage/boot/vmlinuz-}
chroot /mnt/sysimage env LC_ALL=C mkinitramfs -o "/boot/initrd.img-${target_kver}" "${target_kver}"

# generate grub argument
case ${pciback_mod} in
  xen-pciback) bootname='pciback' ;;
  *) bootname=${pciback_mod} ;;
esac

pcif_arg="pciback_force=${bootname}:${force_arg}"

# update grub - try just the Xen specific version first, then tinker with standard.
grub_def_lx_xe_arg=$(augtool -r /mnt/sysimage print /files/etc/default/grub/GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT)
if [ ! -z "grub_def_lx_xe_arg" ] ; then
  grub_def_lx_xe_arg="${grub_def_lx_xe_arg#* = }"
  grub_def_lx_xe_arg="${grub_def_lx_xe_arg:0:-3} ${pcif_arg}${grub_def_lx_xe_arg: -3}"
  augtool -r /mnt/sysimage set /files/etc/default/grub/GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT "${grub_def_lx_xe_arg}"
else
  grub_def_lx_arg=$(augtool -r /mnt/sysimage print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
  grub_def_lx_arg="${grub_def_lx_arg#* = }"
  grub_def_lx_arg="${grub_def_lx_arg:0:-3} ${pcif_arg}${grub_def_lx_arg: -3}"
  augtool -r /mnt/sysimage set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "${grub_def_lx_arg}"
fi

# and update the boot config
chroot /mnt/sysimage grub-mkconfig -o /boot/grub/grub.cfg
