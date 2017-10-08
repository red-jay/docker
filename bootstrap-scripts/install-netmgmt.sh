#!/bin/bash

set -e

case "${1}" in
  sv1|sv2|pa)
    : ;;
  *)
    echo "supply a site to bootstrap netmgmt in (sv1|sv2|pa)"
    exit 1
    ;;
esac

virt-install --location http://192.168.128.129/bootstrap/centos7/ --name netmgmt.${1} --memory 1280 --os-variant rhel7.4 --disk size=12 --graphics none --network bridge=netmgmt --network bridge=vmm --extra-args="console=ttyS0,115200n8 ks=http://192.168.128.129/bootstrap/ks/netmgmt.ks site=${1} rd.neednet=1 ip=eth1:dhcp biosdevname=0 net.ifnames=0" --noautoconsole --noreboot --wait -1

virsh setmem netmgmt.${1} 393216 --config
virsh setmaxmem netmgmt.${1} 786432 --config
