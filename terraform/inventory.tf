resource "local_file" "ansible_inventory" {
  filename             = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = yamlencode({
    all = {
      vars = {
        kubernetes_node_network   = hcloud_network_subnet.lab.ip_range
        tailscale_package_version = var.tailscale_package_version
      }
      children = {
        k8s_nodes = {
          children = {
            control_plane = {
              hosts = {
                for node in slice(module.nodes, 0, var.control_plane_count) :
                node.hostname => {
                  k8s_node_ip = node.private_ip
                }
              }
            }
            workers = {
              hosts = {
                for node in slice(module.nodes, var.control_plane_count, length(module.nodes)) :
                node.hostname => {
                  k8s_node_ip = node.private_ip
                }
              }
            }
          }
        }
      }
    }
  })
}
