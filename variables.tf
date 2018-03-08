variable "mac-prefix" {
  default = "5e267e"
}

variable "hv_systems" {
  type    = "map"
  default = {}
}

variable "netm_systems" {
  type    = "map"
  default = {}
}

variable "pln_systems" {
  type    = "map"
  default = {}
}

variable "external_maddrs" {
  type    = "list"
  default = []
}
