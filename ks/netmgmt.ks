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

dhcp
memtest86+
tftp-server
nginx

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

# functions
partition_all_drives() {
  # partition drives
  for d in /dev/[sv]d*[^0-9] /dev/xvd*[^0-9] ; do
    if [ "${d}" == "${repodisk}" ] ; then continue ; fi
    parted "${d}" mklabel gpt
    parted "${d}" mkpart biosboot 1m 5m
    parted "${d}" toggle 1 bios_grub
    parted "${d}" toggle 1 legacy_boot
    biosboot_dev="${biosboot_dev} ${d}1"

    parted "${d}" mkpart '"EFI System Partition"' 5m 300m
    parted "${d}" toggle 2 boot
    efi_sp_dev="${efi_sp_dev} ${d}2"

    parted "${d}" mkpart boot 300m 800m
    boot_dev="${boot_dev} ${d}3"

    parted "${d}" mkpart primart 800m 100%
    sys_dev="${sys_dev} ${d}4"
  done

}

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

# get whatever diskdev we're running on
repodisk=$(awk '$2 == "/run/install/repo" { print $1 }' < /proc/mounts)
repodisk=${repodisk%[1-9]*}

# always stop lvm
vgchange -an

# always stop md devices
for md in /dev/md[0-9]* ; do
  mdadm -S "${md}"
done

# always erase disks, write a new gpt
for d in /dev/[sv]d*[^0-9] /dev/xvd*[^0-9] ; do
  # skip where we booted
  if [ "${d}" == "${repodisk}" ] ; then continue ; fi

  # partitions...
  for part in ${d}[0-9]* ; do
    wipefs -a "${part}"
  done

  # label
  wipefs -a "${d}"
done

# this holds any needed conditional package statements
touch /tmp/package-include

# disk setup globals
biosboot_dev=''
efi_sp_dev=''
boot_dev=''
sys_dev=''

  partition_all_drives

  {
    for part in ${biosboot_dev} ; do
      p=$(basename "${part}")
      printf 'part biosboot --fstype=biosboot --onpart=%s\n' "${p}"
    done
    for part in ${efi_sp_dev} ; do
      p=$(basename "${part}")
      printf 'part /boot/efi --fstype="efi" --onpart=%s\n' "${p}"
    done
    for part in ${boot_dev} ; do
      p=$(basename "${part}")
      printf 'part /boot --fstype="ext2" --onpart=%s\n' "${p}"
    done
    for part in ${sys_dev} ; do
      p=$(basename "${part}")
      printf 'part pv.0 --fstype="lvmpv" --onpart=%s\n' "${p}"
    done
    # LVM
    printf 'volgroup centos_system pv.0\n'
    printf 'logvol / --vgname=centos_system --fstype=ext4 --name=root --size=8192\n'
    printf 'logvol swap --vgname=centos_system --name=swap --size=512\n'

    printf 'bootloader --append=" net.ifnames=0 biosdevname=0 crashkernel auto" --location=mbr\n'
  } > /tmp/part-include

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
    dhcp_subnet "${subnet}" "powerline" "${nextserver}"
  done

  # wext
  for subnet in ${dhcp_wext} ; do
    dhcp_subnet "${subnet}" "wifiext" "${nextserver}"
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

  printf 'subclass "powerline" 1:52:54:00:22:CA:BE; subclass "powerline" 52:54:00:22:CA:BE;\n'

  # ufw
  # dfw

  # switches!
  printf 'subclass "netmgmt" 1:88:75:56:6a:d6:c1; subclass "netmgmt" 88:75:56:6a:d6:c1;\n'
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
  ipxe_tgz="${ks_method}/../ipxe-images.tgz"
elif [ -f /mnt/install/repo/ipxe-images.tgz ] ; then
  ipxe_tgz=file:///mnt/install/repo/ipxe-images.tgz
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
      curl --head --fail "${obsd_toplev}/${d}/amd64/bsd" 2>/dev/null 1>&2; echo $?
      rc=$?
      if [ $? -eq 0 ] ; then
        obsd_uri="${obsd_toplev}/${d}/amd64"
        ob_ver="${d///}"
      fi
    done
    ;;
esac

