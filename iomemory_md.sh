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
      md_args=${x#iomemory_md=}
      md_name=${md_args#:*}
      md_dev=${md_args%${md_name}:}
      md_dev=$(echo "${md_dev}" | sed 's/,/ /g' )
      # shellcheck disable=SC2086
      mdadm --assemble "/dev/md/${md_name}" ${md_dev}
    ;;
  esac
done
