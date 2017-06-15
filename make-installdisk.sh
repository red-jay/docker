#!/bin/bash

# create an ubuntu usb stick to install our Xen hv configuration

set -eux

set -o pipefail

# https://help.ubuntu.com/community/LiveCDCustomizationFromScratch
IMGDIR=$(mktemp -d /var/tmp/hvdisk-XXXXXX)

# create a chroot
sudo debootstrap --verbose --arch=amd64 --keyring=./ubuntu-archive-keyring.gpg xenial "${IMGDIR}"

# mount filesystems
sudo mount --bind /dev  "${IMGDIR}/dev"
sudo mount --bind /proc "${IMGDIR}/proc"
sudo mount --bind /sys  "${IMGDIR}/sys"

# update sources.list
{
  printf 'deb http://archive.ubuntu.com/ubuntu xenial main universe\n'
  printf 'deb http://us.archive.ubuntu.com/ubuntu/ xenial-security main universe\n'
  printf 'deb http://us.archive.ubuntu.com/ubuntu/ xenial-updates main universe\n'
} | sudo tee "${IMGDIR}/etc/apt/sources.list" > /dev/null

# fetch packagelists
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -y update

# install debsums
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTENT=noninteractive apt-get install -y debsums

# update system
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

# install packages for livefs
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-standard casper lupin-casper
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y discover laptop-detect os-prober
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y linux-generic
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y lvm2 thin-provisioning-tools cryptsetup mdadm debootstrap xfsprogs bcache-tools dkms
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server

# patch live system login capability
sudo cp pam-login "${IMGDIR}/etc/pam.d/login"

# copy fio packages, install
if [ -d "fio-files" ] ; then
  fio_list=""
  for f in "fio-files/"*.dev ; do
    sudo cp "${f}" "${IMGDIR}/var/cache/apt/archives"
    fio_list="$(basename ${f}) ${fio_list}"
  done
  sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTENT=noninteractive sh -c "cd /var/cache/apt/archives && dpkg -i ${fio_list}"
fi

# get packages to install next phase
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y apt-rdepends dpkg-dev
sudo chroot "${IMGDIR}" env LC_ALL=C chown _apt /var/cache/apt/archives
sudo cp dl-pkgs.sh "${IMGDIR}/root"
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive bash /root/dl-pkgs.sh
sudo rm "${IMGDIR}/root/dl-pkgs.sh"

# create package pool
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C mkdir -p '/repository/dists/archive/main/binary-amd64'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /var/cache/apt/archives && mv *.deb /repository/dists/archive/main/binary-amd64'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /repository && apt-ftparchive packages dists/archive/main/binary-amd64 > dists/archive/main/binary-amd64/Packages'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /repository/dists/archive && apt-ftparchive -o APT::FTPArchive::Release::Components="main" release .  > Release'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C find /repository -type d -exec chmod a+rx {} \;
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C find /repository -type f -exec chmod a+r {} \;

# hack debootstrap
sudo cp debootstrap-archive "${IMGDIR}/usr/share/debootstrap/scripts/archive"

# write some notes
{
  printf "To bootstrap a new chroot from the /repository archive, run\n"
  printf '`/usr/sbin/debootstrap archive PATH`\n'
} | sudo tee "${IMGDIR}/etc/motd"

# unmount filesystems
sudo umount "${IMGDIR}/dev"
sudo umount "${IMGDIR}/proc"
sudo umount "${IMGDIR}/sys"

# create syslinux cfg
printf 'serial 0 115200\n\n' | sudo tee "${IMGDIR}/syslinux.cfg" > /dev/null
default=""
for initrd in ${IMGDIR}/boot/initrd.img* ; do
  ver=$(basename "${initrd}" -generic)
  ver=${ver#initrd.img-}
  if [ -z "${default}" ] ; then
    default="${ver}"
    printf 'DEFAULT %s\n\n' "${ver}" | sudo tee -a "${IMGDIR}/syslinux.cfg" > /dev/null
  fi
  {
    printf 'LABEL %s\n' "${ver}"
    printf ' KERNEL /boot/vmlinuz-%s-generic\n' "${ver}"
    printf ' INITRD /boot/initrd.img-%s-generic\n' "${ver}"
    printf ' APPEND console=ttyS0,115200 root=LABEL=%s rw\n' "HVINABOX"
  } | sudo tee -a "${IMGDIR}/syslinux.cfg" > /dev/null
done

# create tarball
sudo tar cp -C "${IMGDIR}" . > image.tar

# clean out IMGDIR
sudo rm -rf "${IMGDIR}"

# create backing store
truncate -s3G image.img

# guestfish to assemble bootable instance
guestfish -a image.img << _EOF_
run
part-init /dev/sda mbr
part-add /dev/sda p 63 -1
part-set-bootable /dev/sda 1 true
mkfs ext2 /dev/sda1 label:HVINABOX
mount /dev/sda1 /
extlinux /
tar-in image.tar /
umount /dev/sda1
upload /usr/share/syslinux/mbr.bin /dev/sda
_EOF_
