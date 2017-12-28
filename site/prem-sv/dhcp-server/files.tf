data "template_file" "netmgmt_subnet" {
  template = "${file("${path.module}/dhcpd-subnet.template")}"
  count    = 3

  vars {
    netmgmt = "${element(var.netmgmt-ranges,count.index)}"
    class   = "netmgmt"
  }
}

data "template_file" "dhcpd_conf" {
  template = "${file("${path.module}/dhcpd.conf.template")}"

  vars {
  netmgmt = "${join("\n",data.template_file.netmgmt_subnet.*.rendered)}"
  }
}

resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcpd.conf"
  content  = "${data.template_file.dhcpd_conf.rendered}"
}
