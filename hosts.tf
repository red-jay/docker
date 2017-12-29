locals {
  host-mac-net-mapping = "${map(
    "lr-kallax-sw", "${map("class","netmgmt","hwaddr","a021.b7af.2abd")}"
  )}"
}
