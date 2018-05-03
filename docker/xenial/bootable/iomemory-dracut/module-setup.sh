#!/bin/bash

# called by dracut
check() {
    local fiomds
    # No mdadm?  No mdraid support.
    require_binaries mdadm || return 1
    fiomds=(/sys/block/md*/slaves/fio*)
    if [ -z "${fiomds[0]}" ] ; then return 1 ; fi
}

# called by dracut
depends() {
    return 0
}

# called by dracut
installkernel() {
    instmods iomemory-vsl
}

# called by dracut
install() {
    local fiomds arrays basedev mddev
    inst $(command -v mdadm) /sbin/mdadm
    mkdir -p "${initdir}/etc/mdadm"
    fiomds=(/sys/block/md*/slaves/fio*)
    arrays=""

    for slave in "${fiomds[@]}" ; do
      basedev="${slave##*/}"
      mddev="${slave#/sys/block/}"
      mddev="${mddev%/slaves/${basedev}}"
      mdadm --detail --scan "/dev/${mddev}" >> "${initdir}/etc/mdadm/fio.conf"
    done
    inst_hook initqueue/settled 20 "$moddir/iomemory-md.sh"
}
