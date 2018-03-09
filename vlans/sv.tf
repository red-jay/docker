module "vlans-sv1" {
  source = "vltable"
  series = "sv1"
  user-vlan = "10"
  restricted-vlan = "20"
  guest-vlan      = "30"
  wext-vlan       = "40"
  iot-vlan        = "50"
}

module "vlans-sv1a" {
  source = "vltable"
  series = "sv1a"
  user-vlan = "12"
  restricted-vlan = "22"
  guest-vlan      = "32"
  wext-vlan       = "42"
  iot-vlan        = "52"
}

module "vlans-sv2" {
  source = "vltable"
  series = "sv2"
  user-vlan = "11"
  restricted-vlan = "21"
  guest-vlan      = "31"
  wext-vlan       = "41"
  iot-vlan        = "51"
}
