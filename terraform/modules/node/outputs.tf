output "hostname" {
  description = "Hostname assigned to the node."
  value       = hcloud_server.this.name
}

output "id" {
  description = "Hetzner Cloud server ID of the node."
  value       = hcloud_server.this.id
}

output "private_ip" {
  description = "IPv4 address assigned to the node's Hetzner private network interface."
  value       = hcloud_server_network.private.ip
}
