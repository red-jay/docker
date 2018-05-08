#!/usr/bin/env bash

pi_dir=/run/platform-info

if [ -f /sys/class/dmi/id/board_vendor ] ; then
  bv_words="${pi_dir}/board_vendor_words"
  mkdir -p "${bv_words}"
  read -r board_vendor < /sys/class/dmi/id/board_vendor
  for word in ${board_vendor} ; do
    case "${word}" in
      "."|".."|"/"|"\\"|"\n") : ;;
      *) touch "${bv_words}/${word,,}" ;;
    esac
  done
fi
