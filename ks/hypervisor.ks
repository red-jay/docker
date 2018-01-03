#version=RHEL7
# System authorization information
auth --enableshadow --passalgo=sha512

# we're pretending to be a CDROM, even if we're...kinda not
cdrom

# Use text mode
text
# Dont' run the Setup Agent on first boot
firstboot --disable
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# partitioning is done via %pre madness
%include /tmp/part-include

# configure root password
rootpw --iscrypted $6$ddmoPYtWupIPA/Vn$9EcJ170zv2lnVP6mLK0W9zAWaf7OYmu3yHk9dY0/pl5dPluvkTp/wTLmT4C7BAIE4FAGxPQ0K0zPwftvdvl5/0

# networking is also in %pre (well, unless it's in %post)
%include /tmp/net-include

# reboot when done
%include /tmp/reboot-flag

# System timezone
timezone America/Los_Angeles --isUtc --nontp

# System services
services --enabled="lldpad,chronyd"

%packages
@core
@base

@virtualization-hypervisor
@virtualization-tools
virt-install

grub2
grub2-pc
grub2-pc-modules
grub2-efi-x64
grub2-efi-x64-modules
grub2-efi-ia32
grub2-efi-ia32-modules
shim-x64
shim-ia32
efibootmgr

%include /tmp/package-include

systemd-networkd

lldpad
epel-release
nut
apg
screen
uucp

dstat
htop
tmux
xorg-x11-xauth

policycoreutils-python

# needed for org_fedora_oscap addon
openscap
openscap-scanner
scap-security-guide

nginx

%end

%addon org_fedora_oscap
    content-type = scap-security-guide
    profile = common
%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%pre
# be a chatterbox here
exec 1> /tmp/pre-log
exec 2>&1
set -x

env

# find ppid so we can get parent cmd
ppid=$(cut -d' ' -f4 < /proc/$$/stat)
read -r pcmdl < "/proc/${ppid}/cmdline"

case "${pcmdl}" in
  */sbin/anaconda)
    echo "running in anaconda ks env"
  ;;
esac

echo ${ppid} ${pcmdl}

# on with nullglub
shopt -s nullglob

# functions

# parts that can be _reset_ by system config but have a default
reboot_flag="reboot"
inst_fqdn="localhost.localdomain"

# first get if we have a syscfg on cmdline
read cmdline < /proc/cmdline
for ent in $cmdline ; do
  case $ent in
    syscfg=*)
      syscfg=${ent#syscfg=}
      ;;
  esac
done

# well... let's try to find one
if [ -z "${syscfg}" ] ; then
  # first, chassis serial number?
  if [ -f /sys/class/dmi/id/chassis_serial ] ; then
    read cha_ser < /sys/class/dmi/id/chassis_serial
    case $cha_ser in
      C07M30ANDY3H)
        syscfg=nickel
        inst_fqdn="nickel.produxi.net"
        ;;
      C07MD1PCDY3H)
        syscfg=palladium
        inst_fqdn="palladium.produxi.net"
        ;;
      C07JC8QCDWYL)
        syscfg=tungsten
        inst_fqdn="tungsten.produxi.net"
        ;;
      "To Be Filled By O.E.M."|"#GIADAI##661##"|"")
      # yuck, go grab ethernet MACs by PCI topology
      for macfile in /sys/devices/pci*/*/net/*/address /sys/devices/pci*/*/*/net/*/address ; do
        read mac < "${macfile}"
        case $mac in
          "00:1b:21:8f:8e:80")
            syscfg=rhenium
            inst_fqdn="rhenium.bbxn.us"
            break
            ;;
          "00:e0:6f:25:6e:8d")
            syscfg=mercury
            inst_fqdn="mercury.bbxn.us"
            break
            ;;
          "00:e0:6f:11:ac:20")
            syscfg=radon
            inst_fqdn="radon.bbxn.us"
            break
            ;;
          "e8:03:9a:da:48:45")
            syscfg=strontium
            inst_fqdn="strontium.bbxn.us"
            break
            ;;
        esac
      done
      ;;
    esac
  fi
fi

# second pass - more generic things
if [ -z "${syscfg}" ] ; then
  if [ -f /sys/class/dmi/id/chassis_vendor ] ; then
    read cha_ven < /sys/class/dmi/id/chassis_vendor
    case $cha_ven in
      "QEMU")
        syscfg=qemu-generic
        ;;
    esac
  fi
fi

# always stop lvm
vgchange -an

# configure disks via magic script ;)
bash -x /run/install/repo/fs-layout.sh -W

# this holds any needed conditional package statements
touch /tmp/package-include

if [[ " radon mercury tungsten palladium nickel " =~ " ${syscfg} " ]] ; then
  reboot_flag="reboot"
fi

if [[ " strontium rhenium qemu-generic " =~ " ${syscfg} " ]] ; then
  reboot_flag="poweroff"
fi

# hang the hostname up
printf 'network --hostname="%s"\n' "${inst_fqdn}" >> /tmp/net-include

# we always create reboot-flag
printf '%s\n' "${reboot_flag}" > /tmp/reboot-flag

# we always create post-vars.
touch /tmp/post-vars

# write out the syscfg for %post
if [ ! -z "${syscfg}" ] ; then
  printf 'syscfg="%s"\n' "${syscfg}" >> /tmp/post-vars
fi

%end

%post --nochroot --log=/mnt/sysimage/root/post.log
# be a chatterbox here
set -x

# on with nullglub
shopt -s nullglob

# pick up env vars from %pre
. /tmp/post-vars

# pick up authorized_keys
if [ -f /run/install/repo/authorized_keys ] ; then
  mkdir -p /mnt/sysimage/root/.ssh
  cp /run/install/repo/authorized_keys /mnt/sysimage/root/.ssh
  chmod 0700 /mnt/sysimage/root/.ssh
  chmod 0600 /mnt/sysimage/root/.ssh/authorized_keys
  printf 'PermitRootLogin without-password\n' >> /mnt/sysimage/etc/ssh/sshd_config
fi

# install grub cross-bootably
if [ -d /sys/firmware/efi/efivars ] ; then
  # install i386 grub in efi
  chroot /mnt/sysimage grub2-install --target=i386-pc /dev/${disk}
  chroot /mnt/sysimage grub2-mkconfig | sed 's@linuxefi@linux16@g' | sed 's@initrdefi@initrd16@g' > /mnt/sysimage/boot/grub2/grub.cfg
else
  # install efi grub in i386
  chroot /mnt/sysimage grub2-mkconfig | sed 's@linux16@linuxefi@g' | sed 's@initrd16@initrdefi@g' > /mnt/sysimage/boot/efi/EFI/centos/grub.cfg
fi

# strontium is...slightly perplexed
if [[ " strontium " =~ " ${syscfg} " ]] ; then
  cp /mnt/sysimage/boot/efi/EFI/centos/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
fi

# rewire the repo files :)
{
  for r in os updates extras ; do
    printf '[%s]\nbaseurl=%s/$releasever/%s/$basearch/\ngpgcheck=1\n' "${r}" "http://wcs.bbxn.us/centos" "${r}"
  done
} > /mnt/sysimage/etc/yum.repos.d/CentOS-Base.repo

printf '[%s]\nbaseurl=%s/$releasever/$basearch/\ngpgcheck=1\n' "epel" "http://wcs.bbxn.us/epel" > /mnt/sysimage/etc/yum.repos.d/epel.repo

for f in /mnt/sysimage/etc/pki/rpm-gpg/* ; do
  k=${f##*/}
  chroot /mnt/sysimage rpm --import "/etc/pki/rpm-gpg/${k}"
done

# this particular vlan table is global since all HVs use it.
vlan[4]=netmgmt		# network device controllers (where possible)
vlan[5]=standard	# "regular" VMs and such
vlan[7]=guest		# guest wifi
vlan[8]=sv2-guest	# guest wifi (garage)
vlan[66]=transit	# transit vlan
vlan[70]=restricted	# restricted wifi vlan
vlan[71]=sv2-res	# restricted wifi (garage)
vlan[90]=wifi		# standard user wifi
vlan[91]=sv2-wifi	# user wifi in the garage
vlan[100]=virthost	# hypervisors
vlan[303]=dmz		# DMZ range
vlan[606]=chaos		# chaosnet
vlan[602]=sv2-iot	# iot (garage)
vlan[999]=iot		# internet of things devices
vlan[990]=pln		# powerline networking
vlan[992]=wext		# wifi backup networking

# configure the network using systemd-networkd here.
mkdir -p /mnt/sysimage/etc/systemd/network/

# shoot NetworkManager in the face
ln -s /dev/null /mnt/sysimage/etc/systemd/system/NetworkManager.service
ln -s /dev/null /mnt/sysimage/etc/systemd/system/NetworkManager-wait-online.service
rm -f /mnt/sysimage/etc/systemd/system/dbus-org.freedesktop.NetworkManager.service
rm -f /mnt/sysimage/etc/systemd/system/multi-user.target.wants/NetworkManager.service
rm -f /mnt/sysimage/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service
#ln -s /usr/lib/systemd/system/systemd-networkd-wait-online.service /mnt/sysimage/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service

# disable ipv6 for most things
printf 'net.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 0\n' > /mnt/sysimage/etc/sysctl.d/40-ipv6.conf

# create vmm
printf '[NetDev]\nName=vmm\nKind=bridge\n' > "/mnt/sysimage/etc/systemd/network/vmm.netdev"
printf '[Match]\nName=vmm\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\nAddress=192.168.128.129/25\n' > "/mnt/sysimage/etc/systemd/network/vmm.network"

# update firewalld for vmm
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --new-zone vmm
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --zone vmm --add-interface vmm
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 0 --logical-in vmm -j DROP
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 1 --logical-out vmm -j DROP
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --zone vmm --add-service dhcp
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --zone vmm --add-service ntp
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --zone vmm --add-service http
chroot /mnt/sysimage /usr/bin/firewall-offline-cmd --zone vmm --add-port 3493/tcp

# configure dnsmasq
{
  printf 'port=0\ninterface=vmm\nbind-interfaces\nno-hosts\n'
  printf 'dhcp-range=192.168.128.130,192.168.128.254,30m\n'
  printf 'dhcp-option=3\ndhcp-option=6\ndhcp-option=12\ndhcp-option=42,0.0.0.0\n'
  printf 'dhcp-option=vendor:BBXN,1,0.0.0.0\n'
  printf 'dhcp-authoritative\n'
} > /mnt/sysimage/etc/dnsmasq.conf
ln -s /usr/lib/systemd/system/dnsmasq.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/dnsmasq.service
mkdir -p /mnt/sysimage/etc/systemd/system/dnsmasq.service.d
printf '[Service]\nRestartSec=1s\nRestart=on-failure\n' > /mnt/sysimage/etc/systemd/system/dnsmasq.service.d/local.conf
ln -s /usr/lib/systemd/system/nginx.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/nginx.service
printf 'location /bootstrap/openbsd {\n autoindex on;\n}\n' > /mnt/sysimage/etc/nginx/default.d/openbsd.conf

if [[ " rhenium " =~ " ${syscfg} " ]] ; then
  topcard='enp6s0f1'
fi

if [[ " radon mercury " =~ " ${syscfg} " ]] ; then
  topcard='enp3s0'
fi

if [[ " strontium " =~ " ${syscfg} " ]] ; then
  topcard='enp4s0'
fi

if [[ " tungsten palladium nickel " =~ " ${syscfg} " ]] ; then
  topcard='enp1s0f0'
fi

case "${syscfg}" in
  rhenium)
    fallback_ipv4=172.16.143.150/25
    ;;
  radon)
    fallback_ipv4=172.16.143.151/25
    ;;
  mercury)
    fallback_ipv4=172.16.143.152/25
    ;;
  nickel)
    fallback_ipv4=172.16.143.153/25
    ;;
  strontium)
    fallback_ipv4=172.16.143.154/25
    ;;
  palladium)
    fallback_ipv4=172.16.143.155/25
    ;;
  tungsten)
    fallback_ipv4=172.16.143.156/25
    ;;
esac

if [ ! -z "${topcard}" ] ; then
  printf '[Match]\nName=%s\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${topcard}" > "/mnt/sysimage/etc/systemd/network/${topcard}.network"
fi

# create bridges,vlans
for vid in "${!vlan[@]}" ; do
  printf '[NetDev]\nName=%s\nKind=bridge\n' "${vlan[$vid]}" > "/mnt/sysimage/etc/systemd/network/${vlan[$vid]}.netdev"
  printf '[Match]\nName=%s\n[Network]\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${vlan[$vid]}" > "/mnt/sysimage/etc/systemd/network/${vlan[$vid]}.network"
  if [ ! -z "${topcard}" ] ; then
    printf '[NetDev]\nName=vl-%s\nKind=vlan\n[VLAN]\nId=%s\n' "${vlan[$vid]}" "${vid}" > "/mnt/sysimage/etc/systemd/network/vl-${vlan[$vid]}.netdev"
    printf '[Match]\nName=vl-%s\n[Network]\nBridge=%s\nLinkLocalAddressing=no\nLLMNR=false\nIPv6AcceptRA=no\n' "${vlan[$vid]}" "${vlan[$vid]}" > "/mnt/sysimage/etc/systemd/network/vl-${vlan[$vid]}.network"
    # associate vlans to topdev
    printf 'VLAN=vl-%s\n' "${vlan[$vid]}" >> "/mnt/sysimage/etc/systemd/network/${topcard}.network"
  fi
done

if [ ! -z "${topcard}" ] ; then
  # configure virthost to use dhclient, with a fallback managed via systemd...
  {
    printf '[Unit]\nDescription=dhclient on %%I\nWants=network.target\nBefore=network.target\nOnFailure=dhclient-fallback@%%i.service\n'
    printf '[Service]\nEnvironment=PATH_DHCLIENT_PID=/var/run/dhclient-%%i.pid\nEnvironment=PATH_DHCLIENT_DB=/var/lib/dhclient/dhclient-%%i.leases\n'
    printf 'ExecStart=/sbin/dhclient -4 -d -1 %%i\nRestart=on-success\n'
  } > "/mnt/sysimage/etc/systemd/system/dhclient@.service"
  printf '[Unit]\nDescription=dhclient watchdog for %%I\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=30min\nUnit=dhclient@%%i.service\n[Install]\nWantedBy=timers.target\n' > "/mnt/sysimage/etc/systemd/system/dhclient@.timer"

  printf '[Unit]\nDescription=dhclient fallback for %%I\n[Service]\nType=oneshot\nExecStart=/usr/local/libexec/dhclient-fallback.sh %%i\n' > "/mnt/sysimage/etc/systemd/system/dhclient-fallback@.service"
  {
    printf '#!/usr/bin/env bash\nif [ -f "/usr/local/etc/dhclient-fallback/${1}.conf" ] ; then\n'
    printf ' source "/usr/local/etc/dhclient-fallback/${1}.conf"\nelse\n exit 0\nfi\n'
    printf 'ip addr add "${IPADDR0}" dev "${1}"\n'
    printf 'if [ ! -z "${GATEWAY}" ]; then\n ip route add default via "${GATEWAY}"\nfi\n'
  } > "/mnt/sysimage/usr/local/libexec/dhclient-fallback.sh"
  chmod +x /mnt/sysimage/usr/local/libexec/dhclient-fallback.sh

  mkdir /mnt/sysimage/etc/systemd/system/timers.target.wants
  ln -s /etc/systemd/system/dhclient@.timer /mnt/sysimage/etc/systemd/system/timers.target.wants/dhclient@virthost.timer

  # configure last-ditch DNS here too.
  printf 'nameserver 8.8.8.8\n' > /mnt/sysimage/etc/resolv.conf

  # if we have a fallback ipv4 for virthost, here you go
  if [ ! -z "${fallback_ipv4}" ] ; then
     mkdir -p /mnt/sysimage/usr/local/etc/dhclient-fallback
    printf 'IPADDR0=%s\nGATEWAY=172.16.143.129\n' "${fallback_ipv4}" > "/mnt/sysimage/usr/local/etc/dhclient-fallback/virthost.conf"
  fi

  # while we're here, install udev trickery to autobridge all the other ethernet adapters
  mkdir -p /mnt/sysimage/etc/udev/autobr-lmac
  {
    printf 'SUBSYSTEM!="net", GOTO="autobr_end"\n'
    printf 'ACTION!="add", GOTO="autobr_end"\n'
    printf 'ENV{INTERFACE}=="lo", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="bridge", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="vlan", GOTO="autobr_end"\n'
    printf 'ENV{DEVTYPE}=="wlan", GOTO="autobr_end"\n'
    printf 'ENV{ID_NET_DRIVER}=="tun", GOTO="autobr_end"\n'
    printf 'PROGRAM="/usr/bin/test -e /etc/systemd/network/%%k.network", GOTO="autobr_end"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k down"\n'
    printf 'RUN+="/etc/udev/autobr-lmac.sh"\n'
    printf 'RUN+="/usr/sbin/ip link add br-%%k type bridge"\n'
    printf 'RUN+="/usr/sbin/ip link set dev %%k master br-%%k"\n'
    printf 'RUN+="/usr/sbin/ip link set %%k up"\n'
    printf 'RUN+="/usr/sbin/ip link set br-%%k up"\n'
    printf 'ENV{NM_UNMANAGED}="1"\n'
    printf 'LABEL="autobr_end"\n'
  } > /mnt/sysimage/etc/udev/rules.d/81-autobridge.rules

  {
    printf '5A'
    dd bs=1 count=2 if=/dev/random 2>/dev/null | hexdump -v -e '/1 ":%02X"'
  } > /mnt/sysimage/etc/udev/autobr-lmac/prefix

  {
    printf '#!/bin/bash\n'
    printf 'cmac=${ID_NET_NAME_MAC: -12}\n'
    printf 'if [ ! -f "/etc/udev/autobr-lmac/lmac.${cmac}" ] ; then\n'
    printf '{\n cat /etc/udev/autobr-lmac/prefix\n dd bs=1 count=3 if=/dev/random 2>/dev/null |hexdump -v -e '"'"'/1 ":%%02X"'"'"'\n} > "/etc/udev/autobr-lmac/lmac.${cmac}"\n'
    printf 'fi\n'
    printf 'read lmac < "/etc/udev/autobr-lmac/lmac.${cmac}"\n'
    printf 'if [ ${#lmac} -eq 17 ] ; then\n'
    printf ' /sbin/ip link set dev "${INTERFACE}" address "${lmac}"\n'
    printf 'fi\n'
  } > /mnt/sysimage/etc/udev/autobr-lmac.sh

  chmod +x /mnt/sysimage/etc/udev/autobr-lmac.sh
