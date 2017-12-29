locals {
  range-keys = "${keys(var.ranges)}"
  host-keys  = "${keys(var.host-map)}"
  classes    = "${formatlist("class \"%s\" { match hardware };",local.range-keys)}"
}

data "template_file" "subnet" {
  template = "${file("${path.module}/dhcpd-subnet.template")}"
  count    = "${length(local.range-keys)}"

  vars {
    range       = "${lookup(var.ranges,element(local.range-keys,count.index))}"
    class       = "${element(local.range-keys,count.index)}"
    allows      = "${contains(var.restricted_nets,element(local.range-keys,count.index)) ? "\n    allow members of \"${element(local.range-keys,count.index)}\";" : "" }"
    next-server = "${cidrhost(var.addr,0)}"
  }
}

data "template_file" "host_mapping" {
  template = "${file("${path.module}/dhcpd-classmap.template")}"
  count    = "${length(local.host-keys)}"

  vars {
    name  = "${element(local.host-keys,count.index)}"
    class = "${lookup(var.host-map[element(local.host-keys,count.index)],"class")}"
    m1    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),0,2)}"
    m2    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),2,2)}"
    m3    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),4,2)}"
    m4    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),6,2)}"
    m5    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),8,2)}"
    m6    = "${substr(replace(lookup(var.host-map[element(local.host-keys,count.index)],"hwaddr"),"/[.:]/",""),10,2)}"
  }
}

data "template_file" "dhcpd_conf" {
  template = "${file("${path.module}/dhcpd.conf.template")}"

  vars {
    classes = "${join("\n",local.classes)}"
    subnets = "${join("\n",data.template_file.subnet.*.rendered)}"
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

resource "local_file" "dhcpd_hostclass" {
  filename = "tf-output/${var.fqdn}/etc/dhcp/hwaddr-access.conf"
  content  = "${join("\n",data.template_file.host_mapping.*.rendered)}"
}
