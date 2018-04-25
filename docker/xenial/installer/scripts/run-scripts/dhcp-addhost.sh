#!/usr/bin/bash
if [ "$#" -lt 2 ]; then echo "group mac [name]" 1>&2 ; exit 1; fi
cls="${1}" ; mac="${2}"
printf '"'"'subclass "%%s" 1:%%s; subclass "%%s" %%s;\\n'"'"' "${cls}" "${mac}" "${cls}" "${mac}" >> /etc/dhcp/dhcpd.conf
if [ "$#" -eq 3 ] ; then
 hst="${3}"
 printf '"'"'host %%s { hardware ethernet %%s; option host-name "%%s"; }\\n'"'"' "${hst}" "${mac}" "${hst}" >> /etc/dhcp/dhcpd.conf
fi
