mock_provider "hcloud" {
  mock_resource "hcloud_server" {
    defaults = { id = "1" }
  }
  mock_resource "hcloud_network" {
    defaults = { id = "1" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "1" }
  }
  mock_data "hcloud_server_type" {
    defaults = { architecture = "x86" }
  }
  mock_data "hcloud_image" {
    defaults = { architecture = "x86", os_flavor = "ubuntu", os_version = "24.04" }
  }
}
mock_provider "tailscale" {
  mock_data "tailscale_device" {
    defaults = { node_id = "nodeidTEST" }
  }
}
mock_provider "local" {}

variables {
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnly test@example"
}

run "inventory" {
  command = apply
  assert {
    condition = (
      local_file.ansible_inventory.filename == "${path.module}/../ansible/inventory/hosts.yml" &&
      local_file.ansible_inventory.file_permission == "0644" &&
      yamldecode(local_file.ansible_inventory.content).all.vars.kubernetes_node_network == "10.0.1.0/24" &&
      yamldecode(local_file.ansible_inventory.content).all.vars.tailscale_package_version == var.tailscale_package_version &&
      !contains(keys(yamldecode(local_file.ansible_inventory.content).all.children.k8s_nodes.children.control_plane.hosts["k8s-lab-node-1"]), "ansible_host") &&
      yamldecode(local_file.ansible_inventory.content).all.children.k8s_nodes.children.control_plane.hosts["k8s-lab-node-1"].k8s_node_ip == "10.0.1.11" &&
      yamldecode(local_file.ansible_inventory.content).all.children.k8s_nodes.children.workers.hosts["k8s-lab-node-3"].k8s_node_ip == "10.0.1.13"
    )
    error_message = "Terraform must generate the local Ansible inventory with fixed node names, private IPs, subnet and Tailscale version."
  }
}

run "reject_multiple_control_planes" {
  command = plan
  variables { control_plane_count = 2 }
  expect_failures = [var.control_plane_count]
}

run "reject_workerless_topology" {
  command = plan
  variables { node_count = 1 }
  expect_failures = [var.node_count]
}

run "initial_node" {
  command = apply
  module { source = "./modules/node" }
  variables {
    name                      = "test-node"
    server_type               = "cx23"
    image                     = "161547269"
    location                  = "nbg1"
    ssh_key_id                = "1"
    firewall_ids              = [1]
    subnet_id                 = "1"
    private_ip                = "10.0.1.11"
    tailscale_auth_key        = "test-key-original"
    tailscale_package_version = "1.102.4"
  }
  assert {
    condition = (
      strcontains(nonsensitive(hcloud_server.this.user_data), "test-key-original") &&
      strcontains(nonsensitive(hcloud_server.this.user_data), "--hostname='test-node'") &&
      terraform_data.tailscale_device.input.device_id == "nodeidTEST" &&
      terraform_data.tailscale_device.triggers_replace == hcloud_server.this.id &&
      terraform_data.cloud_init_ready.triggers_replace == hcloud_server.this.id
    )
    error_message = "A new node must use its fixed hostname and record its device identity and server replacement trigger."
  }
}

run "refresh_bootstrap_inputs" {
  command = plan
  module { source = "./modules/node" }
  variables {
    name                      = "test-node"
    server_type               = "cx23"
    image                     = "161547269"
    location                  = "nbg1"
    ssh_key_id                = "1"
    firewall_ids              = [1]
    subnet_id                 = "1"
    private_ip                = "10.0.1.11"
    tailscale_auth_key        = "test-key-refreshed"
    tailscale_package_version = "1.102.6"
  }
  assert {
    condition = (
      strcontains(nonsensitive(hcloud_server.this.user_data), "test-key-original") &&
      strcontains(nonsensitive(hcloud_server.this.user_data), "1.102.4")
    )
    error_message = "Existing nodes must retain first-boot data when bootstrap inputs change."
  }
}

run "new_node_gets_fresh_inputs" {
  command   = apply
  state_key = "new-node"
  module { source = "./modules/node" }
  variables {
    name                      = "test-new-node"
    server_type               = "cx23"
    image                     = "161547269"
    location                  = "nbg1"
    ssh_key_id                = "1"
    firewall_ids              = [1]
    subnet_id                 = "1"
    private_ip                = "10.0.1.14"
    tailscale_auth_key        = "test-key-refreshed"
    tailscale_package_version = "1.102.6"
  }
  assert {
    condition = (
      strcontains(nonsensitive(hcloud_server.this.user_data), "test-key-refreshed") &&
      strcontains(nonsensitive(hcloud_server.this.user_data), "1.102.6")
    )
    error_message = "Fresh nodes must receive current bootstrap inputs."
  }
}

run "explicit_image_change" {
  command = plan
  module { source = "./modules/node" }
  variables {
    name                      = "test-node"
    server_type               = "cx23"
    image                     = "161547270"
    location                  = "nbg1"
    ssh_key_id                = "1"
    firewall_ids              = [1]
    subnet_id                 = "1"
    private_ip                = "10.0.1.11"
    tailscale_auth_key        = "test-key-refreshed"
    tailscale_package_version = "1.102.6"
  }
  assert {
    condition     = hcloud_server.this.image == "161547270"
    error_message = "Explicit image changes must not be ignored."
  }
}
