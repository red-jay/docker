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

output "restricted-nets" {
  value = "${local.restricted_keys}"
}
