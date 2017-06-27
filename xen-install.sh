#!/bin/bash

set -eux

set -o pipefail

chroot_ag() {
  chroot /mnt/target env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get "${@}"
}

# install
chroot_ag install -y xen-system-amd64

# base xen boot arguments
xen_cmdline="dom0_max_vcpus=2 dom0_mem=8G"

# figure out serial console by asking grub what _it_ does
grub_term=$(augtool -r /mnt/target print /files/etc/default/grub/GRUB_TERMINAL)
grub_term="${grub_term#* = }"

case "${grub_term}" in
  *serial*)
    grub_sercmd=$(augtool -r /mnt/target print /files/etc/default/grub/GRUB_SERIAL_COMMAND)
    grub_sercmd="${grub_sercmd#* = }"
    for param in ${grub_sercmd} ; do
      case "${param}" in
        --unit=*)
          CONFIG_SERIAL_INSTALL=${param#--unit=}
          # xen uses com1, com2...as opposed to ttyS0 for linux/grub
          xen_com=$((CONFIG_SERIAL_INSTALL + 1))
          xen_cmdline="${xen_cmdline} com${xen_com}=115200,8n1 console=com${xen_com}"
          ;;
      esac
    done
    ;;
esac

# platform specific hacks
read plat < /sys/class/dmi/id/product_name

case "${plat}" in
  "Precision WorkStation T5500")
    xen_cmdline="${xen_cmdline} iommu=no-intremap"
    ;;
esac

# adapt the grub linux boot options for the grub linux/xen boot options
lx_def_cmdline=$(augtool -r /mnt/target print /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)
lx_def_cmdline="${lx_def_cmdline#* = }"
lx_def_cmdline="${lx_def_cmdline:3:-3}"
lx_xe_def_cmdline='console=hvc0 earlyprintk=xenboot'
for arg in ${lx_def_cmdline} ; do
  case "${arg}" in
    console=*)
      :
      ;;
    *)
      lx_xe_def_cmdline="${lx_xe_def_cmdline} ${arg}"
      ;;
  esac
done

# quotes and backticks for augtool hell
xen_cmdline=\"\\\""${xen_cmdline}"\\\"\"
lx_xe_def_cmdline=\"\\\""${lx_xe_def_cmdline}"\\\"\"

augtool -r /mnt/target -s set /files/etc/default/grub/XEN_OVERRIDE_GRUB_DEFAULT 1
augtool -r /mnt/target -s set /files/etc/default/grub/GRUB_CMDLINE_XEN "${xen_cmdline}"
augtool -r /mnt/target -s set /files/etc/default/grub/GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT "${lx_xe_def_cmdline}"

chroot /mnt/target sh -c "cd /etc/grub.d && ln -s 20_linux_xen 01_linux_xen"

chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg
