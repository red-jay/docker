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
timezone America/Los_Angeles --isUtc

# System services
services --enabled="lldpad,chronyd"

%packages
@core
@^minimal
-kernel
kernel-ml

chrony
kexec-tools
-fprintd-pam
-intltool
-mariadb-libs
-postfix
-linux-firmware
-aic94xx-firmware
-atmel-firmware
-b43-openfwwf
-bfa-firmware
-ipw2100-firmware
-ipw2200-firmware
-ivtv-firmware
-iwl100-firmware
-iwl105-firmware
-iwl135-firmware
-iwl1000-firmware
-iwl2030-firmware
-iwl2000-firmware
-iwl3060-firmware
-iwl3160-firmware
-iwl3945-firmware
-iwl4965-firmware
-iwl5000-firmware
-iwl5150-firmware
-iwl6000-firmware
-iwl6000g2a-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-iwl7260-firmware
-iwl7265-firmware
-libertas-sd8686-firmware
-libertas-sd8787-firmware
-libertas-usb8388-firmware
-ql2100-firmware
-ql2200-firmware
-ql23xx-firmware
-ql2400-firmware
-ql2500-firmware
-rt61pci-firmware
-rt73usb-firmware
-xorg-x11-drv-ati-firmware
-zd1211-firmware

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

dosfstools
lvm2
authconfig

%include /tmp/package-include

systemd-networkd

lldpad
epel-release
nut

open-vm-tools


dstat
htop
tmux
xorg-x11-xauth

policycoreutils-python

nginx
dhcp
memtest86+
tftp-server

# needed for org_fedora_oscap addon
openscap
openscap-scanner
scap-security-guide

%end

%addon org_fedora_oscap
    content-type = scap-security-guide
    profile = common
%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%pre
# be a chatterbox here
set -x

# on with nullglub
shopt -s nullglob

# parts that can be _reset_ by system config but have a default
reboot_flag="reboot"
inst_fqdn="netmgmt"

# first get if we have a syscfg on cmdline
read cmdline < /proc/cmdline
for ent in $cmdline ; do
  case $ent in
    syscfg=*)
      syscfg=${ent#syscfg=}
      ;;
    site=*)
      site=${ent#site=}
      ;;
    method=*)
      ks_method=${ent#method=}
      ;;
  esac
done































































# configure disks via magic script ;)
bash -x /run/install/repo/fs-layout.sh -W -S -m 8589934592

# this holds any needed conditional package statements
touch /tmp/package-include









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

if [ ! -z "${site}" ] ; then
  printf 'site="%s"\n' "${site}" >> /tmp/post-vars
fi

if [ ! -z "${ks_method}" ] ; then
  printf 'ks_method="%s"\n' "${ks_method}" >> /tmp/post-vars
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
if [ ! -z "${ks_method}" ] ; then
  mkdir -p /mnt/sysimage/root/.ssh
  curl -L -o /mnt/sysimage/root/.ssh/authorized_keys "${ks_method}/../authorized_keys"
  chmod 0700 /mnt/sysimage/root/.ssh
  chmod 0600 /mnt/sysimage/root/.ssh/authorized_keys
  printf 'PermitRootLogin without-password\n' >> /mnt/sysimage/etc/ssh/sshd_config
elif [ -f /run/install/repo/authorized_keys ] ; then
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

case "${site}" in
  sv1)
    # used for ip address assignment
    netm_range="172.16.16.72/29"
    netm_suffx="26"

    # used for dhcp
    dhcp_peer1="172.16.32.72"
    dhcp_netm="172.16.16.64/26 172.16.32.64/26"
    dhcp_trns="172.16.16.0/26 172.16.32.0/26"
    dhcp_virt="172.16.16.128/26 172.16.32.128/26"
    dhcp_pwln="172.16.52.0/27"
    dhcp_wext="172.16.52.32/27"

    dhcp_peer2="172.16.48.40"

    # firewalld
    internal_sources="${dhcp_netm} ${dhcp_trns} ${dhcp_virt}"
    ;;
  sv2)
    netm_range="172.16.32.72/29"
    netm_suffx="26"

    dhcp_peer1="172.16.16.72"
    dhcp_netm="172.16.32.64/26 172.16.16.64/26"
    dhcp_trns="172.16.32.0/26 172.16.16.0/26"
    dhcp_virt="172.16.32.128/26 172.16.16.128/26"
    dhcp_pwln="172.16.52.0/27"
    dhcp_wext="172.16.52.32/27"

    # firewalld
    internal_sources="${dhcp_netm} ${dhcp_trns} ${dhcp_virt}"
    ;;
  sv1a)
    netm_range="172.16.48.40/30"
    netm_suffx="27"

    dhcp_peer1="172.16.16.72"
    dhcp_netm="172.16.48.32/27"
    dhcp_trns="172.16.48.0/27"
    dhcp_virt="172.16.48.128/27"

    # firewalld
    internal_sources="${dhcp_netm} ${dhcp_trns} ${dhcp_virt}"
    ;;
  pa)
    netm_range="192.168.16.8/30"
    netm_suffx="26"

    dhcp_netm="192.168.16.64/26"
    dhcp_trns="192.168.16.0/26"
    dhcp_virt="192.168.16.128/26"

    # firewalld
    internal_sources="${dhcp_netm} ${dhcp_trns} ${dhcp_virt}"
    ;;
esac

