#!/bin/bash

sudo virt-install --name nestedhv --memory 2048,maxmemory=2048 --vcpus 2 --cdrom /tmp/image.iso --os-variant ubuntu16.04 --disk size=72,bus=sata --network network=alternative,model=e1000 --graphics none
