#!/bin/bash

# create an ubuntu usb stick to install our Xen hv configuration

set -eux

set -o pipefail

# https://help.ubuntu.com/community/LiveCDCustomizationFromScratch
IMGDIR=$(mktemp -d /var/tmp/hvdisk-XXXXXX)
UBU_ARCHIVE=http://wcs.bbxn.us/ubuntu

set +u
if [ ! -z "${1}" ] ; then
  UBU_ARCHIVE="${1}"
fi
set -u

# create a chroot
sudo debootstrap --verbose --arch=amd64 --keyring=./ubuntu-archive-keyring.gpg xenial "${IMGDIR}" "${UBU_ARCHIVE}"

# mount filesystems
sudo mount --bind /dev  "${IMGDIR}/dev"
sudo mount --bind /proc "${IMGDIR}/proc"
sudo mount --bind /sys  "${IMGDIR}/sys"

# update sources.list
{
  printf 'deb %s xenial main universe\n' "${UBU_ARCHIVE}"
  printf 'deb %s/ xenial-security main universe\n' "${UBU_ARCHIVE}"
  printf 'deb %s/ xenial-updates main universe\n' "${UBU_ARCHIVE}"
} | sudo tee "${IMGDIR}/etc/apt/sources.list" > /dev/null

# fetch packagelists
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -qq -y update

# install debsums
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTENT=noninteractive apt-get -q install -y debsums

# update system
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y upgrade

# install packages for livefs
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y ubuntu-standard casper lupin-casper
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y discover laptop-detect os-prober
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y linux-generic
printf 'GRUB_DISABLE_OS_PROBER=true\n' sudo tee -a "${IMGDIR}/etc/default/grub"
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y lvm2 thin-provisioning-tools cryptsetup mdadm debootstrap xfsprogs bcache-tools dkms syslinux extlinux isolinux memtest86+
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y smartmontools lm-sensors ethtool
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y openssh-server augeas-tools smartmontools fio
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y dbus

# patch live system login capability
sudo cp pam-login "${IMGDIR}/etc/pam.d/login"

# copy fio packages, install
if [ -d "fio-files" ] ; then
  fio_list=""
  for f in "fio-files/"*.deb ; do
    sudo cp "${f}" "${IMGDIR}/var/cache/apt/archives"
    fio_list="$(basename "${f}") ${fio_list}"
  done
  sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive sh -c "cd /var/cache/apt/archives && dpkg -i ${fio_list}"
  sudo chroot "${IMGDIR}" env LC_ALL=C sh -c 'chmod +x /var/lib/dkms/iomemory-vsl/*/*/*.sh'
  target_kver=("${IMGDIR}"/boot/vmlinuz-*-generic)
  target_kver=${target_kver#${IMGDIR}/boot/vmlinuz-}
  sudo chroot "${IMGDIR}" env LC_ALL=C dkms autoinstall -k "${target_kver}"
fi

# get packages to install next phase
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y apt-rdepends dpkg-dev
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
# shellcheck disable=SC2016
{
  printf "To bootstrap a new chroot from the /repository archive, run\n"
  printf '`/usr/sbin/debootstrap archive PATH`\n'
} | sudo tee "${IMGDIR}/etc/motd"

# copy over the fancy blockdev initscript
sudo cp ks-scripts/fs-layout.sh "${IMGDIR}/root/fs-layout.sh"
sudo cp blockdev-init.sh  "${IMGDIR}/root/blockdev-init.sh"
sudo cp simpledev-init.sh "${IMGDIR}/root/simpledev-init.sh"

# and the install-to-target scripts
sudo cp minsys-install.sh "${IMGDIR}/root/minsys-install.sh"
sudo cp luksdev-reformat.sh "${IMGDIR}/root/luksdev-reformat.sh"
sudo cp iomemory_md.sh "${IMGDIR}/root/iomemory_md.sh"
sudo cp xen-install.sh "${IMGDIR}/root/xen-install.sh"
sudo cp boot_pci_assign.sh "${IMGDIR}/root/boot_pci_assign.sh"
sudo cp pci-assign.sh "${IMGDIR}/root/pci-assign.sh"
sudo cp ks-scripts/install-stack.sh "${IMGDIR}/root/install-stack.sh"

# if we have the netmgmt iso, bring it along now.
if [ -f netmgmt.iso ] ; then
  sudo cp netmgmt.iso "${IMGDIR}/root/netmgmt-inst.iso"
fi

# if we have a ssh pubkey to induct, add it now.
if [ -f ssh.pub ] ; then
  sudo mkdir -p "${IMGDIR}/root/.ssh"
  sudo cp ssh.pub "${IMGDIR}/root/.ssh/authorized_keys"
  sudo chown -R root:root "${IMGDIR}/root/.ssh"
  sudo chmod 0700 "${IMGDIR}/root/.ssh"
  sudo chmod 0600 "${IMGDIR}/root/.ssh/authorized_keys"
fi

# unmount filesystems
sudo umount "${IMGDIR}/dev"
sudo umount "${IMGDIR}/proc"
sudo umount "${IMGDIR}/sys"

# move about isolinux files
sudo cp "${IMGDIR}/usr/lib/ISOLINUX/isolinux.bin" "${IMGDIR}/boot/isolinux.bin"
sudo mkdir -p "${IMGDIR}/boot/syslinux"
sudo cp "${IMGDIR}/usr/lib/syslinux/modules/bios/ldlinux.c32" "${IMGDIR}/boot/syslinux/ldlinux.c32"

# create syslinux/isolinux cfg
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

{
  printf 'LABEL memtest\n'
  printf ' KERNEL /boot/memtest86+.bin\n'
} | sudo tee -a "${IMGDIR}/syslinux.cfg" > /dev/null

# fstab entries for live env
{
  printf 'tmpfs\t/tmp\ttmpfs\tdefaults\t0 0\n'
  printf 'tmpfs\t/run\ttmpfs\tdefaults\t0 0\n'
} | sudo tee "${IMGDIR}/etc/fstab" > /dev/null

sudo mkdir -p "${IMGDIR}/mnt/sysimage"

# create tarball - sudo needs to create it, but we want the user to _own_ it ;)
# shellcheck disable=SC2024
sudo tar cp -C "${IMGDIR}" . > image.tar
# create iso
sudo mkisofs -b boot/isolinux.bin -c boot/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -joliet-long -v -T -V HVINABOX "${IMGDIR}" > image.iso

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
mkfs ext2 /dev/sda1
set-e2label /dev/sda1 HVINABOX
mount /dev/sda1 /
tar-in image.tar /
command "extlinux -i /"
umount /dev/sda1
upload /usr/share/syslinux/mbr.bin /dev/sda
_EOF_
