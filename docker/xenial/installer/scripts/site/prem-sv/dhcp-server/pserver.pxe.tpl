#!ipxe
isset $${comport}   || set pserver ${tftp} ||
iseq  $${comport} 1 && set pserver ${com1} ||
iseq  $${comport} 2 && set pserver ${com2} ||
