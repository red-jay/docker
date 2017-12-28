# we turn lists into strings here, buddy
locals {
  netmgmt = "${join("\n",formatlist("%s",var.netmgmt-ranges))}"
}

data "template_file" "dhcpd_conf" {
  template = "${file("${path.module}/dhcpd.conf.template")}"

  vars {
    netmgmt = "${local.netmgmt}"
  }
}

resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcpd.conf"
  content  = "${data.template_file.dhcpd_conf.rendered}"
}
