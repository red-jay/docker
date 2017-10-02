#!/usr/bin/python

import sys
import pprint
pp = pprint.PrettyPrinter(indent=4)

from pykickstart.parser import *
from pykickstart.version import makeVersion
ksparser = KickstartParser(makeVersion('RHEL7'),followIncludes=False)
ksparser.readKickstart(sys.argv[1])
kspkgs = ksparser.handler.packages.packageList
for n in kspkgs:
  print n