fi

# configure nut if we find a ups...
for hiddev in /sys/class/hidraw/* ; do
  hidpath=$(readlink "${hiddev}")	# ../../devices/pci.../port:vend:devi.ep/hidraw/hidrawX
  hidpath=${hidpath%.*}		# ../../devices/pci.../port:vend:devi
  hidpath=${hidpath##*/}		# port:vend:devi
  hidpath=${hidpath#*:}		# vend:devi
  case $hidpath in
    "0764:0501")
      upsmon_pw=$(/mnt/sysimage/usr/bin/apg -M SNCL -m 21 -n 1)
      upsmast_pw=$(/mnt/sysimage/usr/bin/apg -M SNCL -m 21 -n 1)
      root_pw=$(/mnt/sysimage/usr/bin/apg -M SNCL -m 21 -n 1)
      printf '[ups]\n driver = usbhid-ups\n port = auto\n desc = "detected USB UPS"\n sdorder = 1\n' > /mnt/sysimage/etc/ups/ups.conf
      {
        printf '[upsmon]\n password = %s\n upsmon slave\n[upsmast]\n password = %s\n upsmon master\n' "${upsmon_pw}" "${upsmast_pw}"
        printf '[root]\n password = %s\n actions = SET\n instcmds = ALL\n' "${root_pw}"
      } > /mnt/sysimage/etc/ups/upsd.users
      printf 'MONITOR ups@localhost 1 upsmast %s master\n' "${upsmast_pw}" >> /mnt/sysimage/etc/ups/upsmon.conf
      ln -s /usr/lib/systemd/system/nut-server.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/nut-server.service
      ln -s /usr/lib/systemd/system/nut-monitor.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/nut-monitor.service
      ;;
    *) : ;;	# nop
  esac
