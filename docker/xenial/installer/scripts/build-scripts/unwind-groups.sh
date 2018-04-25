#!/bin/bash

d=$(mktemp -d)

glist=${1}

for g in $(cat ${glist}) ; do
  repoquery -c ./yum.conf --releasever=7 -g -l ${g} --grouppkgs=all -qf '%{NAME}\n' > ${d}/group-${g}.txt
done

cat ${d}/group-*.txt
