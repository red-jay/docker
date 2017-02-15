#!/bin/bash

glist=${1}

for g in $(cat ${glist}) ; do
  repoquery -g -l ${g} --grouppkgs=all -qf '%{NAME}\n' > repodata/group-${g}.txt
done
