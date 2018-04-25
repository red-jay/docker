locals {
  vlan-kv = "${merge(module.vlans-sv1.vlans, module.vlans-sv1a.vlans, module.vlans-sv2.vlans, module.vlans-pa.vlans)}"
  vlan-keys = "${keys(local.vlan-kv)}"
}
