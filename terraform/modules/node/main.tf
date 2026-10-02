resource "hcloud_server" "this" {
  name         = var.name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [var.ssh_key_id]
  firewall_ids = var.firewall_ids
  network {
    subnet_id = var.subnet_id
    ip        = var.private_ip
    alias_ips = []
  }
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  user_data = templatefile(
    "${path.module}/templates/cloud-init.yml",
    {
      hostname           = var.name
      tailscale_auth_key = var.tailscale_auth_key
    }
  )

  shutdown_before_deletion = true
  provisioner "local-exec" {
    when       = destroy
    on_failure = continue

    command = <<-EOT
      ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${self.name} \
        'tailscale logout'
    EOT
  }
}
