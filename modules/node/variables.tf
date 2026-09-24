variable "name" {
  description = "RFC 1123 hostname to assign to the Hetzner Cloud server and cloud-init configuration."
  type        = string
}

variable "server_type" {
  description = "Hetzner Cloud server type name used to create the node."
  type        = string
}

variable "image" {
  description = "Exact Hetzner Cloud image ID used to create the node."
  type        = string
}

variable "location" {
  description = "Hetzner Cloud location in which to create the node."
  type        = string
}

variable "public_ipv4_enabled" {
  description = "Whether the node receives a public IPv4 address."
  type        = bool
}

variable "tailscale_auth_key" {
  description = "Single-use Tailscale authentication key consumed by cloud-init when the node first boots."
  type        = string
  sensitive   = true
}

variable "firewall_ids" {
  description = "Hetzner Cloud firewall IDs attached to the node."
  type        = list(number)
}

variable "network_id" {
  description = "Hetzner Cloud private network ID attached to the node."
  type        = number
}

variable "ssh_key_id" {
  description = "ID of the Terraform-managed Hetzner Cloud SSH key installed on the node."
  type        = string
}
