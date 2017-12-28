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

# dhcp servers
module "dhcp-1" {
  source         = "./dhcp-server"
  addr           = "${local.tftp-1-subrange}"
  fqdn           = "dhcp-1.${var.domainname}"
  netmgmt-ranges = "${local.netmgmt-ranges}"
}

module "dhcp-2" {
  source         = "./dhcp-server"
  addr           = "${local.tftp-2-subrange}"
  fqdn           = "dhcp-2.${var.domainname}"
  netmgmt-ranges = "${local.netmgmt-ranges}"
}

module "dhcp-1a" {
  source         = "./dhcp-server"
  addr           = "${local.tftp-1a-subrange}"
  fqdn           = "dhcp-1a.${var.domainname}"
  netmgmt-ranges = "${local.netmgmt-ranges}"
}
