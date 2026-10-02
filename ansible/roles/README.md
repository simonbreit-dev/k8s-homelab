# Roles

Roles run in the order defined by `playbooks/site.yml`:

- `common`: shared OS packages.
- `containerd`: runtime installation, validated configuration, and service management.
- `kubernetes`: node networking prerequisites and held Kubernetes packages.
- `control_plane`: cluster initialization and local admin kubeconfig.
- `worker`: worker enrollment using a temporary bootstrap token.
- `cilium`: pod networking and cluster readiness checks.

Shared lab settings live in `inventory/group_vars/all.yml`. This is a bootstrap
workflow for one control plane with workers; Kubernetes upgrades are separate.
