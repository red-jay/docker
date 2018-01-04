#!/usr/bin/env bash

set -eux

set -o pipefail

IN_KS="0"

TARGETPATH=/mnt/sysimage

SELFDIR="${BASH_SOURCE%/*}"

if [ -z "${IN_KS}" ] ; then
  ppid=$(cut -d' ' -f4 < /proc/$$/stat)
  gpid=$(cut -d' ' -f4 < "/proc/${ppid}/stat")
  # parsing /proc/pid/cmdline sucks.
  while read -r -d $'\0' cmdl ; do
    case $cmdl in
      /sbin/anaconda) IN_KS=1 ;;
    esac
  done < "/proc/${gpid}/cmdline"
fi

chroot () {
  command chroot "${TARGETPATH}" env LC_ALL=C TERM=dumb DEBIAN_FRONTEND=noninteractive "${@}"
}

chroot_ag() {
  if [ "${IN_KS}" != 0 ] ; then
    chroot apt-get "${@}"
  else
    true
  fi
}

# install libvirt, firewalld
chroot_ag install -y libvirt-bin firewalld dnsmasq dhcpcd5 virtinst vncsnapshot

# enable systemd-networkd
ln -sf /lib/systemd/system/systemd-networkd.service "${TARGETPATH}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
ln -sf /lib/systemd/system/systemd-networkd.socket "${TARGETPATH}/etc/systemd/system/sockets.target.wants/systemd-networkd.service"
#ln -s /lib/systemd/system/systemd-networkd-wait-online.service /mnt/target/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service

# shoot dhcpcd...and NetworkManager...
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/dhcpcd.service"
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/NetworkManager.service"
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/NetworkManager-wait-online.service"
rm -f "${TARGETPATH}/etc/systemd/system/dbus-org.freedesktop.NetworkManager.service"
rm -f "${TARGETPATH}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
rm -f "${TARGETPATH}/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service"

# directory for systemd-networkd configs
mkdir -p "${TARGETPATH}/etc/systemd/network"

# disable ipv6 for most things
printf 'net.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 0\n' > "${TARGETPATH}/etc/sysctl.d/40-ipv6.conf"

# create vmm
printf '[NetDev]\nName=vmm\nKind=bridge\n' > "${TARGETPATH}/etc/systemd/network/vmm.netdev"
printf '[Match]\nName=vmm\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\nAddress=192.168.128.129/25\n' > "${TARGETPATH}/etc/systemd/network/vmm.network"

# update firewalld for vmm
mkdir "${TARGETPATH}/run/firewalld"
chroot /usr/bin/firewall-offline-cmd --new-zone vmm
chroot /usr/bin/firewall-offline-cmd --zone vmm --add-interface vmm
chroot /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 0 --logical-in vmm -j DROP
chroot /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 1 --logical-out vmm -j DROP
chroot /usr/bin/firewall-offline-cmd --zone vmm --add-service dhcp
chroot /usr/bin/firewall-offline-cmd --zone vmm --add-service ntp
chroot /usr/bin/firewall-offline-cmd --zone vmm --add-port 3493/tcp

# libvirtd/firewalld act poorly here, shoot filtering on bridges
{
  printf 'install xt_physdev /bin/false\n'
  printf 'install br_netfilter /bin/false\n'
} > "${TARGETPATH}/etc/modprobe.d/blacklist-xt_physdev.conf"

# configure dnsmasq
{
  printf 'port=0\ninterface=vmm\nbind-interfaces\nno-hosts\n'
  printf 'dhcp-range=192.168.128.130,192.168.128.254,30m\n'
  printf 'dhcp-option=3\ndhcp-option=6\ndhcp-option=12\ndhcp-option=42,0.0.0.0\n'
  printf 'dhcp-option=vendor:BBXN,1,0.0.0.0\n'
  printf 'dhcp-authoritative\n'
} > "${TARGETPATH}/etc/dnsmasq.conf"

ln -sf /lib/systemd/system/dnsmasq.service "${TARGETPATH}/etc/systemd/system/multi-user.target.wants/dnsmasq.service"
mkdir -p "${TARGETPATH}/etc/systemd/system/dnsmasq.service.d"
printf '[Service]\nRestartSec=1s\nRestart=on-failure\n' > "${TARGETPATH}/etc/systemd/system/dnsmasq.service.d/local.conf"

# load vlan data, then create bridges, vlans
# shellcheck source=tf-output/common/hv-bridge-map.sh
source "${SELFDIR}/hv-bridge-map.sh"

# create bridges,vlans
for vid in "${!vlan[@]}" ; do
  printf '[NetDev]\nName=%s\nKind=bridge\n' "${vlan[$vid]}" > "${TARGETPATH}/etc/systemd/network/${vlan[$vid]}.netdev"
  printf '[Match]\nName=%s\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${vlan[$vid]}" > "${TARGETPATH}/etc/systemd/network/${vlan[$vid]}.network"
done
