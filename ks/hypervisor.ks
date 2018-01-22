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
-kernel
kernel-ml

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

# start writing KSPRE_ENV
printf '#!/usr/bin/env bash\nTARGETPATH=/mnt/sysimage\nexport TARGETPATH\n' > /tmp/KSPRE_ENV

# parts that can be _reset_ by system config but have a default
reboot_flag="reboot"
inst_fqdn="localhost.localdomain"

# first get if we have a syscfg on cmdline
read -r cmdline < /proc/cmdline
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

sourceuri=""
if [ ! -z "${ks_method}" ] ; then
  sourceuri="${ks_method}/../"
elif [ -f /mnt/install/repo/.discinfo ] ; then
  sourceuri="file:///mnt/install/repo/"
fi

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

{
  printf 'SOURCEURI="%s"\n' "${sourceuri}"
  printf 'export SOURCEURI\n'
  if [ ! -z "${site}" ] ; then
    printf 'SITE="%s"\n' "${site}"
    printf 'export SITE\n'
  fi
  if [ ! -z "${syscfg}" ] ; then
    printf 'SYSCFG="%s"\n' "${syscfg}"
    printf 'export SYSCFG\n'
  fi
  printf 'load_n_run () {\n'
  printf ' local realfile sourcefile\n'
  printf ' realfile="$(mktemp)"\n'
  printf ' sourcefile="${1}"\n'
  printf ' curl -L -o "${realfile}" "${SOURCEURI}${sourcefile}"\n'
  printf ' chmod +x "${realfile}"\n'
  printf ' "${realfile}" "${@:2}"\n'
  printf '}\n'
  printf 'get_file () {\n'
  printf ' local source dest\n'
  printf ' source="${1}" ; dest="${2}"\n'
  printf ' curl -L -o "${dest}" "${SOURCEURI}${source}"\n'
  printf '}\n'
} >> /tmp/KSPRE_ENV

. /tmp/KSPRE_ENV

# configure disks via magic script ;)
load_n_run ks-scripts/fs-layout.sh -W

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
. /tmp/KSPRE_ENV
. /tmp/post-vars

cp /tmp/KSPRE_ENV "${TARGETPATH}/tmp"
cp /tmp/fs-layout.env "${TARGETPATH}/tmp"

get_file ks-scripts/install-grub.sh /mnt/sysimage/tmp/install-grub.sh
chroot "${TARGETPATH}" /usr/bin/env bash /tmp/install-grub.sh

load_n_run ks-scripts/centos-common.sh

# pick up authorized_keys
if [ -f /run/install/repo/authorized_keys ] ; then
  mkdir -p /mnt/sysimage/root/.ssh
  cp /run/install/repo/authorized_keys /mnt/sysimage/root/.ssh
  chmod 0700 /mnt/sysimage/root/.ssh
  chmod 0600 /mnt/sysimage/root/.ssh/authorized_keys
  printf 'PermitRootLogin without-password\n' >> /mnt/sysimage/etc/ssh/sshd_config
fi

ln -s /usr/lib/systemd/system/nginx.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/nginx.service
printf 'location /bootstrap/openbsd {\n autoindex on;\n}\n' > /mnt/sysimage/etc/nginx/default.d/openbsd.conf

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

bash -x /run/install/repo/ks-scripts/install-stack.sh

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
  cp -R /run/install/repo/.treeinfo /mnt/sysimage/usr/share/nginx/html/bootstrap/centos7
  cp -R /run/install/repo/ks /mnt/sysimage/usr/share/nginx/html/bootstrap
  if [ -f /run/install/repo/authorized_keys ] ; then
    cp /run/install/repo/authorized_keys /mnt/sysimage/usr/share/nginx/html/bootstrap
  fi
  cp -R /run/install/repo/intca-pub /mnt/sysimage/usr/share/nginx/html/bootstrap
  cp -R /run/install/repo/certs /mnt/sysimage/usr/share/nginx/html/bootstrap
  cp -R /run/install/repo/bootstrap-scripts /mnt/sysimage/root
  cp -R /run/install/repo/ks-scripts /mnt/sysimage/usr/share/nginx/html/bootstrap/ks-scripts
  cp -R /run/install/repo/ipxe /mnt/sysimage/usr/share/nginx/html/bootstrap/ipxe
  cp -R /run/install/repo/openbsd /mnt/sysimage/usr/share/nginx/html/bootstrap/openbsd
  cp -R /run/install/repo/config-zips /mnt/sysimage/usr/share/nginx/html/bootstrap/config-zips
  find /mnt/sysimage/usr/share/nginx/html -type d -exec chmod a+rx {} \;
  find /mnt/sysimage/usr/share/nginx/html -type f -exec chmod a+r {} \;
fi

# copy private-isos to /var/lib/libvirt
if [ -d /run/install/repo/private-isos ] ; then
  mkdir -p /mnt/sysimage/var/lib/libvirt/images
  cp -R /run/install/repo/private-isos /mnt/sysimage/var/lib/libvirt/images/private
fi

%end
