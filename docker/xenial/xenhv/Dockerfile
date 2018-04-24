FROM redjays/xenial:bootable
MAINTAINER RJ <rbergero@gmail.com>
RUN env LC_ALL=C DEBIAN_FRONTENV=noninteractive add-apt-repository ppa:notarrjay/stretch-xen-on-xenial && apt-get update && apt-get clean all

RUN dpkg-divert --rename /usr/sbin/update-grub && ln -s /bin/true /usr/sbin/update-grub && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y install xen-system-amd64 && \
    rm /usr/sbin/update-grub && dpkg-divert --rename --remove /usr/sbin/update-grub

RUN env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y libvirt-clients libvirt-daemon-system firewalld dnsmasq dhcpcd5 virtinst vncsnapshot
