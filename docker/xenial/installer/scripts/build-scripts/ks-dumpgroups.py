#!/usr/bin/python

import sys
from pykickstart.parser import *
from pykickstart.version import makeVersion
ksparser = KickstartParser(makeVersion('RHEL7'),followIncludes=False)
ksparser.readKickstart(sys.argv[1])
ksgroups = ksparser.handler.packages.groupList
ksgroupnames = [group.name for group in ksgroups]
for n in ksgroupnames:
  print n
