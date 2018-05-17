#!/usr/bin/env bash

set -eux

for f in dockerfiles/*/* ; do
  dist=${f#dockerfiles/}
  version=${f##*/}
  dist=${dist%/${version}}
  docker build -f "$f" -t "mods/$dist:$version" .
done
