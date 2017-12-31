locals {
  dhcp-1-addr = "${cidrhost(lookup(module.node-1a.networks,"netmgmt"),1)}"

  # minimum /29...
  tftp-1-subrange  = "${cidrsubnet(lookup(module.node-1.networks,"netmgmt"),4,1)}"
  tftp-2-subrange  = "${cidrsubnet(lookup(module.node-2.networks,"netmgmt"),4,1)}"
  tftp-1a-subrange = "${cidrsubnet(lookup(module.node-1a.networks,"netmgmt"),4,1)}"
}
