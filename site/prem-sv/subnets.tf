locals {
  netmgmt-ranges = "${list(lookup(module.node-1.networks,"netmgmt"), lookup(module.node-1a.networks,"netmgmt"), lookup(module.node-2.networks,"netmgmt"))}"
}
