locals {
  hv_maddrs = "${keys(var.hv_systems)}"
  netm_maddrs = "${keys(var.netm_systems)}"
  pln_maddrs = "${keys(var.pln_systems)}"
}

data "template_file" "macmapper_data" {
  template = "$${source}) exit 0 ;;"
  count    = "${length(local.hv_maddrs)}"

  vars {
    source = "${replace(element(local.hv_maddrs,count.index),"/[.:]/","")}"
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
  count    = "${length(local.pln_maddrs)}"

  vars {
    bridge = "pln"
    source = "${replace(element(local.pln_maddrs,count.index),"/[.:]/","")}"
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
  count    = "${length(local.netm_maddrs)}"

  vars {
    bridge = "external"
    source = "${replace(element(local.netm_maddrs,count.index),"/[.:]/","")}"
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
