# sv1 is split into three nodes...
module "node-1" {
  source = "./node"
  supernet = "${local.block-node-1}"
}

module "node-1a" {
  source = "./node"
  supernet = "${local.block-node-1a}"
}

module "node-2" {
  source = "./node"
  supernet = "${local.block-node-2}"
}
