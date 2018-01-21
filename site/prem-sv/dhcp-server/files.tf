locals {
  range-keys = "${keys(var.ranges)}"
  host-keys  = "${keys(var.host-map)}"
  classes    = "${formatlist("class \"%s\" { match hardware; }",local.range-keys)}"
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

data "template_file" "tftp_systemd_requires" {
  template = "${file("${path.module}/tftpd.systemd.template")}"

  vars {
    tftp = "${cidrhost(var.addr,0)}"
    com1 = "${cidrhost(var.addr,1)}"
    com2 = "${cidrhost(var.addr,2)}"
  }
}


data "template_file" "networkd_config" {
  template = "${file("${path.module}/eth0.network.template")}"

  vars {
    tftp     = "${cidrhost(var.addr,0)}"
    com1     = "${cidrhost(var.addr,1)}"
    com2     = "${cidrhost(var.addr,2)}"
    cidrmask = "${element(split("/",lookup(var.ranges,"netmgmt")),1)}"
  }
}

data "template_file" "tftp_vh_init" {
  template = "${file("${path.module}/tftp-vh.sh.template")}"

  vars {
    tftp     = "${cidrhost(var.addr,0)}"
    com1     = "${cidrhost(var.addr,1)}"
    com2     = "${cidrhost(var.addr,2)}"
  }
}

data "archive_file" "config_layer" {
  type = "zip"
  output_path = "tf-output/${var.fqdn}.zip"

  source {
    filename = "etc/systemd/network/eth0.network"
    content  = "${data.template_file.networkd_config.rendered}"
  }

  source {
    filename = "etc/systemd/system/tftpd-vhosts.service"
    content  = "${data.template_file.tftp_systemd_requires.rendered}"
  }

  source {
    filename = "etc/dhcp/hwaddr-access.conf"
    content  = "${join("\n",data.template_file.host_mapping.*.rendered)}"
  }

  source {
    filename = "etc/dhcp/bootfile.conf"
    content  = "${file("${path.module}/dhcp-bootfile.conf")}"
  }

  source {
    filename = "etc/dhcp/ipxe-option-space.conf"
    content  = "${file("${path.module}/ipxe-option-space.conf")}"
  }

  source {
    filename = "etc/dhcp/dhcpd.conf"
    content  = "${data.template_file.dhcpd_conf.rendered}"
  }

  source {
    filename = "usr/local/sbin/tftp-vhosts.sh"
    content  = "${data.template_file.tftp_vh_init.rendered}"
  }
}
