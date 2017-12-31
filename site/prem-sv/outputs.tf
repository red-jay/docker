output "cidr-supernet-vpn" {
  value = "${local.block-vpn}"
}

output "cidr-supernet-local" {
  value = "${local.block-local}"
}

output "nodes" {
  value = "${var.nodes}"
}

output "node_named_networks" {
  value = "${map(
                  "node-1",module.node-1.networks,
                  "node-2",module.node-2.networks,
                  "node-1a",module.node-1a.networks
                )}"
}
