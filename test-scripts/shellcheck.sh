#!/bin/bash

find . -path ./archive -prune -o -type f -iname \*.sh -print0|xargs -0 shellcheck 
