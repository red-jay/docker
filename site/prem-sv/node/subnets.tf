locals {
  transit    = "${cidrsubnet(var.supernet,(var.site-bits + 1),0)}"
  netmgmt    = "${cidrsubnet(var.supernet,(var.site-bits + 1),1)}"
  hypervisor = "${cidrsubnet(var.supernet,(var.site-bits + 1),2)}"
  restricted = "${cidrsubnet(var.supernet,var.site-bits,2)}"
  server     = "${cidrsubnet(var.supernet,var.site-bits,3)}"
  dmz        = "${cidrsubnet(var.supernet,var.site-bits,4)}"
  user       = "${cidrsubnet(var.supernet,var.site-bits,5)}"
  guest      = "${cidrsubnet(var.supernet,var.site-bits,6)}"

  # list of restricted networks
  restricted_keys = "${list("transit","netmgmt","hypervisor","restricted","dmz")}"
}
