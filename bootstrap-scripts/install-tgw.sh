#!/bin/bash

set -e

case "${1}" in
  sv1)
    bootmac="52:54:00:CC:EF:04"
    vi_opts="--network bridge=pln,model=virtio --network bridge=wext,model=virtio"
    ;;
  sv2)
    bootmac="52:54:00:3E:EE:84"
    vi_opts="--network bridge=br-enp0s20u3,model=virtio,mac=52:54:00:22:CA:BE"
    ;;
  *)
    echo "supply a site to bootstrap tgw in (sv1|sv2)"
    exit 1
    ;;
esac

if [[ -f "/var/lib/libvirt/images/private/tgw.${1}.iso" ]] ; then
  vi_opts="${vi_opts} --disk path=/var/lib/libvirt/images/private/tgw.${1}.iso,device=cdrom"
fi

virt-install --pxe --name tgw.${1} --memory 384 --os-variant openbsd4 --disk size=12,bus=virtio --graphics none --network bridge=transit,mac=${bootmac},model=virtio --network bridge=vmm,model=virtio ${vi_opts} --noreboot --noautoconsole --wait -1


if [[ -f "/var/lib/libvirt/images/private/tgw.${1}.iso" ]] ; then
  virsh detach-disk --config --persistent tgw.${1} /var/lib/libvirt/images/private/tgw.${1}.iso
fi

virsh start tgw.${1}
virsh autostart tgw.${1}
