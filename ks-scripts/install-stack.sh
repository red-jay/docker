#!/usr/bin/env bash

set -eux
set -o pipefail
shopt -s nullglob

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
chroot /usr/bin/firewall-offline-cmd --zone vmm --add-service http
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

# placeholder for if we have an address to remap
remap_addr=""

# check to see if we have a ethernet interface to plumb vlans against
for hwaddr_file in /sys/devices/pci*/*/net/*/address /sys/devices/pci*/*/*/net/*/address ; do
 if [ ! -z "${remap_addr}" ] ; then break ; fi
 hwaddr=""
 read -r hwaddr < "${hwaddr_file}"
 hwaddr="${hwaddr//:/}"
 remap_addr=$(bash "${SELFDIR}/intmac-remap.sh" "${hwaddr}")
done

# load vlan data, then create bridges, vlans
# shellcheck source=tf-output/common/hv-bridge-map.sh
source "${SELFDIR}/hv-bridge-map.sh"
# shellcheck source=tf-output/common/intmac-bridge.sh
source "${SELFDIR}/intmac-bridge.sh"

# create bridges
for vid in "${!vlan[@]}" ; do
  printf '[NetDev]\nName=%s\nKind=bridge\n' "${vlan[$vid]}" > "${TARGETPATH}/etc/systemd/network/${vlan[$vid]}.netdev"
  printf '[Match]\nName=%s\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${vlan[$vid]}" > "${TARGETPATH}/etc/systemd/network/${vlan[$vid]}.network"
done

# turn stp on for bridges OOTB
{
    printf '%s\n' 'SUBSYSTEM!="net", GOTO="autostp_end"'
    printf '%s\n' 'ACTION!="add", GOTO="autostp_end"'
    printf '%s\n' 'ENV{DEVTYPE}!="bridge", GOTO="autostp_end"'
    printf '%s\n' 'ENV{NO_STP}=="1", GOTO="autostp_end"'
    printf '%s\n' 'RUN+="/bin/sh -c '\''printf 1 > /sys/class/net/%k/bridge/stp_state'\''"'
    printf '%s\n' 'RUN+="/bin/sh -c '\''printf 200 > /sys/class/net/%k/bridge/forward_delay'\''"'
    printf '%s\n' 'LABEL="autostp_end"'
} > "${TARGETPATH}/etc/udev/rules.d/80-br-autostp.rules"

# turn stp off for external
{
    printf '%s\n' 'SUBSYSTEM!="net", GOTO="nostp_end"'
    printf '%s\n' 'ACTION!="add", GOTO="nostp_end"'
    printf '%s\n' 'ENV{DEVTYPE}!="bridge", GOTO="nostp_end"'
    printf '%s\n' 'ENV{INTERFACE}!="external", GOTO="nostp_end"'
    printf '%s\n' 'ENV{NO_STP}="1"'
    printf '%s\n' 'LABEL="nostp_end"'
} > "${TARGETPATH}/etc/udev/rules.d/65-br-external-nostp.rules"

if [ ! -z "${remap_addr}" ] ; then
  # create udev rule to remap an interface
  lladdr="${remap_addr:0:2}:${remap_addr:2:2}:${remap_addr:4:2}:${remap_addr:6:2}:${remap_addr:8:2}:${remap_addr:10:2}"
  oladdr="${hwaddr:0:2}:${hwaddr:2:2}:${hwaddr:4:2}:${hwaddr:6:2}:${hwaddr:8:2}:${hwaddr:10:2}"
  {
    printf 'SUBSYSTEM!="net", GOTO="autobr_end"\n'
    printf 'ACTION!="add", GOTO="autobr_end"\n'
    printf 'ENV{INTERFACE}=="lo", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="bridge", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="vlan", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="wlan", GOTO="autobr_end"\n'
    printf 'ENV{ID_NET_DRIVER}=="tun", GOTO="autobr_end"\n'
    printf 'ENV{ID_NET_NAME_MAC}!="enx%s", GOTO="autobr_end"\n' "${hwaddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k down"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k address %s"\n' "${lladdr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k up"\n'
    printf 'ENV{NM_UNMANAGED}="1"\n'
    printf 'LABEL="autobr_end"\n'
  } > "${TARGETPATH}/etc/udev/rules.d/81-remap-${hwaddr}.rules"

  # and a systemd-networkd config to drop in carrier mode...
  printf '[Match]\nMACAddress=%s\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${lladdr}" > "/mnt/sysimage/etc/systemd/network/${remap_addr}.network"

  # then glue the VLANs to the card en-masse.
  for vid in "${!vlan[@]}" ; do
     printf '[NetDev]\nName=vl-%s\nKind=vlan\n[VLAN]\nId=%s\n' "${vlan[$vid]}" "${vid}" > "/mnt/sysimage/etc/systemd/network/vl-${vlan[$vid]}.netdev"
     printf '[Match]\nName=vl-%s\n[Network]\nBridge=%s\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${vlan[$vid]}" "${vlan[$vid]}" > "/mnt/sysimage/etc/systemd/network/vl-${vlan[$vid]}.network"
     printf 'VLAN=vl-%s\n' "${vlan[$vid]}" >> "${TARGETPATH}/etc/systemd/network/${remap_addr}.network"
  done

  # configure just the hypervisor bridge with the old mac, dhcp on it.
  printf 'MACAddress=%s\n' "${oladdr}" >> "${TARGETPATH}/etc/systemd/network/hv.netdev"

  printf 'DHCP=ipv4\n[Link]\nRequiredForOnline=no\n' >> "${TARGETPATH}/etc/systemd/network/hv.network"
fi

for hwaddr in $pln ; do
  # so we actually make a new mac for remapping, then two bridge files - one for the freshly remapped mac and one for just the new.
  raddr=$(printf '5a'; dd bs=1 count=5 if=/dev/random 2>/dev/null | hexdump -v -e '/1 "%02x"')
  oraddr="${raddr:0:2}:${raddr:2:2}:${raddr:4:2}:${raddr:6:2}:${raddr:8:2}:${raddr:10:2}"
  {
    printf 'SUBSYSTEM!="net", GOTO="rebridge_end"\n'
    printf 'ACTION!="add", GOTO="rebridge_end"\n'
    printf 'ENV{INTERFACE}=="lo", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="bridge", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="vlan", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="wlan", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_DRIVER}=="tun", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_NAME_MAC}!="enx%s", GOTO="rebridge_end"\n' "${hwaddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k down"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k address %s"\n' "${oraddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k up"\n'
    printf 'ENV{NM_UNMANAGED}="1"\n'
    printf 'LABEL="rebridge_end"\n'
  } > "${TARGETPATH}/etc/udev/rules.d/82-map-pln-${hwaddr}.rules"

  {
    printf '[Match]\nMACAddress=%s\n[Network]\nBridge=%s\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${oraddr}" "pln"
  } > "${TARGETPATH}/etc/systemd/network/${raddr}.network"
done

for hwaddr in $external ; do
  # so we actually make a new mac for remapping, then two bridge files - one for the freshly remapped mac and one for just the new.
  raddr=$(printf '5a'; dd bs=1 count=5 if=/dev/random 2>/dev/null | hexdump -v -e '/1 "%02x"')
  oraddr="${raddr:0:2}:${raddr:2:2}:${raddr:4:2}:${raddr:6:2}:${raddr:8:2}:${raddr:10:2}"
  {
    printf 'SUBSYSTEM!="net", GOTO="rebridge_end"\n'
    printf 'ACTION!="add", GOTO="rebridge_end"\n'
    printf 'ENV{INTERFACE}=="lo", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="bridge", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="vlan", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="wlan", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_DRIVER}=="tun", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_NAME_MAC}!="enx%s", GOTO="rebridge_end"\n' "${hwaddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k down"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k address %s"\n' "${oraddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k up"\n'
    printf 'ENV{NM_UNMANAGED}="1"\n'
    printf 'LABEL="rebridge_end"\n'
  } > "${TARGETPATH}/etc/udev/rules.d/82-map-external-${hwaddr}.rules"

  {
    printf '[Match]\nMACAddress=%s\n[Network]\nBridge=%s\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${oraddr}" "external"
  } > "${TARGETPATH}/etc/systemd/network/${raddr}.network"
done

for hwaddr in $netm ; do
  # so we actually make a new mac for remapping, then two bridge files - one for the freshly remapped mac and one for just the new.
  raddr=$(printf '5a'; dd bs=1 count=5 if=/dev/random 2>/dev/null | hexdump -v -e '/1 "%02x"')
  oraddr="${raddr:0:2}:${raddr:2:2}:${raddr:4:2}:${raddr:6:2}:${raddr:8:2}:${raddr:10:2}"
  {
    printf 'SUBSYSTEM!="net", GOTO="rebridge_end"\n'
    printf 'ACTION!="add", GOTO="rebridge_end"\n'
    printf 'ENV{INTERFACE}=="lo", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="bridge", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="vlan", GOTO="rebridge_end"\n'
    printf 'ENV{DEVTYPE}=="wlan", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_DRIVER}=="tun", GOTO="rebridge_end"\n'
    printf 'ENV{ID_NET_NAME_MAC}!="enx%s", GOTO="rebridge_end"\n' "${hwaddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k down"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k address %s"\n' "${oraddr}"
    printf 'RUN+="/usr/sbin/ip link set dev %%k up"\n'
    printf 'ENV{NM_UNMANAGED}="1"\n'
    printf 'LABEL="rebridge_end"\n'
  } > "${TARGETPATH}/etc/udev/rules.d/82-map-netm-${hwaddr}.rules"

  {
    printf '[Match]\nMACAddress=%s\n[Network]\nBridge=%s\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${oraddr}" "netm"
  } > "${TARGETPATH}/etc/systemd/network/${raddr}.network"
done

# disable libvirt network autostarts
lv_autostart=( "${TARGETPATH}"/etc/libvirt/qemu/networks/autostart/* )
if [ ! -z "${lv_autostart[*]}" ] ; then
  rm -f "${TARGETPATH}/etc/libvirt/qemu/networks/autostart/*"
fi

# configure spare libvirt network
altmac=$({ printf '5A'; dd bs=1 count=5 if=/dev/random 2> /dev/null | hexdump -v -e '/1 ":%02X"'; })
altuuid=$(uuidgen)
cat << _EOF_ > "${TARGETPATH}/etc/libvirt/qemu/networks/alternative.xml"
<network>
 <name>alternative</name>
 <uuid>${altuuid}</uuid>
 <forward mode="nat"/>
 <bridge name="virbr1" stp="on" delay="0"/>
 <mac address="${altmac}"/>
 <ip address="192.168.212.1" netmask="255.255.255.0">
  <dhcp>
   <range start="192.168.212.2" end="192.168.212.254"/>
  </dhcp>
 </ip>
</network>
_EOF_
