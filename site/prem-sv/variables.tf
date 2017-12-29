# required from cidr
variable "supernet" {}

variable "domainname" {}

variable "host-map" {
  type    = "map"
  default = {}
}
