# vpc modules - subnets and addressing
module "prem-sv" {
  source     = "site/prem-sv"
  supernet   = "${lookup(var.supernet,"prem-sv")}"
  domainname = "bbxn.us"
}
