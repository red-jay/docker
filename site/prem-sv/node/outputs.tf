output "networks" {
  value = "${map(
                  "netmgmt",local.netmgmt,
                  "hypervisor",local.hypervisor,
                  "restricted",local.restricted,
                  "server",local.server,
                  "dmz",local.dmz,
                  "user",local.user,
                  "guest",local.guest,
                  "transit",local.transit,
                )}"
}

output "vlans" {
  value = "${map(
                  "4","netmgmt",
                  "5","server",
                  "66","transit",
                  "6","hypervisor",
                  "303","dmz",
                  var.user-vlan,"user",
                  var.restricted-vlan,"restricted",
                  var.guest-vlan,"guest",
                )}"
}

output "restricted-nets" {
  value = "${local.restricted_keys}"
}

output "host-map" {
  value = "${map(
                 "ifw.sv1.${var.domainname}", "${map("class","netmgmt","hwaddr","${random_id.ifw_hwaddr.hex}")}"
                )}"
}
