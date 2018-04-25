data "template_file" "bridge_mapping" {
  template = "$${br_name != "" ? "vlan[$${vlan_nr}]=$${br_name}" : "" }\n"
  count    = "${length(local.vlan-keys)}"

  vars {
    vlan_nr = "${element(local.vlan-keys,count.index)}"
    br_name = "${lookup(local.vlan-kv,element(local.vlan-keys,count.index))}"
  }
}

data "template_file" "hv_interface_config_script" {
  template = "${file("${path.module}/bridge-config.sh.tpl")}"

  vars {
    vlan_kvs = "${join("",data.template_file.bridge_mapping.*.rendered)}"
  }
}

resource "local_file" "bridge_mapping" {
  filename = "tf-output/common/hv-bridge-map.sh"
  content  = "${data.template_file.hv_interface_config_script.rendered}"
}
