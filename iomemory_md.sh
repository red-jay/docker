#!/bin/sh

PREREQ="udev"
prereqs() {
  echo "$PREREQ"
}
case "${1}" in prereqs) prereqs ; exit 0 ;; esac

# shellcheck disable=SC2013
for x in $(cat /proc/cmdline) ; do
  case "${x}" in
    iomemory_md=*)
      md_args=$( echo "${x}" | sed 's/^iomemory_md=//' )
      md_name=$( echo "${md_args}" | sed 's/:.*//' )
      md_dev=$( echo "${md_args}" | sed "s/${md_name}://" )
      md_dev=$( echo "${md_dev}" | sed 's/,/ /g' )
      # shellcheck disable=SC2086
      mdadm --assemble "/dev/md/${md_name}" ${md_dev}
    ;;
  esac
done
