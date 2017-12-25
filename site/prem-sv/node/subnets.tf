locals {
  netmgmt    = "${cidrsubnet(var.supernet,var.site-bits,0)}"
  hypervisor = "${cidrsubnet(var.supernet,var.site-bits,1)}"
  restricted = "${cidrsubnet(var.supernet,var.site-bits,2)}"
  server     = "${cidrsubnet(var.supernet,var.site-bits,3)}"
  dmz        = "${cidrsubnet(var.supernet,var.site-bits,4)}"
  user       = "${cidrsubnet(var.supernet,var.site-bits,5)}"
  guest      = "${cidrsubnet(var.supernet,var.site-bits,6)}"
}
