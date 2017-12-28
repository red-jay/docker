data "template_file" "dhcpd_conf" {
  template = "${file("${path.module}/dhcpd.conf.template")}"
}

resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcpd.conf"
  content  = "${data.template_file.dhcpd_conf.rendered}"
}
