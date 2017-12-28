locals {
  range-keys = "${keys(var.ranges)}"
}

data "template_file" "subnet" {
  template = "${file("${path.module}/dhcpd-subnet.template")}"
  count    = "${length(local.range-keys)}"

  vars {
    range       = "${lookup(var.ranges,element(local.range-keys,count.index))}"
    class       = "${element(local.range-keys,count.index)}"
    next-server = "${cidrhost(var.addr,0)}"
  }
}

data "template_file" "dhcpd_conf" {
  template = "${file("${path.module}/dhcpd.conf.template")}"

  vars {
    classes = ""
    netmgmt = "${join("\n",data.template_file.subnet.*.rendered)}"
  }
}

resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcpd.conf"
  content  = "${data.template_file.dhcpd_conf.rendered}"
}
