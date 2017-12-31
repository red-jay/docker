variable "site-bits" {
  default = 2
}

locals {
  block-node-1 = "${cidrsubnet(var.supernet,var.site-bits,1)}"
  block-node-2 = "${cidrsubnet(var.supernet,var.site-bits,2)}"

  # block 3
  block-node-1a = "${cidrsubnet(var.supernet,(var.site-bits + 2),((var.site-bits * 2) * 3))}"
  block-local   = "${cidrsubnet(var.supernet,(var.site-bits + 4),(((var.site-bits * 8) * 3)) + 4 )}"
  block-vpn     = "${cidrsubnet(var.supernet,(var.site-bits + 4),(((var.site-bits * 8) * 3)) + 5 )}"
}
