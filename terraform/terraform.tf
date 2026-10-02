terraform {
  required_version = "1.16.4"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.69.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}
