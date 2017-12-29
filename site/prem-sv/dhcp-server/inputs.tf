variable "addr" {}

variable "fqdn" {}

variable "ranges" {
  type    = "map"
  default = {}
}

variable "restricted_nets" {
  type    = "list"
  default = []
}
