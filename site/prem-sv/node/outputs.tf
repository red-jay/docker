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
                  "iot",local.iot,
                )}"
}

output "vlans" {
  # NOTE: this is used to plumb hypervisors, so we need to clamp names to 15c (IFNAMSIZ)
  value = "${map(
                  "4","netm",
                  "5","srv",
                  "66","xsit",
                  "6","hv",
                  "303","dmz",
                  "400","pln",
                  "4000","external",
                  var.wext-vlan,"s${var.series}.wext",
                  var.user-vlan,"s${var.series}.user",
                  var.restricted-vlan,"s${var.series}.res",
                  var.guest-vlan,"s${var.series}.gst",
                  var.iot-vlan,"s${var.series}.iot",
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
