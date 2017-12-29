# sv1 is split into three nodes...
variable "nodes" {
  default = ["node-1", "node-2", "node-1a"]
}

module "node-1" {
  source   = "./node"
  supernet = "${local.block-node-1}"
}

module "node-1a" {
  source   = "./node"
  supernet = "${local.block-node-1a}"
}

module "node-2" {
  source   = "./node"
  supernet = "${local.block-node-2}"
}

locals {
  # dhcp-1 also gets wifiext, powerline networks
  dhcp-1-range = "${merge(module.node-1.networks, local.wext-1-range, local.pln-1-range)}"
}

# dhcp(/tftp) servers
module "dhcp-1" {
  source = "./dhcp-server"
  addr   = "${local.tftp-1-subrange}"
  fqdn   = "dhcp-1.${var.domainname}"
  ranges = "${local.dhcp-1-range}"
}

module "dhcp-2" {
  source = "./dhcp-server"
  addr   = "${local.tftp-2-subrange}"
  fqdn   = "dhcp-2.${var.domainname}"
  ranges = "${module.node-2.networks}"
}

module "dhcp-1a" {
  source = "./dhcp-server"
  addr   = "${local.tftp-1a-subrange}"
  fqdn   = "dhcp-1a.${var.domainname}"
  ranges = "${module.node-1a.networks}"
}
