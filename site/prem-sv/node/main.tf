# generate random mac address for your ifw
resource "random_id" "ifw_hwaddr" {
  byte_length = 3
  prefix      = "5e267e"
}
