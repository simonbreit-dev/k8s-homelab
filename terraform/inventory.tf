resource "local_file" "ansible_inventory" {
  filename             = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile(
    "${path.module}/templates/ansible_inventory.yml.tftpl",
    {
      control_planes = slice(
        module.nodes,
        0,
        var.control_plane_count
      )

      workers = slice(
        module.nodes,
        var.control_plane_count,
        length(module.nodes)
      )
    }
  )
}
