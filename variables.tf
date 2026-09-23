

variable "ssh_public_key" {
  type = string
}

variable "node_count" {
  type     = number
  nullable = false

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "serverCount must be a positive integer."
  }
}

variable "node_server_type" {
  type = string
}

variable "node_image" {
  type = string
}