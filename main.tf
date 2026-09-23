terraform {
  required_version = "1.16.4"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
  cloud {
  }
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
}

provider "tailscale" {
  tailnet = "-"
  scopes  = ["auth_keys"]
}

resource "tailscale_tailnet_key" "node" {
  count =  var.node_count
  reusable      = false
  ephemeral     = true
  preauthorized = true
  expiry        = 3600
  tags = [
    "tag:k8s-node"
  ]
}

resource "hcloud_firewall" "k8s-lab-firewall" {
    name = "k8s-lab-firewall"
    rule {
      direction = "in"
      port = "41641"
      protocol = "udp"
      source_ips = [
        "0.0.0.0/0",
        "::/0"
      ]
    }
}

resource "hcloud_network" "k8s" {
  name     = "k8s-lab"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k8s" {
  network_id   = hcloud_network.k8s.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

module "nodes" {
  count = var.node_count

  source = "./modules/node"

  name        = "k8s-lab-node-${count.index + 1}"
  server_type = var.node_server_type
  image       = var.node_image

  firewall_ids = [hcloud_firewall.k8s-lab-firewall.id]
  network_id = hcloud_network.k8s.id
  tailscale_auth_key = tailscale_tailnet_key.node[count.index].key
}