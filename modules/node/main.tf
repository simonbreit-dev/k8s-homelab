resource "hcloud_server" "this" {
  name        = var.name
  server_type = var.server_type
  image       = var.image
  ssh_keys = [ var.ssh_key_id ]
  firewall_ids = var.firewall_ids
  network {
    network_id = var.network_id
  }
  public_net {
    ipv4_enabled = false
    ipv6_enabled = true
}
  user_data = templatefile(
    "${path.module}/templates/cloud-init.yml",
    {
      hostname           = var.name
      tailscale_auth_key = var.tailscale_auth_key
    }
  )
}