locals {
  range-keys = "${keys(var.ranges)}"
  classes    = "${formatlist("class \"%s\" { match hardware };",local.range-keys)}"
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
    classes = "${join("\n",local.classes)}"
    netmgmt = "${join("\n",data.template_file.subnet.*.rendered)}"
  }
}

resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcp/dhcpd.conf"
  content  = "${data.template_file.dhcpd_conf.rendered}"
}

resource "local_file" "ipxe_option_space" {
  filename = "tf-output/${var.fqdn}/etc/dhcp/ipxe-option-space.conf"
  content  = "${file("${path.module}/ipxe-option-space.conf")}"
}

resource "local_file" "dhcpd_bootfile_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcp/bootfile.conf"
  content  = "${file("${path.module}/dhcp-bootfile.conf")}"
}
