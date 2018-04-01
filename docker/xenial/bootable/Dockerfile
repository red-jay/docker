FROM redjays/xenial:latest
MAINTAINER RJ <rbergero@gmail.com>
RUN env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y ubuntu-standard casper lupin-casper discover laptop-detect os-prober linux-generic lvm2 thin-provisioning-tools cryptsetup mdadm xfsprogs bcache-tools dkms syslinux extlinux isolinux memtest86+ nwipe smartmontools lm-sensors ethtool openssh-server augeas-tools smartmontools fio dbus && apt-get -q -y clean all