obsd_idx="${obsd_uri}/index.txt"
ob_ver_nd=${ob_ver//.}

mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64
pushd /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64
  curl -LO "${obsd_idx}"
  for f in $(awk '($9 && $9 != "index.txt") {print $9}' < index.txt) ; do
    curl -LO "${obsd_uri}/${f}"
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

# create openbsd site tree
mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc
# vio0 - netmgmt
printf 'inet 172.16.16.65 255.255.255.192\n-inet6\ngroup netmgmt\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio0.sv1
printf 'inet 172.16.32.65 255.255.255.192\n-inet6\ngroup netmgmt\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio0.sv2
# vio1 - vmm
printf 'dhcp\n-inet6\ngroup vmm\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio1
# vio2 - virthost
printf 'inet 172.16.16.129 255.255.255.192\n-inet6\ngroup virthost\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio2.sv1
printf 'inet 172.16.32.129 255.255.255.192\n-inet6\ngroup virthost\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio2.sv2
# vio3 - transit
printf 'inet 172.16.16.1 255.255.255.192\n-inet6\ngroup transit\n!route add -net 172.16.52.0/26 172.16.16.11\nup\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio3.sv1
printf 'inet 172.16.32.1 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/hostname.vio3.sv2

{
  printf '#!/bin/sh\n'
  printf 'site=$(hostname | sed '"-e 's/[^\.]*\.//' | sed -e 's/\..*//'"')\n'

  printf 'for f in /etc/hostname.*.$site ; do\n'
  printf ' basefile=$(echo $f | sed -e "s/\.$site//")\n'
  printf ' mv $f $basefile\n'
  printf 'done\n'

  printf 'rm /etc/hostname.*.*\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_virthosts\n'
  printf 'rcctl enable dhcrelay_virthosts\nrcctl set dhcrelay_virthosts flags "-i vio2 172.16.16.72 172.16.32.72"\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_transit\n'
  printf 'rcctl enable dhcrelay_transit\nrcctl set dhcrelay_transit flags "-i vio3 172.16.16.72 172.16.32.72"\n'

  printf 'rcctl enable tftpproxy\nrcctl set tftpproxy flags -v\n'
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

  printf 'pass in on { virthosts transit } proto udp from port 68 to port 67\n'
  printf 'pass in proto udp from port 67 to {172.16.16.72, 172.16.32.72} port 67\n'
  printf 'pass in quick on transit proto udp from (transit:network) to %s port 69 divert-to 127.0.0.1 port 6969\n' "{172.16.16.72/29, 172.16.32.72/29}"
  printf 'pass out quick on netmgmt proto udp to %s port 69 group _tftp_proxy divert-reply\n' "{172.16.16.72/29, 172.16.32.72/29}"

  printf 'pass proto tcp from (transit:network) to %s port 80\n' "{172.16.16.72, 172.16.32.72}"

} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/pf.conf

printf 'net.inet.ip.forwarding=1\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw/etc/sysctl.conf

tar cpzf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/site${ob_ver_nd}-ifw.tgz -C /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/ifw .

# tgw site
mkdir -p /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc
# vio0 - transit
printf 'inet 172.16.16.11 255.255.255.192\n-inet6\ngroup transit\n!route add -net 172.16.16.64/26 172.16.16.1\nup\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio0.sv1
printf 'inet 172.16.32.11 255.255.255.192\n-inet6\ngroup transit\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio0.sv2
# vio1 - vmm
printf 'dhcp\n-inet6\ngroup vmm\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio1
# vio2 - pln
printf 'inet 172.16.52.1 255.255.255.224\n-inet6\ngroup pln\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio2.sv1
printf 'dhcp\n-inet6\ngroup pln\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio2.sv2
# vio3 - wext
printf 'inet 172.16.52.32 255.255.255.224\n-inet6\ngroup wext\n' > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/hostname.vio3.sv1

{
  printf '#!/bin/sh\n'
  printf 'site=$(hostname | sed '"-e 's/[^\.]*\.//' | sed -e 's/\..*//'"')\n'

  printf 'for f in /etc/hostname.*.$site ; do\n'
  printf ' basefile=$(echo $f | sed -e "s/\.$site//")\n'
  printf ' mv $f $basefile\n'
  printf 'done\n'

  printf 'rm /etc/hostname.*.*\n'

  printf 'if [ $site == "sv1" ] ; then\n'
  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_pln\n'
  printf 'rcctl enable dhcrelay_pln\nrcctl set dhcrelay_pln flags "-i vio2 172.16.16.72 172.16.32.72"\n'

  printf 'cp /etc/rc.d/dhcrelay /etc/rc.d/dhcrelay_wext\n'
  printf 'rcctl enable dhcrelay_wext\nrcctl set dhcrelay_wext flags "-i vio3 172.16.16.72 172.16.32.72"\n'
  printf 'fi\n'

} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/install.site
chmod a+rx /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/install.site

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

  printf 'pass in on { pln wext } proto udp from port 68 to port 67\n'
  printf 'pass out proto udp from port 67 to {172.16.16.72, 172.16.32.72} port 67\n'
} > /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw/etc/pf.conf

tar cpzf /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD/${ob_ver}/amd64/site${ob_ver_nd}-tgw.tgz -C /mnt/sysimage/usr/share/nginx/html/pub/OpenBSD-site/tgw .

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
  printf 'Start sshd(8) by default = no\n'
  printf 'Do you expect to run the X Window System = no\n'
  printf 'Change the default console to com0 = yes\n'
  printf 'Which speed should com0 use = 115200\n'
  printf 'What timezone are you in = UTC\n'
  printf 'Setup a user = packer\n'
  printf 'Password for user = packer\n'
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
