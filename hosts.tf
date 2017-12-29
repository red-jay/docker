locals {
  host-mac-net-mapping = "${map(
    "lr-kallax-sw", "${map("class","netmgmt",   "hwaddr","${lookup(var.kallax_hwid,"ether")}")}",
    "nickel-hw",    "${map("class","hypervisor","hwaddr","${lookup(var.nickel_hwid,"ether")}")}",
    "nickel",       "${map("class","hypervisor","hwaddr",random_id.nickel_mac.hex)}",
  )}"
}

resource "random_id" "nickel_mac" {
  keepers = {
    sysmac = "${lookup(var.nickel_hwid,"ether")}"
  }
  byte_length = 3
  prefix = "5e267e"
}
