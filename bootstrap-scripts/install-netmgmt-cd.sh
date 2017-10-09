#!/bin/bash

set -e

virt-install --cdrom /var/lib/libvirt/images/netmgmt-inst.iso --name netmgmt.${1} --memory 768 --os-variant rhel7.4 --disk size=12 --graphics none --network bridge=netmgmt --network bridge=vmm --noautoconsole --noreboot --wait -1

virsh setmem netmgmt.${1} 393216 --config
virsh setmaxmem netmgmt.${1} 786432 --config
virsh autostart netmgmt.${1}

virsh start netmgmt.${1}
