output "hostname" {
  description = "Hostname assigned to the node."
  value       = hcloud_server.this.name
}

output "id" {
  description = "Hetzner Cloud server ID of the node."
  value       = hcloud_server.this.id
}
