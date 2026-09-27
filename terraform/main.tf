data "hcloud_server_type" "node" {
  name = var.node_server_type
}

data "hcloud_image" "node" {
  name              = var.node_image
  with_architecture = data.hcloud_server_type.node.architecture
}

resource "tailscale_tailnet_key" "node" {
  count = var.node_count

  reusable            = true
  ephemeral           = true
  preauthorized       = true
  recreate_if_invalid = "always"
  tags                = [var.tailscale_tag]
}

resource "hcloud_ssh_key" "node_access" {
  name       = "k8s-lab-ssh-key"
  public_key = trimspace(var.ssh_public_key)
}

resource "hcloud_firewall" "lab" {
  name = "k8s-lab-firewall"

  rule {
    direction = "in"
    port      = "41641"
    protocol  = "udp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_network" "lab" {
  name     = "k8s-lab"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "lab" {
  network_id   = hcloud_network.lab.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

module "nodes" {
  source = "./modules/node"
  count  = var.node_count

  name                = "${var.node_name_prefix}-${count.index + 1}"
  server_type         = data.hcloud_server_type.node.name
  image               = tostring(data.hcloud_image.node.id)
  location            = var.node_location
  public_ipv4_enabled = var.public_ipv4_enabled
  ssh_key_id          = hcloud_ssh_key.node_access.id
  firewall_ids        = [hcloud_firewall.lab.id]
  network_id          = hcloud_network.lab.id
  tailscale_auth_key  = tailscale_tailnet_key.node[count.index].key
}
