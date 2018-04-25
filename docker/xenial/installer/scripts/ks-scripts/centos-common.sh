#!/usr/bin/env bash

# rewire the repo files :)
{
  for r in os updates extras ; do
    printf '[%s]\nbaseurl=%s/$releasever/%s/$basearch/\ngpgcheck=1\n' "${r}" "http://wcs.bbxn.us/centos" "${r}"
  done
} > "${TARGETPATH}/etc/yum.repos.d/CentOS-Base.repo"

printf '[%s]\nbaseurl=%s/$releasever/$basearch/\ngpgcheck=1\n' "epel" "http://wcs.bbxn.us/epel" > "${TARGETPATH}/etc/yum.repos.d/epel.repo"

# import rpm keys
if [ -z "${TARGETPATH}" ]
  ch_rpm() { chroot "${TARGETPATH}" rpm "${@}"; }
else
  ch_rpm() { rpm "${@}" ; }
fi

for f in "${TARGETPATH}/etc/pki/rpm-gpg"/* ; do
  k=${f##*/}
  ch_rpm --import "/etc/pki/rpm-gpg/${k}"
done

# configure vmm network if vm
mkdir -p "${TARGETPATH}/etc/systemd/network
cat <<_EOF_ > "${TARGETPATH}/etc/systemd/network/eth1.network"
[Match]
Name=eth1
Virtualization=vm
[Network]
DHCP=yes
LinkLocalAddressing=no
LMNR=no
MulticastDNS=no
_EOF_

# enable systemd-networkd
ln -sf /lib/systemd/system/systemd-networkd.service "${TARGETPATH}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
ln -sf /lib/systemd/system/systemd-networkd.socket "${TARGETPATH}/etc/systemd/system/sockets.target.wants/systemd-networkd.service"
ln -s /lib/systemd/system/systemd-networkd-wait-online.service "${TARGETPATH}/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

# shoot dhcpcd...and NetworkManager...
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/dhcpcd.service"
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/NetworkManager.service"
ln -sf /dev/null "${TARGETPATH}/etc/systemd/system/NetworkManager-wait-online.service"
rm -f "${TARGETPATH}/etc/systemd/system/dbus-org.freedesktop.NetworkManager.service"
rm -f "${TARGETPATH}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
rm -f "${TARGETPATH}/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service"

# forget everything you think you know about networks, actually
rm -f "${TARGETPATH}/etc/udev/rules.d/70-persistent-net.rules"
