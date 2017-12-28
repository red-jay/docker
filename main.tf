# vpc modules - subnets and addressing
module "prem-sv" {
  source     = "site/prem-sv"
  supernet   = "${lookup(var.supernet,"prem-sv")}"
  domainname = "bbxn.us"
}

#module "dhcp-sv1" {
#  source = "dhcp-server/prem"
#  addr   = "${module.prem-sv.cidr-subnet-netmgmt-sv1}"
#}

