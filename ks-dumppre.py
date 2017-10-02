#!/usr/bin/python

from pykickstart.parser import *
from pykickstart.sections import *
from pykickstart.version import makeVersion
ksparser = KickstartParser(makeVersion('RHEL7'),followIncludes=False)
ksparser.readKickstart("ks.cfg")
ksscripts = ksparser.handler.scripts
for n in ksscripts:
  if n.type == KS_SCRIPT_PRE:
    print n
