locals {
  wext-1-range = "${map("wifiext",cidrsubnet(local.block-local,2,1))}"
  pln-1-range  = "${map("powerline",cidrsubnet(local.block-local,2,0))}"
}
