variable "user-vlan" {}

variable "restricted-vlan" {}

variable "guest-vlan" {}

variable "series" {}

variable "wext-vlan" {
  default = ""
}

variable "iot-vlan" {
  default = ""
}

locals {
  wext = "${var.wext-vlan != "" ? "${var.wext-vlan},${var.series}.wext" : ","}"
  wext-arr = "${split(",",local.wext)}"
  wext-map = "${map(local.wext-arr[0],local.wext-arr[1])}"

  iot = "${var.iot-vlan != "" ? "${var.iot-vlan},${var.series}.iot" : ","}"
  iot-arr = "${split(",",local.iot)}"
  iot-map = "${map(local.iot-arr[0],local.iot-arr[1])}"

  common-vl = "${map(
                  "4","netm",
                  "5","srv",
                  "66","xsit",
                  "6","hv",
                  "303","dmz",
                  "400","pln",
                  "4000","external",
                  var.user-vlan,"${var.series}.user",
                  var.restricted-vlan,"${var.series}.res",
                  var.guest-vlan,"${var.series}.gst",
               )}"
}

output "vlans" {
  # NOTE: this is used to plumb hypervisors, so we need to clamp names to 15c (IFNAMSIZ)
  value = "${merge(local.wext-map,local.iot-map,local.common-vl)}"
}