# NOTE: all this code assumes smaller-than-C (/24) allocations
#       to be specific, that we can get away with just +1 on
#       the last octet.
suffix=${netm_range#*/}
prefix=${netm_range%.*}

first_loctet=${netm_range%/$suffix}
first_loctet=${first_loctet##*.}

# this however, works around a bug in centos ipcalc.
case ${suffix} in
  31)
    last_loctet=${first_loctet}
    scratch=$((last_loctet++))
    ;;
  32)
    last_loctet=${first_loctet}
    ;;
  *)
    last_loctet=$(ipcalc -b ${netm_range})
    last_loctet=${last_loctet##*.}
    ;;
esac

gw_loctet=$(ipcalc -n "${prefix}.${first_loctet}/${netm_suffx}")
gw_loctet=${gw_loctet##*.}
scratch=$((gw_loctet++))
gateway="${prefix}.${gw_loctet}"

declare -a nm_addr
i=0
for octet in $(seq ${first_loctet} ${last_loctet}) ; do
  nm_addr[i]="${prefix}.${octet}/${netm_suffx}"
  scratch=$((i++))
done

# configure the network using systemd-networkd here.
mkdir -p /mnt/sysimage/etc/systemd/network/

{
  printf '[Match]\nName=eth0\n[Network]\nDHCP=no\nLinkLocalAddressing=no\nLLMNR=no\nMulticastDNS=no\n'
  printf 'Address=%s\n' "${nm_addr[0]}"
  printf 'Address=%s\n' "${nm_addr[1]}"
  if [ ! -z "${nm_addr[2]}" ] ; then
    printf 'Address=%s\n' "${nm_addr[2]}"
  fi
  printf 'Gateway=%s\n' "${gateway}"
} > /mnt/sysimage/etc/systemd/network/eth0.network

{
  printf '[Match]\nName=eth1\n[Network]\nDHCP=yes\nLinkLocalAddressing=no\LLMNR=no\nMulticastDNS=no\n'
} > /mnt/sysimage/etc/systemd/network/eth1.network

# shoot NetworkManager in the face
ln -s /dev/null /mnt/sysimage/etc/systemd/system/NetworkManager.service
ln -s /dev/null /mnt/sysimage/etc/systemd/system/NetworkManager-wait-online.service
rm -f /mnt/sysimage/etc/systemd/system/dbus-org.freedesktop.NetworkManager.service.
rm -f /mnt/sysimage/etc/systemd/system/multi-user.target.wants/NetworkManager.service.
rm -f /mnt/sysimage/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service.
ln -s /usr/lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
rm -f /etc/udev/rules.d/70-persistent-net.rules

# disable ipv6 for most things
printf 'net.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 0\n' > /mnt/sysimage/etc/sysctl.d/40-ipv6.conf

# configure last-ditch DNS here too.
printf 'nameserver 8.8.8.8\n' > /mnt/sysimage/etc/resolv.conf

# configure dhcpd

	cat <<-EOF > /mnt/sysimage/etc/dhcp/ipxe-option-space.conf
		# Declare the iPXE/gPXE/Etherboot option space
		option space ipxe;
		option ipxe-encap-opts code 175 = encapsulate ipxe;

		# iPXE options, can be set in DHCP response packet
		option ipxe.priority         code   1 = signed integer 8;
		option ipxe.keep-san         code   8 = unsigned integer 8;
		option ipxe.skip-san-boot    code   9 = unsigned integer 8;
		option ipxe.syslogs          code  85 = string;
		option ipxe.cert             code  91 = string;
		option ipxe.privkey          code  92 = string;
		option ipxe.crosscert        code  93 = string;
		option ipxe.no-pxedhcp       code 176 = unsigned integer 8;
		option ipxe.bus-id           code 177 = string;
		option ipxe.bios-drive       code 189 = unsigned integer 8;
		option ipxe.username         code 190 = string;
		option ipxe.password         code 191 = string;
		option ipxe.reverse-username code 192 = string;
		option ipxe.reverse-password code 193 = string;
		option ipxe.version          code 235 = string;
		option iscsi-initiator-iqn   code 203 = string;

		# iPXE feature flags, set in DHCP request packet
		option ipxe.pxeext    code 16 = unsigned integer 8;
		option ipxe.iscsi     code 17 = unsigned integer 8;
		option ipxe.aoe       code 18 = unsigned integer 8;
		option ipxe.http      code 19 = unsigned integer 8;
		option ipxe.https     code 20 = unsigned integer 8;
		option ipxe.tftp      code 21 = unsigned integer 8;
		option ipxe.ftp       code 22 = unsigned integer 8;
		option ipxe.dns       code 23 = unsigned integer 8;
		option ipxe.bzimage   code 24 = unsigned integer 8;
		option ipxe.multiboot code 25 = unsigned integer 8;
		option ipxe.slam      code 26 = unsigned integer 8;
		option ipxe.srp       code 27 = unsigned integer 8;
		option ipxe.nbi       code 32 = unsigned integer 8;
		option ipxe.pxe       code 33 = unsigned integer 8;
		option ipxe.elf       code 34 = unsigned integer 8;
		option ipxe.comboot   code 35 = unsigned integer 8;
		option ipxe.efi       code 36 = unsigned integer 8;
		option ipxe.fcoe      code 37 = unsigned integer 8;
		option ipxe.vlan      code 38 = unsigned integer 8;
		option ipxe.menu      code 39 = unsigned integer 8;
		option ipxe.sdi       code 40 = unsigned integer 8;
		option ipxe.nfs       code 41 = unsigned integer 8;

		# Other useful general options
		# http://www.ietf.org/assignments/dhcpv6-parameters/dhcpv6-parameters.txt
		option arch code 93 = unsigned integer 16;
	EOF

dhcp_subnet() {
  local subnet tag next
  subnet="${1}"
  tag="${2}"
  next="${3}"

  local scratch staticslice
  local sub_addr sub_mask prefix bcast
  local net_loctet gw_loctet bw_loctet lh_loctet
  local hostct hostoffset hoststart

  if [ -z "${4}" ] ; then
    staticslice=4
  else
    staticslice="${4}"
  fi

  sub_addr=${subnet%/*}
  sub_mask=$(ipcalc -m "${subnet}")
  sub_mask=${sub_mask##*=}
  prefix=${subnet%.*}
  net_loctet=${subnet#${prefix}.}
  net_loctet=${net_loctet%/*}
  gw_loctet=${net_loctet}
  scratch=$((gw_loctet++))
  bcast=$(ipcalc -b "${subnet}")
  bcast=${bcast##*=}
  bw_loctet=${bcast#${prefix}.}
  lh_loctet=${bw_loctet}
  scratch=$((bw_loctet--))
  hostct=$(($lh_loctet-$gw_loctet))
  # below range works as long as you are working with a /29 in a /26...
  # ...and you start counting from the router ;)
  hostoffset=$(($hostct / $staticslice))
  hoststart=$(($gw_loctet + $hostoffset))

  printf 'subnet %s netmask %s { pool {\n' "${sub_addr}" "${sub_mask}"
  printf ' allow members of "%s";\n' "${tag}"
  printf ' option subnet-mask %s;\n' "${sub_mask}"
  printf ' option routers %s;\n' "${prefix}.${gw_loctet}"
  printf ' option broadcast-address %s;\n' "${bcast}"
  printf ' range dynamic-bootp %s %s;\n' "${prefix}.${hoststart}" "${prefix}.${lh_loctet}"
  printf ' next-server %s;\n' "${next}"
  printf '} }\n'
}

{
  printf 'authoritative;\n'
  printf 'ddns-update-style none;\n'
  printf 'use-host-decl-names on;\n'
  printf 'option px-network code 170 = text;\n'
  printf 'include "/etc/dhcp/ipxe-option-space.conf";\n'
  printf 'class "netmgmt" { match hardware; }\n'
  printf 'class "transit" { match hardware; }\n'
  printf 'class "virthost" { match hardware; }\n'
  printf 'class "powerline" { match hardware; }\n'
  printf 'class "wifiext" { match hardware; }\n'

  # you're only allowed one-next server, may as well leave it as whoever answers.
  nextserver="${netm_range%/*}"

  # netmgmt
  for subnet in ${dhcp_netm} ; do
    dhcp_subnet "${subnet}" "netmgmt" "${nextserver}"
  done

  # transit
  for subnet in ${dhcp_trns} ; do
    dhcp_subnet "${subnet}" "transit" "${nextserver}" 2
  done

  # virthost
  for subnet in ${dhcp_virt} ; do
    dhcp_subnet "${subnet}" "virthost" "${nextserver}"
  done

  # pwln
  for subnet in ${dhcp_pwln} ; do
    dhcp_subnet "${subnet}" "powerline" "${nextserver}" 2
  done

  # wext
  for subnet in ${dhcp_wext} ; do
    dhcp_subnet "${subnet}" "wifiext" "${nextserver}" 2
  done

  printf 'if    exists ipxe.http\n'
  printf '  and exists ipxe.menu\n'
  printf '  and exists ipxe.dns\n'
  printf '  and exists ipxe.tftp\n'
  printf '{\n'
  printf ' filename "tftp://${next-server}/ipxe.d/init.ipxe";\n'
  printf '}\n'

  printf 'elsif exists user-class and option user-class = "iPXE" {\n'
  printf '   if option arch =      00:06 {\n'
  printf ' filename "ipxe/vc/ipxe-i386.efi";\n'
  printf '   } elsif option arch = 00:07 {\n'
  printf ' filename "ipxe/vc/ipxe-x86_64.efi";\n'
  printf '   } elsif option arch = 00:00 {\n'
  printf ' filename "ipxe/vc/ipxe-pcbios.lkrn";\n'
  printf '   }\n'
  printf '}\n'

  printf 'elsif option arch =      00:06 {\n'
  printf ' filename "ipxe/vc/ipxe-i386.efi";\n'
  printf '} elsif option arch =    00:07 {\n'
  printf ' filename "ipxe/vc/ipxe-x86_64.efi";\n'
  printf '} elsif option arch =    00:00 {\n'
  printf ' filename "ipxe/vc/ipxe-pcbios.pxe";\n'
  printf '} else {\n'
  printf ' filename "auto_install";\n'
  printf '}\n'

  # ifw
  printf 'subclass "netmgmt" 1:52:54:00:44:C9:2E; subclass "netmgmt" 52:54:00:44:C9:2E;\n'
  printf 'host ifw.sv1 { hardware ethernet 52:54:00:44:C9:2E; option host-name "ifw.sv1.bbxn.us"; }\n'

  printf 'subclass "netmgmt" 1:52:54:00:44:C7:2E; subclass "netmgmt" 52:54:00:44:C7:2E;\n'
  printf 'host ifw.sv2 { hardware ethernet 52:54:00:44:C7:2E; option host-name "ifw.sv2.bbxn.us"; }\n'

  printf 'subclass "transit" 1:52:54:00:4E:CC:0F; subclass "netmgmt" 52:54:00:4E:CC:0F;\n'
  printf 'host efw { hardware ethernet 52:54:00:4E:CC:0F; option host-name "efw.bbxn.us"; }\n'

  # tgw
  printf 'subclass "transit" 1:52:54:00:CC:EF:04; subclass "transit" 52:54:00:CC:EF:04;\n'
  printf 'host tgw.sv1 { hardware ethernet 54:54:00:CC:EF:04; option host-name "tgw.sv1.bbxn.us"; }\n'

  printf 'subclass "transit" 1:52:54:00:3E:EE:84; subclass "transit" 52:54:00:3E:EE:84;\n'
  printf 'host tgw.sv2 { hardware ethernet 54:54:00:3E:EE:84; option host-name "tgw.sv2.bbxn.us"; }\n'

  printf 'host tgw.sv2.pl { hardware ethernet 52:54:00:22:ca:be; fixed-address 172.16.52.8;}\n'

  # ufw
  # dfw

  # efw
  printf 'subclass "transit" 1:52:54:00:CE:88:02; subclass "transit" 52:54:00:CE:88:02;\n'
  printf 'host efw.sv1 { hardware ethernet 52:54:00:CE:88:02; option host-name "efw.sv1.bbxn.us"; }\n'

  # switches!
  printf 'subclass "netmgmt" 1:88:75:56:6a:d6:c1; subclass "netmgmt" 88:75:56:6a:d6:c1;\n'
  printf 'host lr-kallax-sw { hardware ethernet 88:75:56:6a:d6:c1; option host-name "lr-kallax-sw"; }\n'

  printf 'subclass "netmgmt" 1:a0:21:b7:af:2a:bd; subclass "netmgmt" a0:21:b7:af:2a:bd;\n'
  printf 'host kitchen-sw { hardware ethernet a0:21:b7:af:2a:bd; option host-name "kitchen-sw"; }\n'

  printf 'subclass "netmgmt" 1:30:f7:0d:8c:d0:4b; subclass "netmgmt" 30:f7:0d:8c:d0:4b;\n'
  printf 'host kitchen-ap { hardware ethernet 30:f7:0d:8c:d0:4b; option host-name "kitchen-ap"; }\n'

  printf 'subclass "netmgmt" 1:9c:3d:cf:f9:51:1e; subclass "netmgmt" 9c:3d:cf:f9:51:1e;\n'
  printf 'host br2-sw { hardware ethernet 9c:3d:cf:f9:51:1e; option host-name "br2-sw"; }\n'
} > /mnt/sysimage/etc/dhcp/dhcpd.conf

# dhcp managing script
{
  printf '#!/usr/bin/bash\n'
  printf 'if [ "$#" -lt 2 ]; then echo "group mac [name]" 1>&2 ; exit 1; fi\n'
  printf 'cls="${1}" ; mac="${2}"\n'
  printf 'printf '"'"'subclass "%%s" 1:%%s; subclass "%%s" %%s;\\n'"'"' "${cls}" "${mac}" "${cls}" "${mac}" >> /etc/dhcp/dhcpd.conf\n'
  printf 'if [ "$#" -eq 3 ] ; then\n'
  printf 'hst="${3}"\n'
  printf 'printf '"'"'host %%s { hardware ethernet %%s; option host-name "%%s"; }\\n'"'"' "${hst}" "${mac}" "${hst}" >> /etc/dhcp/dhcpd.conf\n'
  printf 'fi\n'
} > /mnt/sysimage/usr/local/sbin/addhost
chmod +x /mnt/sysimage/usr/local/sbin/addhost

# enable dhcpd, tftpd
{
  printf '[Unit]\nDescription=tftpd vhost on %%I\nWants=network-online.target\nAfter=network-online.target\n'
  printf '[Service]\nExecStart=/sbin/in.tftpd -L --address %%i -s -P /run/tftpd-%%i.pid /var/lib/tftpboot/vh-%%i\n'
} > /mnt/sysimage/etc/systemd/system/tftpd@.service

tftp_std=${nm_addr[0]%/*}	# standard tftp service
tftp_com1=${nm_addr[1]%/*}	# for obsd/com1/x86
tftp_com2=${nm_addr[2]%/*}	# for obsd/com2/x86

ln -s /usr/lib/systemd/system/dhcpd.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/dhcpd.service
ln -s /etc/systemd/system/tftpd@.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/tftpd@${tftp_std}.service
ln -s /etc/systemd/system/tftpd@.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/tftpd@${tftp_com1}.service
if [ ! -z "${tftp_com2}" ] ; then
  ln -s /etc/systemd/system/tftpd@.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/tftpd@${tftp_com2}.service
fi

# enable nginx
ln -s /usr/lib/systemd/system/nginx.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/nginx.service

# configure firewalld as needed
for srcset in ${internal_sources} ; do
  chroot /mnt/sysimage /bin/firewall-offline-cmd --zone internal --add-source "${srcset}"
done
chroot /mnt/sysimage /bin/firewall-offline-cmd --zone internal --add-service tftp
chroot /mnt/sysimage /bin/firewall-offline-cmd --zone internal --add-service http

# copy ipxe binaries about
mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe
if [ ! -z "${ks_method}" ] ; then
  ipxe_tgz="${ks_method}/../ipxe-binaries.tgz"
elif [ -f /mnt/install/repo/ipxe-binaries.tgz ] ; then
  ipxe_tgz=file:///mnt/install/repo/ipxe-binaries.tgz
fi

if [ ! -z "${ipxe_tgz}" ] ; then
  curl "${ipxe_tgz}" | tar xz -C /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe
fi

# create ipxe configs
mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/{plat,mfr,sys,com}

{
  printf '#!ipxe\necho iPXE loaded\n'
  printf 'cpuid --ext 29 && set arch x86_64 || set arch i386\n'
  printf 'chain plat/${buildarch}-${platform}.ipxe ||\n'
  printf 'chain mfr/${manufacturer}/${buildarch}-${platform}.ipxe ||\n'
  printf 'chain mfr/${manufacturer}.ipxe ||\n'
  printf 'chain mac/${netX/mac:hexhyp}.ipxe ||\n'
  printf 'shell\n'
} > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/init.ipxe

{
  printf '#!ipxe\n'
  printf 'chain mac/${netX/mac:hexhyp}.ipxe ||\n'
  printf 'shell\n'
} > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/com.ipxe

# QEMU BIOS - use first serial port
mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mfr/QEMU
pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mfr
ln -s QEMU Xen
ln -s QEMU Red\ Hat
popd
{
  printf '#!ipxe\nchain tftp://${next-server}/ipxe/com1/ipxe-${platform}.pxe ||\n'
} > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mfr/QEMU/i386-pcbios.ipxe

# grub
chroot /mnt/sysimage grub2-mknetdir --net-directory=/var/lib/tftpboot/vh-${tftp_std}/ --subdir _grub
for sc in com1 com2 ; do
  cp=${sc#com}
  gs=$cp
  scratch=$((gs--))
  chroot /mnt/sysimage grub2-mkimage -O i386-pc-pxe --output=/var/lib/tftpboot/vh-${tftp_std}/_grub/i386-pc/${sc}.0 --prefix="(pxe)/grub.d/${sc}" pxe tftp
  mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/i386-pc/
  pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/i386-pc/
   ln -s ../../../_grub/i386-pc/
  popd
  {
    printf 'serial --unit=%s --speed=115200\n' "${gs}"
    printf 'terminal_input serial console\n'
    printf 'terminal_output serial console\n'
    printf 'load_env\n'
    printf 'if cpuid -l ; then arch=x86_64 ; else arch=$buildarch ; fi\n'
  } > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grub.cfg
  chroot /mnt/sysimage grub2-editenv /var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grubenv create
  chroot /mnt/sysimage grub2-editenv /var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grubenv set r=/grub.d
  chroot /mnt/sysimage grub2-editenv /var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grubenv set comport=${cp}
  chroot /mnt/sysimage grub2-editenv /var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grubenv set buildarch=i386
  chroot /mnt/sysimage grub2-editenv /var/lib/tftpboot/vh-${tftp_std}/grub.d/${sc}/grubenv set platform=pcbios
done

pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/_grub/
 ln -s i386-pc i386-pcbios
popd


if [ ! -z "${ks_method}" ] ; then
  obsd_toplev="${ks_method}../openbsd"
  obsd_uri="${ks_method}../openbsd/${ob_ver}/amd64"
elif [ -d /mnt/install/repo/openbsd-dist/ ] ; then
  obsd_toplev="/mnt/install/repo/openbsd-dist"
fi

case $obsd_toplev in
  /*)
    for d in ${obsd_toplev}/* ; do
      if [ ! -d "${d}" ] ; then continue ; fi
      # LC_COLLATE is my friend!
      if [ -f "${d}/amd64/bsd" ] ; then
        obsd_uri="file://${d}/amd64"
        ob_ver="${d##*/}"
      fi
    done
    ;;
  http*)
    subs=$(curl "${obsd_toplev}/" 2>/dev/null|awk '$0 ~ "<a href=" { if ($1 == "<a") { split($2,j,"[<>]");print j[2] } }')
    for d in ${subs} ; do
      curl --head --fail "${obsd_toplev}/${d}/amd64/bsd" 2>/dev/null 1>&2
      rc=$?
      if [ ${rc} -eq 0 ] ; then
        obsd_uri="${obsd_toplev}/${d}/amd64"
        ob_ver="${d///}"
      fi
    done
    ;;
esac

obsd_idx="${obsd_uri}/index.txt"
ob_ver_nd=${ob_ver//.}

printf 'location /pub { autoindex on; }\n' > /mnt/sysimage/etc/nginx/default.d/pub.conf

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64
  curl -LO "${obsd_idx}"
  for f in $(awk '($9 && $9 != "index.txt") {print $9}' < index.txt) ; do
    curl -LO "${obsd_uri}/${f}"
  done
popd

case $obsd_toplev in
  /*)
    obp_uri="file://${obsd_toplev}/syspatch/${ob_ver}/amd64"
    ;;
  *)
    obp_uri="${obsd_toplev}/syspatch/${ob_ver}/amd64"
    ;;
esac
obs_sha="${obp_uri}/SHA256.sig"

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/syspatch/${ob_ver}/amd64
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/syspatch/${ob_ver}/amd64
  curl -LO "${obs_sha}"
  for f in $(awk '$1 == "SHA256" {print substr($2, 2, (length($2) - 2))}' < SHA256.sig) ; do
    curl -LO "${obp_uri}/${f}"
  done
popd

case $obsd_toplev in
  /*)
    obpkg_uri="file://${obsd_toplev}/${ob_ver}/packages/amd64"
    ;;
  *)
    obpkg_uri="${obsd_toplev}/${ob_ver}/packages/amd64"
    ;;
esac
obpkg_idx="${obpkg_uri}/index.txt"

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/packages/amd64
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/packages/amd64
  curl -LO "${obpkg_idx}"
  for f in $(awk 'NR>1 {print $NF}' < index.txt) ; do
    if [ $f == index.txt ] ; then continue ; fi
    curl -LO "${obpkg_uri}/${f}"
  done
popd

mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/_openbsd/${ob_ver}/amd64
pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/_openbsd/${ob_ver}/
  ln -s amd64 x86_64
  pushd amd64
    tar xf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/base*.tgz --strip-components=3 ./usr/mdec/pxeboot
    cp /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/bsd.rd .
    ln -s pxeboot pxeboot.0
  popd
popd

pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}
  ln -s ./_openbsd/${ob_ver}/amd64/bsd.rd bsd
popd

mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_com1}/_openbsd/${ob_ver}/amd64
pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_com1}
  pushd _openbsd/${ob_ver}/
    ln -s amd64 x86_64
    pushd amd64
      ln ../../../../vh-${tftp_std}/_openbsd/${ob_ver}/amd64/pxeboot
      ln ../../../../vh-${tftp_std}/_openbsd/${ob_ver}/amd64/bsd.rd
      ln -s pxeboot pxeboot.0
    popd
  popd
  mkdir etc
  printf 'stty 115200\nset tty com0\n' > etc/boot.conf
  ln ./_openbsd/${ob_ver}/amd64/bsd.rd bsd
popd

{
  printf '#!ipxe\n'
  printf 'iseq ${platform} pcbios && goto pcbios\n'
  printf 'echo could not handle platform\ngoto shell\n\n'
  printf ':pcbios\niseq ${arch} x86_64 && goto pcbios_x86_64 ||\n'
  printf 'echo could not handle processor architecture\ngoto shell\n\n'
  printf ':pcbios_x86_64\n'
  printf 'isset ${comport} || set pserver %s ||\n' "${tftp_std}"
  printf 'iseq ${comport} 1 && set pserver %s ||\n' "${tftp_com1}"
  printf 'isset ${pserver} && goto load ||\n'
  printf 'echo could not handle console\ngoto shell\n\n'
  printf ':load\n'
  printf 'set netX/next-server ${pserver}\n'
  printf 'set netX/filename auto_install\n'
  printf '\necho server:${next-server} file:${filename} set in PXE env pre-handoff\nsleep 1\n\n'
  printf 'chain tftp://${next-server}/_openbsd/%s/${arch}/pxeboot.0 ||\n' "${ob_ver}"
  printf ':shell\nshell\n'
} > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/openbsd

{
  printf '#!ipxe\n'
  printf 'chain tftp://${next-server}/_grub/${buildarch}-${platform}/com${comport}.0 ||\n'
  printf 'chain tftp://${next-server}/_grub/${buildarch}-${platform}/core.0 ||\n'
} > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/grub
pushd /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d
ln -s ../grub
ln -s ../openbsd
popd

# fix tftpboot perms
find /mnt/sysimage/var/lib/tftpboot -type d -exec chmod a+x {} \;
find /mnt/sysimage/var/lib/tftpboot -exec chmod a+r {} \;

# get vpn ca cert
if [ ! -z "${ks_method}" ] ; then
  curl -L -o /mnt/sysimage/usr/share/nginx/html/pub/BBXN_INT_SV1.pem "${ks_method}../intca-pub/BBXN_INT_SV1.pem"
  cert_idx="${ks_method}../certs/index.txt"
elif [ -f /mnt/install/repo/intca-pub/BBXN_INT_SV1.pem ] ; then
  cp /mnt/install/repo/intca-pub/BBXN_INT_SV1.pem /mnt/sysimage/usr/share/nginx/html/pub/BBXN_INT_SV1.pem
  cert_idx="file:///mnt/install/repo/certs/index.txt"
fi

# create openbsd site tree
mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc

# vio0 - netmgmt
printf 'rtlabel dist\ninet 172.16.16.65 255.255.255.192\n-inet6\ngroup netmgmt\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio0.sv1
printf 'rtlabel dist\ninet 172.16.32.65 255.255.255.192\n-inet6\ngroup netmgmt\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio0.sv2
# vio1 - vmm
printf 'dhcp\n-inet6\ngroup vmm\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio1
# vio2 - virthost
printf 'rtlabel dist\ninet 172.16.16.129 255.255.255.192\n-inet6\ngroup virthost\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio2.sv1
printf 'rtlabel dist\ninet 172.16.32.129 255.255.255.192\n-inet6\ngroup virthost\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio2.sv2
# vio3 - transit
printf 'rtlabel dist\ninet 172.16.16.1 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio3.sv1
printf 'rtlabel dist\ninet 172.16.32.1 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio3.sv2
# bgpd AS
{
  printf 'AS 4233244401\nrouter-id 172.16.16.1\nnexthop qualify via bgp\nlisten on 172.16.16.1\nnetwork inet rtlabel dist\n'
  printf 'deny from any prefix 10.0.0.0/8 prefixlen >= 8\ndeny from any prefix 192.168.0.0/16 prefixlen >=16\n'
  printf 'neighbor 172.16.16.11 {\n descr "tgw.sv1"\n remote-as 4233244401\n ttl-security yes\n announce IPv4 unicast\n}\n'
  printf 'neighbor 172.16.16.10 {\n descr "efw.sv1"\n remote-as 4233244401\n ttl-security yes\n announce IPv4 unicast\n}\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/bgpd.conf.sv1

{
  printf 'AS 4233244402\nrouter-id 172.16.32.1\nnexthop qualify via bgp\nlisten on 172.16.32.1\nnetwork inet rtlabel dist\n'
  printf 'deny from any prefix 10.0.0.0/8 prefixlen >= 8\ndeny from any prefix 192.168.0.0/16 prefixlen >=16\n'
  printf 'neighbor 172.16.32.11 {\n descr "tgw.sv2"\n remote-as 4233244402\n ttl-security yes\n announce IPv4 unicast\n}\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/bgpd.conf.sv2

{
  printf '#!/bin/sh\n'
  printf 'exec > /root/post.log ; exec 2>&1\n'
  printf 'site=$(hostname | sed '"-e 's/[^\.]*\.//' | sed -e 's/\..*//'"')\n'

  printf 'for f in /etc/hostname.*.$site ; do\n'
  printf ' basefile=$(echo $f | sed -e "s/\.$site//")\n'
  printf ' mv $f $basefile\n'
  printf 'done\n'

  printf 'mv -f /etc/bgpd.conf.$site /etc/bgpd.conf\n'

  printf 'rm /etc/hostname.*.*\n'
  printf 'rm /etc/bgpd.conf.*\n'

  printf 'rcctl enable bgpd\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_virthosts\n'
  printf 'rcctl enable dhcrelay_virthosts\nrcctl set dhcrelay_virthosts flags "-i vio2 172.16.16.72 172.16.32.72"\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_transit\n'
  printf 'rcctl enable dhcrelay_transit\nrcctl set dhcrelay_transit flags "-i vio3 172.16.16.72 172.16.32.72"\n'

  printf 'rcctl enable tftpproxy\nrcctl set tftpproxy flags -v\n'

  printf 'syspatch\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/install.site
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/install.site

{
  printf '#!/bin/sh\n'
  printf ':\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/rc.firsttime
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/rc.firsttime

{
  printf 'set skip on lo\n\n'

  printf 'anchor "ftp-proxy/*"\nanchor "tftp-proxy/*"\n'
  printf 'pass in on { virthosts netmgmt } inet proto tcp to port ftp flags S/SA modulate state divert-to 127.0.0.1 port 8021\n\n'

  printf 'block drop quick inet6 proto icmp6 all icmp6-type { routeradv, routersol }\n'
  printf 'block return log\n\n'

  printf 'pass out quick on netmgmt proto udp from port { 67, 68 } to %s port 67\n' "{172.16.16.72, 172.16.32.72}"
  printf 'pass out on vmm proto udp from port 68 to port 67\n'
  printf 'antispoof quick for { virthosts netmgmt vmm }\n\n'
  printf 'pass in on vmm proto tcp from (vmm:network) to (vmm) port 22\n'

  printf 'pass in on { virthosts transit } proto udp from port 68 to port 67\n'
  printf 'pass on { transit } proto tcp from (transit:network) to (transit:network) port 179\n'
  printf 'pass in proto udp from port 67 to {172.16.16.72, 172.16.32.72} port 67\n'
  printf 'pass in quick on transit proto udp from (transit:network) to %s port 69 divert-to 127.0.0.1 port 6969\n' "{172.16.16.72/29, 172.16.32.72/29}"
  printf 'pass out quick on netmgmt proto udp to %s port 69 group _tftp_proxy divert-reply\n' "{172.16.16.72/29, 172.16.32.72/29}"

  printf 'pass proto tcp from { (transit:network), (netmgmt) } to %s port 80\n' "{172.16.16.72, 172.16.32.72}"

} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/pf.conf

printf 'net.inet.ip.forwarding=1\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/sysctl.conf

install -m 0700 -d /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/root/.ssh
install -m 0600 /mnt/sysimage/root/.ssh/authorized_keys /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/root/.ssh/authorized_keys

tar cpzf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/site${ob_ver_nd}-ifw.tgz -C /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw .

# tgw site
mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc

# vio0 - transit
printf 'rtlabel dist\ninet 172.16.16.11 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio0.sv1
printf 'rtlabel dist\ninet 172.16.32.11 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio0.sv2
# vio1 - vmm
printf 'dhcp\n-inet6\ngroup vmm\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio1
# vio2 - pln
printf 'rtlabel dist\ninet 172.16.52.1 255.255.255.224\n-inet6\ngroup pln\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio2.sv1
printf 'dhcp\n-inet6\ngroup pln\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio2.sv2
# vio3 - wext
printf 'rtlabel dist\ninet 172.16.52.32 255.255.255.224\n-inet6\ngroup wext\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio3.sv1

# bgpd AS
{
  printf 'AS 4233244401\nrouter-id 172.16.16.11\n'
  printf 'nexthop qualify via bgp\nnetwork inet rtlabel dist\n'
  printf 'network 172.16.52.64/27\n'
  printf 'match from any set nexthop self\n'
  printf 'deny from any prefix 10.0.0.0/8 prefixlen >= 8\ndeny from any prefix 192.168.0.0/16 prefixlen >=16\n'
  printf 'group vpn {\n'
  printf ' neighbor 172.16.52.66 {\n  remote-as 4233244402\n  descr "tgw.sv2"\n  passive\n ttl-security yes\n }\n'
  printf ' neighbor 172.16.52.67 {\n  remote-as 4233244403\n  descr "tgw.sv1a"\n  passive\n ttl-security yes\n }\n'
  printf '}\n'
  printf 'deny to group vpn prefix 172.16.52.0/23 prefixlen >= 23\n'
  printf 'group transit {\n'
  printf ' neighbor 172.16.16.1  {\n  descr "ifw.sv1"\n  remote-as  4233244401\n  ttl-security  yes\n  announce IPv4 unicast\n }\n'
  printf ' neighbor 172.16.16.10 {\n  descr "efw.sv1"\n  remote-as  4233244401\n  ttl-security  yes\n  announce IPv4 unicast\n }\n'
  printf '}\n'
  printf 'deny to group transit prefix 172.16.16.0/20 prefixlen >= 20\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/bgpd.conf.sv1

{
  printf 'AS 4233244402\nrouter-id 172.16.32.11\n'
  printf 'nexthop qualify via bgp\nnetwork inet rtlabel dist\n'
  printf 'network 172.16.52.96/27\n'
  printf 'match from any set nexthop self\n'
  printf 'deny from any prefix 10.0.0.0/8 prefixlen >= 8\ndeny from any prefix 192.168.0.0/16 prefixlen >=16\n'
  printf 'group vpn {\n'
  printf ' neighbor 172.16.52.65 {\n  remote-as 4233244401\n  descr "tgw.sv1"\n  announce IPv4 unicast\n ttl-security yes\n }\n'
  printf ' neighbor 172.16.52.67 {\n  remote-as 4233244403\n  descr "tgw.sv1a"\n  passive\n ttl-security yes\n }\n'
  printf '}\n'
  printf 'deny to group vpn prefix 172.16.52.0/23 prefixlen >= 23\n'
  printf 'group transit {\n'
  printf ' neighbor 172.16.32.1 {\n  descr "ifw.sv2"\n  remote-as  4233244402\n  ttl-security  yes\n  announce IPv4 unicast\n }\n'
  printf '}\n'
  printf 'deny to group transit prefix 172.16.32.0/20 prefixlen >= 20\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/bgpd.conf.sv2

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn
{
  printf 'ca /etc/openvpn/certs/CA.pem\n'
  printf 'cert /etc/openvpn/certs/openvpn.crt\n'
  printf 'key /etc/openvpn/private/openvpn.key\n'
  printf 'dh /etc/openvpn/dh.pem\n'
  printf 'ifconfig-pool-persist /var/openvpn/ipp.txt\n'
  printf 'tls-auth /etc/openvpn/private/TA.key\n'
  printf 'replay-persist /var/openvpn/replay-persist-file\n'
  printf 'max-clients 30\n'
  printf 'status /var/log/openvpn/openvpn-status.log\n'
  printf 'log-append /var/log/openvpn/openvpn.log\n'
  printf 'proto udp\n'
  printf 'port 1194\n'
  printf 'management 127.0.0.1 1100\n'
  printf 'daemon openvpn\n'
  printf 'chroot /var/openvpn/chrootjail\n'
  #printf 'crl-verify /etc/openvpn/certs/CA.crl\n'
  printf 'float\n'
  printf 'persist-key\n'
  printf 'persist-tun\n'
  printf 'keepalive 10 120\n'
  printf 'comp-lzo\n'
  printf 'user _openvpn\n'
  printf 'group _openvpn\n'
  printf 'verb 4\n'
  printf 'mute 6\n'

  printf 'dev tun0\n'
  printf 'client-config-dir  /etc/openvpn/ccd\n'

  printf 'tls-server\n'
  printf 'topology subnet\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn/server.conf

{
  printf 'ifconfig-push 172.16.52.66 255.255.255.224\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn/ccd/tgw.sv2.bbxn.us

{
  printf 'ca /etc/openvpn/certs/CA.pem\n'
  printf 'cert /etc/openvpn/certs/openvpn-client.crt\n'
  printf 'key /etc/openvpn/private/openvpn-client.key\n'
  printf 'tls-auth /etc/openvpn/private/TA.key\n'
  printf 'status /var/log/openvpn/openvpn-client-status.log\n'
  printf 'log-append /var/log/openvpn/openvpn-client.log\n'
  printf 'proto udp\n'
  printf 'nobind\n'
  printf 'resolv-retry infinite\n'
  printf 'daemon openvpn\n'
  printf 'chroot /var/openvpn/chrootjail\n'
  printf 'persist-key\n'
  printf 'persist-tun\n'
  printf 'comp-lzo\n'
  printf 'user _openvpn\n'
  printf 'group _openvpn\n'
  printf 'verb 4\n'
  printf 'mute 6\n'
  printf 'mute-replay-warnings\n'

  printf 'dev tun1\n'
  printf 'client\n'

  printf 'tls-client\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn/client.conf

{
  printf '#!/bin/sh\n'
  printf 'exec > /root/post.log ; exec 2>&1\n'
  printf 'site=$(hostname | sed '"-e 's/[^\.]*\.//' | sed -e 's/\..*//'"')\n'

  printf 'for f in /etc/hostname.*.$site ; do\n'
  printf ' basefile=$(echo $f | sed -e "s/\.$site//")\n'
  printf ' mv $f $basefile\n'
  printf 'done\n'

  printf 'mv -f /etc/bgpd.conf.$site /etc/bgpd.conf\n'

  printf 'rm /etc/hostname.*.*\n'
  printf 'rm /etc/bgpd.conf.*\n'

  printf 'rcctl enable bgpd\n'

  printf 'if [ $site == "sv1" ] ; then\n'
  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_pln\n'
  printf 'rcctl enable dhcrelay_pln\nrcctl set dhcrelay_pln flags "-i vio2 172.16.16.72 172.16.32.72"\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_wext\n'
  printf 'rcctl enable dhcrelay_wext\nrcctl set dhcrelay_wext flags "-i vio3 172.16.16.72 172.16.32.72"\n'
  printf 'printf "server 172.16.52.64 255.255.255.224\n" >> /var/openvpn/chrootjail/etc/openvpn/server.conf\n'
  printf 'fi\n'

  printf 'if [ $site == "sv2" ] ; then\n'
  printf 'printf "server 172.16.52.96 255.255.255.224\n" >> /var/openvpn/chrootjail/etc/openvpn/server.conf\n'
  printf 'printf "remote 172.16.52.1 1194\n" >> /var/openvpn/chrootjail/etc/openvpn/client.conf\n'
  printf 'fi\n'

  printf 'pkg_add openvpn\n'
  printf 'pkg_add apg\n'

  printf 'install -m 700 -d /etc/openvpn/private-client-conf\n'
  printf 'install -m 755 -d /var/log/openvpn\n'

  printf 'install -m 755 -d /var/openvpn/chrootjail/etc/openvpn\n'
  printf 'install -m 700 -d /var/openvpn/chrootjail/etc/openvpn/private\n'
  printf 'install -m 755 -d /var/openvpn/chrootjail/etc/openvpn/ccd\n'
  printf 'install -m 755 -d /var/openvpn/chrootjail/tmp\n'
  printf 'install -m 755 -d /var/openvpn/chrootjail/var/openvpn\n'

  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/crl.pem /etc/openvpn/crl.pem\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/server.conf /etc/openvpn/server.conf\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/client.conf /etc/openvpn/client.conf\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/ccd/ /etc/openvpn/\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/certs /etc/openvpn\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/private /etc/openvpn\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/replay-persist-file /etc/openvpn/replay-persist-file\n'

  printf 'openssl dhparam -out /var/openvpn/chrootjail/etc/openvpn/dh.pem 2048\n'
  printf 'chmod 0644 /var/openvpn/chrootjail/etc/openvpn/dh.pem\n'
  printf 'ln -s /var/openvpn/chrootjail/etc/openvpn/dh.pem /etc/openvpn\n'
  printf 'touch /var/openvpn/chrootjail/etc/openvpn/private/mgmt.pwd\n'
  printf 'chmod 0640 /var/openvpn/chrootjail/etc/openvpn/private/mgmt.pwd\n'
  printf '/usr/local/bin/apg -M SNCL -m 21 -n 1 > /var/openvpn/chrootjail/etc/openvpn/private/mgmt.pwd\n'
  printf 'ln -s tgw.$site.crt /var/openvpn/chrootjail/etc/openvpn/certs/openvpn.crt\n'
  printf 'ln -s tgw.$site-client.crt /var/openvpn/chrootjail/etc/openvpn/certs/openvpn-client.crt\n'

  printf 'touch /var/openvpn/chrootjail/etc/openvpn/private/openvpn.key\n'
  printf 'touch /var/openvpn/chrootjail/etc/openvpn/private/openvpn-client.key\n'
  printf 'chmod 0640 /var/openvpn/chrootjail/etc/openvpn/private/openvpn.key\n'
  printf 'chmod 0640 /var/openvpn/chrootjail/etc/openvpn/private/openvpn-private.key\n'
  printf 'mount /dev/cd0c /mnt && cat /mnt/openvpn-TA.key > /var/openvpn/chrootjail/etc/openvpn/private/TA.key\n'
  printf 'cat /mnt/openvpn.key > /var/openvpn/chrootjail/etc/openvpn/private/openvpn.key || true\n'
  printf 'cat /mnt/openvpn-client.key > /var/openvpn/chrootjail/etc/openvpn/private/openvpn-client.key || true\n'

  printf 'syspatch\n'

} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/install.site
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/install.site

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn/certs
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/var/openvpn/chrootjail/etc/openvpn/certs
  host_certs=$(curl "${cert_idx}" | awk '{print $9}')
  hc_dir=${cert_idx%/index.txt}
  for x in ${host_certs} ; do
    if [ "${x}" == "index.txt" ] ; then continue ; fi
    curl -LO "${hc_dir}/${x}"
  done
  cp /mnt/sysimage/usr/share/nginx/html/pub/BBXN_INT_SV1.pem CA.pem
popd

{
  printf '#!/bin/sh\n'
  printf ':\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/rc.firsttime
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/rc.firsttime

{
  printf 'set skip on lo\n\n'

  printf 'block drop quick inet6 proto icmp6 all icmp6-type { routeradv, routersol }\n'
  printf 'block return log\n\n'

  printf 'pass out on vmm proto udp from port 68 to port 67\n\n'
  printf 'antispoof quick for { pln wext vmm }\n\n'
  printf 'pass in on vmm proto tcp from (vmm:network) to (vmm) port 22\n'

  printf 'pass in on { pln wext } proto udp from port 68 to port 67\n'
  printf 'pass out proto udp from port 67 to {172.16.16.72, 172.16.32.72} port 67\n'
  printf 'pass out proto tcp from (transit) to {172.16.16.72, 172.16.32.72} port 80\n'
  printf 'pass on { transit tun0 tun1 tun2 } proto tcp from {(transit:network),(tun0:network),(tun1:network),(tun2:network)}'
  printf ' to {(transit:network),(tun0:network),(tun1:network),(tun2:network)} port 179\n'
  printf 'pass on { pln wext } proto udp from {(pln:network),(wext:network)} to {(pln:network),(wext:network)} port 1194\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/pf.conf

{
  printf 'net.inet.ip.forwarding=1\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/sysctl.conf

install -m 0700 -d /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/root/.ssh
install -m 0600 /mnt/sysimage/root/.ssh/authorized_keys /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/root/.ssh/authorized_keys

{
  printf '#!/bin/sh\n'
  printf 'site=$(hostname | sed '"-e 's/[^\.]*\.//' | sed -e 's/\..*//'"')\n'
  printf '[ -e /var/openvpn/chrootjail/etc/openvpn/certs/tgw.$site.crt ] && /usr/local/sbin/openvpn --config /etc/openvpn/server.conf\n'
  printf 'if [ -e /var/openvpn/chrootjail/etc/openvpn/certs/tgw.$site-client.crt ] ; then\n'
  printf '  [ -e /var/openvpn/chrootjail/etc/openvpn/client.conf ]  && /usr/local/sbin/openvpn --config /etc/openvpn/client.conf\n'
  printf '  [ -e /var/openvpn/chrootjail/etc/openvpn/client2.conf ] && /usr/local/sbin/openvpn --config /etc/openvpn/client2.conf\n'
  printf 'fi\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/rc.local
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/rc.local

tar cpzf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/site${ob_ver_nd}-tgw.tgz -C /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw .

# efw - which is really sv1 only
mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw/etc

# vio0 - transit
printf 'inet 172.16.16.10 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw/etc/hostname.vio0
# vio1 - vmm
printf 'dhcp\n-inet6\ngroup vmm\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw/etc/hostname.vio1
# vio2 - egress
printf 'dhcp\n-inet6\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio2

{
  printf 'AS 4233244401\nrouter-id 172.16.16.0\nnexthop qualify via bgp\nlisten on 172.16.16.10\n'
  printf 'deny from any prefix 10.0.0.0/8 prefixlen >= 8\ndeny from any prefix 192.168.0.0/16 prefixlen >=16\n'
  printf 'neighbor 172.16.16.11 {\n descr "tgw.sv1"\n remote-as 4233244401\n ttl-security yes\n announce default-route\n}\n'
  printf 'neighbor 172.16.16.1  {\n descr "ifw.sv1"\n remote-as 4233244401\n ttl-security yes\n announce default-route\n}\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw/etc/bgpd.conf

{
  printf 'set skip on lo\n\n'

  printf 'anchor "ftp-proxy/*"\nanchor "tftp-proxy/*"\n'
  printf 'pass in on { transit } inet proto tcp to port ftp flags S/SA modulate state divert-to 127.0.0.1 port 8021\n\n'

  printf 'block drop quick inet6 proto icmp6 all icmp6-type { routeradv, routersol }\n'
  printf 'block return log\n\n'

  printf 'pass out on vmm proto udp from port 68 to port 67\n'
  printf 'antispoof quick for { vmm }\n\n'
  printf 'pass in on vmm proto tcp from (vmm:network) to (vmm) port 22\n'

  printf 'pass on { transit } proto tcp from (transit:network) to (transit:network) port 179\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw/etc/pf.conf

tar cpzf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/site${ob_ver_nd}-efw.tgz -C /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/efw .

# wire a pxe autochain
mkdir -p /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac
printf '#!ipxe\nchain tftp://${next-server}/ipxe.d/openbsd\n' > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac/52-54-00-44-c9-2e.ipxe
printf '#!ipxe\nchain tftp://${next-server}/ipxe.d/openbsd\n' > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac/52-54-00-4e-cc-0f.ipxe
printf '#!ipxe\nchain tftp://${next-server}/ipxe.d/openbsd\n' > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac/52-54-00-cc-ef-04.ipxe
printf '#!ipxe\nchain tftp://${next-server}/ipxe.d/openbsd\n' > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac/52-54-00-44-c7-2e.ipxe
printf '#!ipxe\nchain tftp://${next-server}/ipxe.d/openbsd\n' > /mnt/sysimage/var/lib/tftpboot/vh-${tftp_std}/ipxe.d/mac/52-54-00-3e-ee-84.ipxe

# regenerate OpenBSD index
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64
rm index.txt
ls -ln > index.txt
popd

# hack around pkg_add weirdness
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}
ln -s . ${ob_ver}
popd

# create openbsd install.conf
{
  printf 'Terminal type? = screen\n'
  printf 'System hostname = openbsd-ai\n'
  printf 'IPv4 address for = dhcp\n'
  printf 'Default IPv4 route = none\n'
  printf 'Password for root = packer\n'
  printf 'Public ssh key for root account = %s\n' "$(head -n1 /mnt/sysimage/root/.ssh/authorized_keys)"
  printf 'Start sshd(8) by default = yes\n'
  printf 'Allow root ssh = without-password\n'
  printf 'Do you expect to run the X Window System = no\n'
  printf 'Change the default console to com0 = yes\n'
  printf 'Which speed should com0 use = 115200\n'
  printf 'What timezone are you in = UTC\n'
  printf 'Setup a user = no\n'
  printf 'Use DUIDs rather than device names in fstab = yes\n'
  printf 'Use (W)hole disk or (E)dit the MBR? = W\n'
  printf 'Use (A)uto layout, (E)dit auto layout, or create (C)ustom layout? = a\n'
  printf 'Which disk do you wish to initialize = done\n'
  printf 'Location of sets = http\n'
  printf 'HTTP proxy URL = none\n'
  printf 'HTTP Server = %s\n' "${tftp_std}"
  printf 'Unable to connect using https. Use http instead = yes\n'
  printf 'Set name(s) = -comp* -man* -game* -x* done\n'
  printf 'Checksum test for site%s.tgz = yes\n' "${ob_ver_nd}"
  printf 'Checksum test for site%s-HOSTNAME.tgz = yes\n' "${ob_ver_nd}"
  printf 'Unverified sets: site%s.tgz. Continue without verification = yes\n' "${ob_ver_nd}"
  printf 'Unverified sets: site%s-HOSTNAME.tgz. Continue without verification = yes\n' "${ob_ver_nd}"
} > /mnt/sysimage/usr/share/nginx/html/install.conf
sed -e 's/openbsd-ai/ifw/' -e 's/HOSTNAME/ifw/g' < /mnt/sysimage/usr/share/nginx/html/install.conf > /mnt/sysimage/usr/share/nginx/html/ifw.sv2.bbxn.us-install.conf
sed -e 's/openbsd-ai/ifw/' -e 's/HOSTNAME/ifw/g' < /mnt/sysimage/usr/share/nginx/html/install.conf > /mnt/sysimage/usr/share/nginx/html/ifw.sv1.bbxn.us-install.conf


sed -e 's/openbsd-ai/tgw/' -e 's/HOSTNAME/tgw/g' < /mnt/sysimage/usr/share/nginx/html/install.conf > /mnt/sysimage/usr/share/nginx/html/tgw.sv1.bbxn.us-install.conf
cp /mnt/sysimage/usr/share/nginx/html/tgw.sv1.bbxn.us-install.conf "/mnt/sysimage/usr/share/nginx/html/52:54:00:cc:ef:04-install.conf"
printf 'DNS domain = sv1.bbxn.us\n' >> "/mnt/sysimage/usr/share/nginx/html/52:54:00:cc:ef:04-install.conf"

sed -e 's/openbsd-ai/tgw/' -e 's/HOSTNAME/tgw/g' < /mnt/sysimage/usr/share/nginx/html/install.conf > /mnt/sysimage/usr/share/nginx/html/tgw.sv2.bbxn.us-install.conf
cp /mnt/sysimage/usr/share/nginx/html/tgw.sv2.bbxn.us-install.conf "/mnt/sysimage/usr/share/nginx/html/52:54:00:3e:ee:84-install.conf"
printf 'DNS domain = sv2.bbxn.us\n' >> "/mnt/sysimage/usr/share/nginx/html/52:54:00:3e:ee:84-install.conf"


sed -e 's/openbsd-ai/efw/' -e 's/HOSTNAME/efw/g' < /mnt/sysimage/usr/share/nginx/html/install.conf > /mnt/sysimage/usr/share/nginx/html/efw.bbxn.us-install.conf

%end
