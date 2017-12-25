output "cidr-subnet-netmgmt" {
  value = "${local.netmgmt}"
}

output "cidr-subnet-hypervisor" {
  value = "${local.hypervisor}"
}

output "cidr-subnet-restricted" {
  value = "${local.restricted}"
}

output "cidr-subnet-server" {
  value = "${local.server}"
}

output "cidr-subnet-dmz" {
  value = "${local.dmz}"
}

output "cidr-subnet-user" {
  value = "${local.user}"
}

output "cidr-subnet-guest" {
  value = "${local.guest}"
}
