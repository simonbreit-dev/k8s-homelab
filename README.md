# Kubernetes Lab on Hetzner Cloud

A personal infrastructure-as-code project for building a Kubernetes cluster from
scratch. Terraform provisions Hetzner Cloud servers and networking; Ansible
configures containerd, bootstraps Kubernetes with kubeadm, and installs Cilium.
Tailscale provides SSH and local Kubernetes API access, while node traffic uses
the Hetzner private network.

The default setup is one control plane and two workers on Ubuntu 24.04. Pinned
versions, preflight checks and readiness checks keep the bootstrap explicit and
repeatable. This is a learning and portfolio project with a single control plane
and simplified security settings.

## Structure

- [`Makefile`](Makefile): setup, deployment, configuration and local checks.
- [`terraform/`](terraform/): infrastructure, cloud-init and the reusable node module.
- [`ansible/`](ansible/): cluster playbook, focused roles and shared configuration.
- [`tests/`](tests/): local regression tests; Terraform mock tests live in `terraform/tests/`.

Terraform writes the node names, private IPs, subnet and Tailscale version directly
to `ansible/inventory/hosts.yml` using `local_file`. `make deploy` applies
infrastructure, generates this inventory, and runs Ansible on the same local
machine. Generated inventory is ignored by Git.

Tailscale, Kubernetes and the local kubeconfig use the fixed names
`k8s-lab-node-1`, `k8s-lab-node-2` and `k8s-lab-node-3`. Terraform records each
Tailscale device ID and deletes that exact device through the API before deleting
or replacing its server, so the next deployment can reuse the same name.

## Getting started

You need:

- GNU Make, Terraform **1.16.4** and an HCP Terraform organization/workspace.
- Python **3.12+**, `kubectl` and Helm on the Ansible controller.
- A Hetzner Cloud project/API token and an SSH key pair.
- Tailscale with MagicDNS, SSH/API access to `tag:k8s-node`, and an OAuth client
  with `auth_keys` and `devices:core` Write permissions for that tag.

From the repository root, install the controller dependencies and copy the
configuration example:

```shell
make setup
cp terraform/config.auto.tfvars.example terraform/config.auto.tfvars
```

Make uses `ansible/.venv` directly; manual environment activation is unnecessary.
For direct `terraform apply` or `terraform destroy` commands, activate it first
with `source ansible/.venv/bin/activate` for readiness checks and device cleanup.

Set `ssh_public_key` in the copied file. Defaults provision three `cx23` servers
in `nbg1` with public IPv4/IPv6. The image ID is fixed to an Ubuntu 24.04 x86
image; selecting a different image ID replaces nodes. Version settings live in
[`terraform/variables.tf`](terraform/variables.tf) and
[`ansible/inventory/group_vars/all.yml`](ansible/inventory/group_vars/all.yml).

Configure credentials and select your workspace:

```shell
export TF_CLOUD_ORGANIZATION="your-organization"
export TF_WORKSPACE="your-workspace"
export HCLOUD_TOKEN="your-hetzner-token"
export TAILSCALE_OAUTH_CLIENT_ID="your-client-id"
export TAILSCALE_OAUTH_CLIENT_SECRET="your-client-secret"
terraform -chdir=terraform login
```

Keep credentials in environment variables or an ignored `.env.local` loaded by
`direnv`. Set the HCP workspace execution mode to **Local**: HCP stores the state,
while Terraform runs on your machine with local credentials and tfvars and writes
the inventory there.

## Provision and use

From the repository root:

```shell
make plan
make deploy
kubectl --kubeconfig="$HOME/.kube/k8s-lab-admin.conf" get nodes -o wide
```

Deployment keeps Terraform's normal confirmation prompt. Ansible automatically
waits up to ten minutes for SSH over Tailscale and another ten minutes for
successful cloud-init completion before configuring nodes. A failed stage stops
the deployment. The local admin kubeconfig is written to
`~/.kube/k8s-lab-admin.conf`.

Terraform waits for successful cloud-init completion over Tailscale before
attaching the private network. Cloud-init installs the persistent DHCP
configuration for that interface through systemd-networkd. Ansible waits for the
assigned IP before configuring Kubernetes.

If cloud-init fails, the task includes its detailed status. Inspect the affected
node's `/var/log/cloud-init.log` before retrying; rerunning Ansible does not repair
first-boot errors.

To rerun Ansible with the existing inventory:

```shell
make configure
```

Terraform updates the inventory during `apply`. If it is missing or the node
configuration has changed, run `make deploy` first.

Bootstrap requires the full inventory; partial `--limit` and full `--check` runs
are rejected. It configures the cluster and verifies readiness without performing
implicit package upgrades or automatic node resets. Cloud-init changes apply to
new or deliberately replaced nodes. For disposable-cluster recovery, destroy and
recreate the lab using `make destroy` followed by `make deploy`.

## Cleanup

```shell
make destroy
```

Device cleanup runs automatically with the local OAuth credentials. If the API
rejects cleanup, Terraform stops before deleting the affected server; fix the
credentials or permission and retry. A device already removed from Tailscale is
accepted. Terraform removes the generated inventory during destroy; the local
kubeconfig remains on disk.

## Checks

From the repository root, after `make setup`:

```shell
make check
```

This runs Terraform formatting/validation and mock tests, Ansible syntax checks,
and local regression tests. It does not apply infrastructure or configure nodes.
Full bootstrap and rerun validation require a disposable cluster. Run `make help`
to list all commands.

Licensed under the [MIT License](LICENSE).
