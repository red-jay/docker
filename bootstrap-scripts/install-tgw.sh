#!/bin/bash

set -e

case "${1}" in
  sv1)
    bootmac="52:54:00:CC:EF:04"
    vi_opts="--network bridge=pln,model=virtio --network bridge=wext,model=virtio"
    ;;
  sv2)
    bootmac="52:54:00:3E:EE:84"
    vi_opts="--network bridge=br-enp0s20u3,model=virtio"
    ;;
  *)
    echo "supply a site to bootstrap tgw in (sv1|sv2)"
    exit 1
    ;;
esac

virt-install --pxe --name tgw.${1} --memory 384 --os-variant openbsd4 --disk size=12,bus=virtio --graphics none --network bridge=transit,mac=${bootmac},model=virtio --network bridge=vmm,model=virtio ${vi_opts} --noautoconsole --wait -1
virsh autostart tgw.${1}
