# Roles

After `tasks/preflight.yml` verifies the controller and all nodes, roles run in
the order defined by `playbooks/site.yml`:

- `common`: shared OS packages.
- `containerd`: pinned runtime, semantic configuration/CRI checks and service management.
- `kubernetes`: node networking prerequisites and pinned, held Kubernetes packages.
- `control_plane`: guarded initialization and idempotent local admin kubeconfig.
- `worker`: CA identity check and enrollment using a temporary bootstrap token.
- `cilium`: pod networking and cluster readiness checks.

Shared lab settings live in `inventory/group_vars/all.yml`. This is a bootstrap
workflow for one control plane with workers; Kubernetes upgrades are separate.
Private node IPs, subnet and Tailscale version come from Terraform-generated
inventory. Cloud-init configures the private interface. Preflight waits for SSH
and successful cloud-init completion, gathers facts and verifies the assigned IP.
Partial initialization and
retained-worker CA mismatches require manual inspection or deliberate cluster
recreation; bootstrap never resets nodes automatically.
