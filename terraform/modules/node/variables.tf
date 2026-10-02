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

variable "private_ip" {
  type        = string
  description = "IPv4 address assigned to the node inside the Hetzner Cloud subnet."
}

variable "server_type" {
  type        = string
  description = "Hetzner Cloud server type name used to create the node."
}

variable "ssh_key_id" {
  type        = string
  description = "ID of the Terraform-managed Hetzner Cloud SSH key installed on the node."
}

variable "subnet_id" {
  type        = string
  description = "Hetzner Cloud subnet ID to which the node's private network interface is attached."
}

variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale authentication key consumed by cloud-init when the node first boots."
  sensitive   = true
}
