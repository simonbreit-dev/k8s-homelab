resource "hcloud_server" "this" {
  name         = var.name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [var.ssh_key_id]
  firewall_ids = var.firewall_ids
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  user_data = templatefile(
    "${path.module}/templates/cloud-init.yml",
    {
      hostname                  = var.name
      tailscale_auth_key        = var.tailscale_auth_key
      tailscale_package_version = var.tailscale_package_version
      tailscale_signing_key     = file("${path.module}/templates/tailscale.asc")
    }
  )

  shutdown_before_deletion = true

  # Cloud-init only runs on first boot. Refreshing auth keys must not replace nodes.
  lifecycle {
    ignore_changes = [user_data]
  }
}

data "tailscale_device" "this" {
  hostname = hcloud_server.this.name
  wait_for = "600s"

  depends_on = [hcloud_server.this]
}

# Record the exact device before checking cloud-init so cleanup also works when
# initialization fails after Tailscale registration. Replacements delete the old
# device before deleting its server and reusing the hostname.
resource "terraform_data" "tailscale_device" {
  input = {
    hostname  = hcloud_server.this.name
    device_id = data.tailscale_device.this.node_id
  }
  triggers_replace = hcloud_server.this.id

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/../../../ansible"
    command     = "ansible-playbook -i localhost, -c local playbooks/delete-tailnet-device.yml -e 'tailscale_device_id=${self.input.device_id}'"
  }
}

# Hetzner starts servers before attaching inline networks. Keep attachment out
# of cloud-init's initial metadata lookup and wait for persistent DHCP setup.
resource "terraform_data" "cloud_init_ready" {
  input            = { hostname = hcloud_server.this.name }
  triggers_replace = hcloud_server.this.id
  depends_on       = [terraform_data.tailscale_device]

  provisioner "local-exec" {
    working_dir = "${path.module}/../../../ansible"
    command     = "ansible-playbook -i '${self.input.hostname},' playbooks/wait-for-cloud-init.yml"
  }
}

resource "hcloud_server_network" "private" {
  server_id = hcloud_server.this.id
  subnet_id = var.subnet_id
  ip        = var.private_ip
  alias_ips = []

  depends_on = [terraform_data.cloud_init_ready]
}
