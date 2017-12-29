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
