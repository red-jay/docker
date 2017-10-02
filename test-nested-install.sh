virt-install -n hvtest --memory 3072 --vcpus 2 --cdrom /tmp/cdrom.iso --disk size=72 --network network=alternative --os-variant=rhel7 --graphics none -v --cpu host-passthrough
