variable "supernet" {
  type = "map"

  default = {
    aws-us-west-2 = "172.31.0.0/18"
    aws-us-east-2 = "172.31.64.0/18"
    prem-sv       = "172.16.0.0/18"
  }
}

variable "reserved-supernets" {
  type = "map"

  default = {
    virbr0 = "192.168.122.1"
    virbr1 = "192.168.123.1"
    chaos  = "10.100.252.0/24"
    vmm    = "192.168.128.128/25"
  }
}
