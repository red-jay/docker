module "vlans-pa" {
  source = "vltable"
  series = "pa"
  user-vlan = "500"
  restricted-vlan = "521"
  guest-vlan = "531"
}