done

# hand some usb devices over for direct passthrough by unbinding them
{
  printf 'SUBSYSTEM=="usb",ATTRS{idVendor}=="0b05",ATTRS{idProduct}=="1784",RUN="/bin/sh -c echo -n $kernel > /sys/bus/drivers/$driver/unbind"\n'
  printf 'SUBSYSTEM=="usb",ATTRS{idVendor}=="2478",ATTRS{idProduct}=="2008",RUN="/bin/sh -c echo -n $kernel > /sys/bus/drivers/$driver/unbind"\n'
} > /mnt/sysimage/etc/udev/rules.d/81-autopass.rules

# configure chronyd
{
  printf 'server ntp.bblug.org\nserver vision.arlen.io\nserver time-b.pts0.net\n'
  printf 'allow 192.168.128.128/25\nbindaddress 192.168.128.129\n'
} > /mnt/sysimage/etc/chrony.conf

# serial ports on tmux via...systemd and uucp
AUTOCONS_SPEED=115200
if [[ " tungsten " =~ " ${syscfg} " ]] ; then
  AUTOCONS_SPEED=9600
fi
{
  printf '[Unit]\nDescription=tmux console\n[Service]\nType=oneshot\nExecStart=/bin/tmux -L console new-session -d -s console bash\nRemainAfterExit=yes\n'
} > "/mnt/sysimage/etc/systemd/system/tmux-console.service"
ln -s /etc/systemd/system/tmux-console.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/tmux-console.service
{
  printf '[Unit]\nDescription=tmux serial on %%I\nRequires=tmux-console.service\nAfter=tmux-console.service\n'
  printf '[Service]\nType=oneshot\nExecStart=/bin/tmux -L console new-window -d -n %%i '"'"'cu -s %s -l /dev/%%i'"'"'\n' "${AUTOCONS_SPEED}"
  printf 'RemainAfterExit=yes\n'
} > "/mnt/sysimage/etc/systemd/system/tmux-serial@.service"
{
  printf '#!/bin/bash\n'
  printf 'set -eux\n'
  printf 'set -o pipefail\n'
  printf 'shopt -s nullglob\n'
  printf 'for ser in /dev/ttyUSB* /dev/ttyACM* ; do\n'
  printf ' ser=${ser##*/}\n'
  printf ' eval $(udevadm info -q property -n /dev/${ser} -x)\n'
  printf ' case "${ID_VENDOR_ID}:${ID_MODEL_ID}" in\n'
  printf '  2478:2008) continue ;;\n'
  printf ' esac\n'
  printf ' set +e\n'
  printf ' systemctl -q status "serial-getty@${ser}.service" > /dev/null\n'
  printf ' rc="${?}"\n'
  printf ' if [ "${?}" -eq 0 ] ; then\n'
  printf '  set -e\n'
  printf '  systemctl start "tmux-serial@${ser}"\n'
  printf ' fi\n set -e\n'
  printf 'done'
} > "/mnt/sysimage/usr/local/libexec/serial-coldplug.sh"
chmod +x /mnt/sysimage/usr/local/libexec/serial-coldplug.sh
printf '[Unit]\nDescription=serial port console - tmux coldplug\n[Service]\nType=oneshot\nExecStart=/usr/local/libexec/serial-coldplug.sh\n' > "/mnt/sysimage/etc/systemd/system/tmux-serial-coldplug.service"
ln -s /etc/systemd/system/tmux-serial-coldplug.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/tmux-serial-coldplug.service

