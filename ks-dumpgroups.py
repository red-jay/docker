#!/usr/bin/python

from pykickstart.parser import *
from pykickstart.version import makeVersion
ksparser = KickstartParser(makeVersion('RHEL7'))
ksparser.readKickstart("ks.cfg")
ksgroups = ksparser.handler.packages.groupList
ksgroupnames = [group.name for group in ksgroups]
for n in ksgroupnames:
  print n
