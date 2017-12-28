resource "local_file" "dhcpd_conf" {
  filename = "tf-output/${var.fqdn}/etc/dhcpd.conf"
  content  = "a"
}