# configure spare libvirtd network
{
  printf '<network>\n'
  printf ' <name>alternative</name>\n'
  printf ' <uuid>%s</uuid>\n' "$(uuidgen)"
  printf ' <forward mode='"'"'nat'"'"'/>\n'
  printf ' <bridge name='"'"'virbr1'"'"' stp='"'"'on'"'"' delay='"'"'0'"'"'/>\n'
  printf ' <mac address='"'"'%s'"'"'/>\n' $({ printf '5A'; dd bs=1 count=5 if=/dev/random 2>/dev/null | hexdump -v -e '/1 ":%02X"'; })
  printf ' <ip address='"'"'192.168.212.1'"'"' netmask='"'"'255.255.255.0'"'"'>\n'
  printf '  <dhcp>\n   <range start='"'"'192.168.212.2'"'"' end='"'"'192.168.212.254'"'"'/>\n  </dhcp>\n'
  printf ' </ip>\n'
  printf '</network>\n'
} > "/mnt/sysimage/etc/libvirt/qemu/networks/alternative.xml"

# disable libvirt network autostarts
rm /mnt/sysimage/etc/libvirt/qemu/networks/autostart/*

# hook libvirtd scripts to plug in to tmux
mkdir -p /mnt/sysimage/etc/libvirt/hooks
{
  printf '#!/bin/bash\n'
  printf 'if [ "${2}" == "started" ] ; then\n'
  printf ' systemctl start tmux-console.service\n'
  printf ' tmux -L console new-window -d -n "${1}" "virsh console ${1}"\n'
  printf 'fi\n'
} > "/mnt/sysimage/etc/libvirt/hooks/qemu"
chmod +x /mnt/sysimage/etc/libvirt/hooks/qemu

# handy script to derive ipv4 on vmm for a given domain
{
  printf '#!/bin/bash\n'
  printf 'if [ -z "${1}" ] ; then echo "supply a domain" 1>&2 ; exit ; fi\n'
  printf 'if [ -f "/var/lib/dnsmasq/dnsmasq.leases" ] ; then lf="/var/lib/dnsmasq/dnsmasq.leases"\n'
  printf 'elif [ -f "/var/lib/misc/dnsmasq.leases" ] ; then lf="/var/lib/misc/dnsmasq.leases"\n'
  printf 'fi\n'

  printf 'mac=$(virsh domiflist "${1}"|awk '"'"'$3 == "vmm" {print $5}'"'"')\n'
  printf 'if [ -z "${mac}" ] ; then echo "error getting vmm mac for domain ${1}" 1>&2 ; exit ; fi\n'

  printf 'awk '"'"'$2 == "'"'"'"${mac}"'"'"'" { print $3 }'"'"' < "${lf}"\n'
} > "/mnt/sysimage/usr/local/sbin/vmm-ip"
chmod +x /mnt/sysimage/usr/local/sbin/vmm-ip

# copy install repo to www share
if [ -d /run/install/repo/bootstrap-scripts ] ; then
  mkdir -p /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7/
  cp -R /run/install/repo/Packages /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/images /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/repodata /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/LiveOS /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/.discinfo /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/ks /mnt/sysimage/usr/share/nginx/html/bootstrap
  if [ -f /run/install/repo/authorized_keys ] ; then
    cp /run/install/repo/authorized_keys /mnt/sysimage/usr/share/nginx/html/bootstrap
  fi
  cp -R /run/install/repo/intca-pub /mnt/sysimage/usr/share/nginx/html/bootstrap
  cp -R /run/install/repo/certs /mnt/sysimage/usr/share/nginx/html/bootstrap
  cp -R /run/install/repo/bootstrap-scripts /mnt/sysimage/root
  cp -R /run/install/repo/ipxe-binaries.tgz /mnt/sysimage/usr/share/nginx/html/bootstrap
  cp -R /run/install/repo/openbsd-dist /mnt/sysimage/usr/share/nginx/html/bootstrap/openbsd
  find /run/install/repo/usr/share/nginx/html -type d -exec chmod a+rx {} \;
  find /run/install/repo/usr/share/nginx/html -type f -exec chmod a+r {} \;
fi

# copy private-isos to /var/lib/libvirt
if [ -d /run/install/repo/private-isos ] ; then
  mkdir -p /mnt/sysimage/var/lib/libvirt/images
  cp -R /run/install/repo/private-isos /mnt/sysimage/var/lib/libvirt/images/private
fi

%end
