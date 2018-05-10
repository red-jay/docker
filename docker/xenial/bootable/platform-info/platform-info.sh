#!/usr/bin/env bash

pi_dir=/run/platform-info

for f in /sys/class/dmi/id/board_vendor /sys/class/dmi/id/chassis_vendor ; do
  words=''
  if [ -f "${f}" ] ; then
    b="${f##*/}"
    worddir="${pi_dir}/${b}_words"
    mkdir -p "${worddir}"
    read -r words < "${f}"
    for word in ${words} ; do
      case "${word}" in
        "."|".."|"/"|"\\"|"\n") : ;;
        *) touch "${worddir}/${word,,}" ;;
      esac
    done
  fi
done
