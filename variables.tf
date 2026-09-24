variable "ssh_public_key" {
  description = "Complete OpenSSH public key that Terraform uploads to the Hetzner Cloud project for node access."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(ssh-|ecdsa-|sk-)[^[:space:]]+[[:space:]]+[^[:space:]]+", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a complete OpenSSH public key, including its key type and encoded key data."
  }
}

variable "node_count" {
  description = "Number of lab nodes to create. Destroy the lab instead of setting this to zero."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a whole number between 1 and 10."
  }
}

variable "node_server_type" {
  description = "Hetzner Cloud server type used for every lab node."
  type        = string
  default     = "cx23"
  nullable    = false

  validation {
    condition     = length(trimspace(var.node_server_type)) > 0
    error_message = "node_server_type must not be empty."
  }
}

variable "node_image" {
  description = "Name of the Hetzner Cloud system image to resolve for the selected server architecture."
  type        = string
  default     = "ubuntu-24.04"
  nullable    = false

  validation {
    condition     = length(trimspace(var.node_image)) > 0
    error_message = "node_image must not be empty."
  }
}

variable "node_location" {
  description = "Hetzner Cloud location in which all lab nodes are created."
  type        = string
  default     = "nbg1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.node_location))
    error_message = "node_location must be a non-empty Hetzner Cloud location name such as nbg1."
  }
}

variable "node_name_prefix" {
  description = "RFC 1123 hostname prefix used to form node names such as k8s-lab-node-1."
  type        = string
  default     = "k8s-lab-node"
  nullable    = false

  validation {
    condition = (
      length(var.node_name_prefix) <= 59 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.node_name_prefix))
    )
    error_message = "node_name_prefix must be at most 59 characters and contain only lowercase letters, digits, and internal hyphens."
  }
}

variable "tailscale_tag" {
  description = "Tailscale ACL tag assigned to the ephemeral authentication keys created for lab nodes."
  type        = string
  default     = "tag:k8s-node"
  nullable    = false

  validation {
    condition     = can(regex("^tag:[A-Za-z0-9-]+$", var.tailscale_tag))
    error_message = "tailscale_tag must use the tag:<name> form."
  }
}

variable "public_ipv4_enabled" {
  description = "Whether each lab node receives a public IPv4 address in addition to its public IPv6 address."
  type        = bool
  default     = true
  nullable    = false
}


variable "manage_known_hosts" {
  description = "Whether a known_hosts_file should be generated automatically"
  type = bool
  default = false
  nullable = false
}