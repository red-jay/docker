FROM redjays/xenial:bootable
MAINTAINER RJ <rbergero@gmail.com>
RUN env LC_ALL=C DEBIAN_FRONTENV=noninteractive add-apt-repository ppa:notarrjay/stretch-xen-on-xenial && apt-get update && apt-get clean all

RUN dpkg-divert --rename /usr/sbin/update-grub && ln -s /bin/true /usr/sbin/update-grub && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y install xen-system-amd64 && \
    rm /usr/sbin/update-grub && dpkg-divert --rename --remove /usr/sbin/update-grub && \
    ln -s 20_linux_xen /etc/grub.d/09_linux_xen

RUN env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y libvirt-clients libvirt-daemon-system firewalld dnsmasq dhcpcd5 virtinst vncsnapshot

ADD /systemd-network /etc/systemd/network

RUN mkdir -p /run/firewalld && \
    /usr/bin/firewall-offline-cmd --new-zone vmm && \
    /usr/bin/firewall-offline-cmd --zone vmm --add-interface vmm && \
    /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 0 --logical-in vmm -j DROP && \
    /usr/bin/firewall-offline-cmd --direct --add-rule eb filter FORWARD 1 --logical-out vmm -j DROP && \
    /usr/bin/firewall-offline-cmd --zone vmm --add-service dhcp && \
    /usr/bin/firewall-offline-cmd --zone vmm --add-service ntp && \
    /usr/bin/firewall-offline-cmd --zone vmm --add-service http && \
    /usr/bin/firewall-offline-cmd --zone vmm --add-port 3493/tcp && \
    rm -rf /run/firewalld

ADD dnsmasq.conf /etc/dnsmasq.conf

ADD resolvconf-interface-order /etc/resolvconf/interface-order

RUN ln -sf /lib/systemd/system/dnsmasq.service /etc/systemd/system/multi-user.target.wants/dnsmasq.service && \
    mkdir -p /etc/systemd/system/dnsmasq.service.d

ADD /systemd-system-dnsmasq.service.d /etc/systemd/system/dnsmasq.service.d

ADD /modprobe.d /etc/modprobe.d

ADD /sysctl.d /etc/sysctl.d

ADD /udev-rules.d /etc/udev/rules.d

ADD /scripts /scripts
