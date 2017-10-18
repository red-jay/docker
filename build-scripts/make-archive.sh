#!/bin/bash

# create an ubuntu archive by creating an ubuntu chroot...

set -eux

set -o pipefail

UBU_REL="xenial"
SRCDIR=${BASH_SOURCE%/*}
echo "auxiliary scripts in ${SRCDIR}"
WORKDIR=$(pwd)
REPODIR="${WORKDIR}/archive/ubuntu/${UBU_REL}"
echo "running in ${WORKDIR}, using ${REPODIR} as destination repository directory"

# https://help.ubuntu.com/community/LiveCDCustomizationFromScratch
IMGDIR=$(mktemp -d /var/tmp/hvdisk-XXXXXX)
UBU_ARCHIVE=http://wcs.bbxn.us/ubuntu

set +u
if [ ! -z "${1}" ] ; then
  UBU_ARCHIVE="${1}"
fi
set -u

# create a chroot
sudo debootstrap --verbose --arch=amd64 --keyring=./ubuntu-archive-keyring.gpg "${UBU_REL}" "${IMGDIR}" "${UBU_ARCHIVE}"

# mount filesystems
mkdir -p          "${REPODIR}"
sudo mkdir -p                  "${IMGDIR}/repository"

sudo mount --bind /dev         "${IMGDIR}/dev"
sudo mount --bind /proc        "${IMGDIR}/proc"
sudo mount --bind /sys         "${IMGDIR}/sys"
sudo mount --bind "${REPODIR}" "${IMGDIR}/repository"

# update sources.list
{
  printf 'deb %s %s main universe\n' "${UBU_ARCHIVE}" "${UBU_REL}"
  printf 'deb %s/ %s-security main universe\n' "${UBU_ARCHIVE}" "${UBU_REL}"
  printf 'deb %s/ %s-updates main universe\n' "${UBU_ARCHIVE}" "${UBU_REL}"
} | sudo tee "${IMGDIR}/etc/apt/sources.list" > /dev/null

# copy archive in
shopt -s nullglob
debs=("${REPODIR}/dists/archive/main/binary-amd64/*.deb")
if (( ${#debs[@]} != 0 )) ; then
  sudo cp "${REPODIR}"/dists/archive/main/binary-amd64/*.deb "${IMGDIR}/var/cache/apt/archives"
fi

# fetch packagelists
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -qq -y update

# install debsums
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTENT=noninteractive apt-get -q install -y debsums

# update system
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y upgrade

# get packages
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y apt-rdepends dpkg-dev rsync
sudo chroot "${IMGDIR}" env LC_ALL=C chown _apt /var/cache/apt/archives
sudo cp "${SRCDIR}/dl-pkgs.sh" "${IMGDIR}/root"
sudo chroot "${IMGDIR}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive bash /root/dl-pkgs.sh
sudo rm "${IMGDIR}/root/dl-pkgs.sh"

# create package pool
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C mkdir -p '/repository/dists/archive/main/binary-amd64'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /var/cache/apt/archives && rsync -r --delete ./ /repository/dists/archive/main/binary-amd64/'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /repository && apt-ftparchive packages dists/archive/main/binary-amd64 > dists/archive/main/binary-amd64/Packages'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C sh -c 'cd /repository/dists/archive && apt-ftparchive -o APT::FTPArchive::Release::Components="main" release .  > Release'
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C find /repository -type d -exec chmod a+rx {} \;
sudo chroot "${IMGDIR}" env LANG=C LC_ALL=C find /repository -type f -exec chmod a+r {} \;

# unmount filesystems
sudo umount "${IMGDIR}/dev"
sudo umount "${IMGDIR}/proc"
sudo umount "${IMGDIR}/sys"
sudo umount "${IMGDIR}/repository"

# change owner on true repodir
sudo chown -R "$(id -u):$(id -g)" "${REPODIR}"

# destroy chroot
sudo rm -rf "${IMGDIR}"
