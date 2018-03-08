locals {
  mac-keys = "${concat(keys(var.hv_systems),keys(var.netm_systems),keys(var.pln_systems))}"
}

data "template_file" "macmapper_data" {
  template = "$${source}) exit 0 ;;"
  count    = "${length(keys(var.hv_systems))}"

  vars {
    source = "${replace(element(keys(var.hv_systems),count.index),"/[.:]/","")}"
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

data "template_file" "mac2bridge_external_data" {
  template = "$${source} "
  count    = "${length(var.external_maddrs)}"

  vars {
    bridge = "external"
    source = "${replace(element(var.external_maddrs,count.index),"/[.:]/","")}"
  }
}

data "template_file" "mac2bridge_netm_data" {
  template = "$${source} "
  count    = "${length(var.netm_maddrs)}"

  vars {
    bridge = "external"
    source = "${replace(element(var.netm_maddrs,count.index),"/[.:]/","")}"
  }
}

data "template_file" "bridger" {
  template = "pln='$${pln_macdata}'\nexternal='$${external_macdata}'\nnetm='$${netm_macdata}'\n"

  vars {
    pln_macdata      = " ${join("",data.template_file.mac2bridge_pln_data.*.rendered)}"
    external_macdata = " ${join("",data.template_file.mac2bridge_external_data.*.rendered)}"
    netm_macdata     = " ${join("",data.template_file.mac2bridge_netm_data.*.rendered)}"
  }
}

resource "local_file" "bridger" {
  filename = "tf-output/common/intmac-bridge.sh"
  content  = "${data.template_file.bridger.rendered}"
}
