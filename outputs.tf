resource "terraform_data" "known_hosts" {

  for_each = var.manage_known_hosts ? {
    for node in module.nodes :
    node.hostname => node
  } :  {}

  triggers_replace = [
    each.value.id
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/update-known-host.sh ${each.value.hostname}"
  }
}