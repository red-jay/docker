#!/bin/bash

if [ -z "${1}" ] ; then echo "provide path to install iso" 1>&2 ; fi

sudo cp "${1}" /tmp/cdrom.iso

if [ "${2}" == "xen" ] ; then
  os_variant="ubuntu16.04"
  diskflags=",bus=sata"
  nicflags=",model=e1000"
else
  os_variant="rhel7"
  diskflags=",bus=virtio"
  nicflags=",model=virtio"
fi

sudo virsh undefine hvtest
sudo rm /var/lib/libvirt/images/hvtest.qcow2

sudo virt-install --name hvtest --memory 3072 --vcpus 2 --cdrom /tmp/cdrom.iso --os-variant "${os_variant}" --disk size=72${diskflags} --network network=alternative${nicflags} --graphics none --cpu host-passthrough
