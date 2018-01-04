locals {
  host-mac-net-mapping = "${map(
    "lr-kallax-sw", "${map("class","netmgmt",   "hwaddr","${lookup(var.kallax_hwid,"ether")}")}",
    "nickel-hw",    "${map("class","hypervisor","hwaddr","${lookup(var.nickel_hwid,"ether")}")}",
    "nickel",       "${map("class","hypervisor","hwaddr",random_id.nickel_mac.hex)}",
    "radon-hw",     "${map("class","hypervisor","hwaddr","${lookup(var.radon_hwid,"ether")}")}",
    "radon",        "${map("class","hypervisor","hwaddr",random_id.radon_mac.hex)}",
  )}"

  mac-remapping = "${map(
    lookup(var.radon_hwid,"ether"),random_id.radon_mac.hex,
  )}"

  mac-keys = "${keys(local.mac-remapping)}"
}

resource "random_id" "nickel_mac" {
  keepers = {
    sysmac = "${lookup(var.nickel_hwid,"ether")}"
  }

  byte_length = 3
  prefix      = "${var.mac-prefix}"
}

resource "random_id" "radon_mac" {
  keepers = {
    sysmac = "${lookup(var.radon_hwid,"ether")}"
  }

  byte_length = 3
  prefix      = "${var.mac-prefix}"
}

data "template_file" "macmapper" {
  template = "mac[$${source}]=$${dest}"
  count    = "${length(local.mac-keys)}"

  vars {
    dest   = "${replace(lookup(local.mac-remapping,element(local.mac-keys,count.index)),"/[.:]/","")}"
    source = "${replace(element(local.mac-keys,count.index),"/[.:]/","")}"
  }
}

resource "local_file" "macmapper" {
  filename = "tf-output/common/intmac-remap.sh"
  content  = "${join("\n",data.template_file.macmapper.*.rendered)}"
}
