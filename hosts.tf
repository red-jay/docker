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

data "template_file" "macmapper_data" {
  template = "$${source}) echo $${dest} ;;"
  count    = "${length(local.mac-keys)}"

  vars {
    dest   = "${replace(lookup(local.mac-remapping,element(local.mac-keys,count.index)),"/[.:]/","")}"
    source = "${replace(element(local.mac-keys,count.index),"/[.:]/","")}"
  }
}

data "template_file" "macmapper" {
  template = "${file("${path.module}/macmapper.sh.tpl")}"

  vars {
    macdata = "${join("\n",data.template_file.macmapper_data.*.rendered)}"
  }
}

resource "local_file" "macmapper" {
  filename = "tf-output/common/intmac-remap.sh"
  content  = "${data.template_file.macmapper.rendered}"
}

data "template_file" "mac2bridge_pln_data" {
  template = "$${source} "
  count    = "${length(var.pln_maddrs)}"

  vars {
    bridge = "pln"
    source = "${replace(element(var.pln_maddrs,count.index),"/[.:]/","")}"
  }
}

data "template_file" "bridger" {
  template = "pln='$${pln_macdata}'"

  vars {
    pln_macdata = " ${join("",data.template_file.mac2bridge_pln_data.*.rendered)}"
  }
}

resource "local_file" "bridger" {
  filename = "tf-output/common/intmac-bridge.sh"
  content  = "${data.template_file.bridger.rendered}"
}
