#!/bin/bash

set -e

virsh_uri=$(virsh uri)

case "${virsh_uri}" in
  xen*)
    os_variant="rhel7"
    ;;
  qemu*)
    os_variant="rhel7.4"
    ;;
esac

virt-install --cdrom /var/lib/libvirt/images/netmgmt-inst.iso --name netmgmt.${1} --memory 768 --os-variant ${os_variant} --disk size=12 --graphics none --network bridge=netmgmt --network bridge=vmm --noautoconsole --noreboot --wait -1 -v

virsh setmem netmgmt.${1} 393216 --config
virsh setmaxmem netmgmt.${1} 786432 --config
virsh autostart netmgmt.${1}

virsh start netmgmt.${1}
