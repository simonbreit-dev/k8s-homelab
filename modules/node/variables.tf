variable "name" {
  type = string
}
variable "server_type" {
  type = string
}
variable "image" {
  type = string
}

variable "tailscale_auth_key" {
  type = string
  sensitive = true
}
variable "firewall_ids" {
  type = list(number)
}
variable "network_id" {
  type = number
}