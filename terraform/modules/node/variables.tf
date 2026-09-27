variable "firewall_ids" {
  type        = list(number)
  description = "Hetzner Cloud firewall IDs attached to the node."
}

variable "image" {
  type        = string
  description = "Exact Hetzner Cloud image ID used to create the node."
}

variable "location" {
  type        = string
  description = "Hetzner Cloud location in which to create the node."
}

variable "name" {
  type        = string
  description = "RFC 1123 hostname to assign to the Hetzner Cloud server and cloud-init configuration."
}

variable "network_id" {
  type        = number
  description = "Hetzner Cloud private network ID attached to the node."
}

variable "public_ipv4_enabled" {
  type        = bool
  description = "Whether the node receives a public IPv4 address."
}

variable "server_type" {
  type        = string
  description = "Hetzner Cloud server type name used to create the node."
}

variable "ssh_key_id" {
  type        = string
  description = "ID of the Terraform-managed Hetzner Cloud SSH key installed on the node."
}

variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale authentication key consumed by cloud-init when the node first boots."
  sensitive   = true
}
