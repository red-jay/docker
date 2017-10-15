#!/bin/bash

set -eu

set -o pipefail

cd /var/cache/apt/archives

for pkg in xen-system-amd64 libvirt-bin debootstrap virtinst libguestfs-tools systemd-sysv pinentry-tty rrdtool nut lm-sensors tmux vlan dnsmasq firewalld dhcpcd5 virtinst vncsnapshot tshark apparmor irqbalance ; do
  # the very ugly grep filter removes virtual packages
  # we want word splitting in the below line
  # shellcheck disable=SC2046
  apt-get -q download $(apt-rdepends "${pkg}" | grep -v "^ " | grep -vE 'debconf-2.0|file-rc|perlapi-*|linux-initramfs-tool|awk|cron-daemon|sysvinit|pinentry')
done

# clean duplicate packages - adapted from
# https://askubuntu.com/questions/96580/how-to-clean-var-cache-apt-in-a-way-that-it-leaves-only-the-latest-versions-of-e

# removal list
declare -a rml
# doing this allows us to easily increment on the size of rml, we test later so it becomes a noop
rml[0]="_DUMMY_"

# configure nullglob so we don't get "*.deb" type answers
shopt -s nullglob

# walk the archive
for package in *.deb ; do
  # strip out everything after the first _
  name=${package%%_*}

  # find here dumps a zero-delim list of files, which we sort by time, then get the last item.
  lf=$(find . -iname "${name}"'_*.deb' -printf '%T@ %p\0' | sort -z | tail -z -n1)

  # get how many files we found now
  files=''
  findct=0
  files=("${name}"_*.deb)
  findct=${#files[@]}

  # if more than one item loop over the files to delete dupes
  if [ "${findct}" -gt 1 ] ; then
    for candidate in ${name}_*.deb ; do

      # compare each potential file against the latest file record
      case "${lf}" in
        *${candidate})
          : # noop
          ;;
        *)
          # duplicate to be cleaned - the ${#rml[@]} being size of rml, so self increments
          rml[${#rml[@]}]="${candidate}"
          ;;
      esac

    done # candidate in ${name}*.deb

  fi     # findct > 1
done     # package in *.deb

# remove packages _after_ we're done iterating
for file in "${rml[@]}" ; do
  # we may have already removed it, so check existence
  if [ -f "${file}" ] ; then
    rm -v "${file}"
  fi
done
