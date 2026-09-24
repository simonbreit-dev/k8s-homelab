# Disposable Kubernetes Lab on Hetzner Cloud

Terraform configuration for disposable Hetzner Cloud nodes connected through Tailscale. The repository currently provisions the infrastructure foundation; it does not install Kubernetes.

## What it creates

- A private Hetzner network and subnet.
- A shared firewall that permits inbound Tailscale UDP traffic and blocks other public ingress.
- A Terraform-managed Hetzner SSH key.
- A configurable number of servers with explicit location, image, IPv4, and hostname settings.
- One reusable, preauthorized Tailscale key per server. Registered nodes are ephemeral.
- Cloud-init that hardens SSH, installs Tailscale, and joins the node to the tailnet.

## Structure

```text
.
├── backend.tf                    # HCP Terraform cloud configuration
├── terraform.tf                  # Terraform and provider requirements
├── providers.tf                  # Provider configuration
├── main.tf                       # Shared infrastructure and node module calls
├── known_hosts.tf                # Optional local known-hosts management
├── variables.tf                  # Root input variables
├── config.auto.tfvars.example    # Non-secret example configuration
├── .terraform.lock.hcl           # Locked provider selections
├── .terraformignore              # HCP configuration-upload exclusions
├── LICENSE
├── scripts/
│   └── update-known-host.sh
└── modules/
    └── node/
        ├── terraform.tf
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── templates/
            └── cloud-init.yml
```

`modules/node` is an internal module that owns one server and its bootstrap lifecycle.

## Prerequisites

- Terraform 1.16.4.
- A Hetzner Cloud project and API token.
- A Tailscale OAuth client with the `auth_keys` scope and permission to assign `tag:k8s-node` or the configured replacement.
- A tailnet policy that permits the required access to that tag.
- An OpenSSH public key and its matching private key.
- An HCP Terraform organization and workspace.

For HCP remote execution, provider credentials must be HCP workspace **environment variables**:

```text
HCLOUD_TOKEN
TAILSCALE_OAUTH_CLIENT_ID
TAILSCALE_OAUTH_CLIENT_SECRET
```

Keep them out of Terraform variables and tfvars files.

## HCP Terraform

Authenticate the CLI and select the workspace externally:

```shell
terraform login
export TF_CLOUD_ORGANIZATION="your-organization"
export TF_WORKSPACE="your-workspace"
```

Set the HCP workspace Terraform version to 1.16.4. Add `ssh_public_key` as a workspace Terraform variable; all other Terraform inputs have defaults and only need values when overridden. Local tfvars and environment files are excluded from HCP uploads through `.terraformignore`.

For local execution, the committed `.envrc` can load an ignored `.env.local`:

```dotenv
HCLOUD_TOKEN=replace-me
TAILSCALE_OAUTH_CLIENT_ID=replace-me
TAILSCALE_OAUTH_CLIENT_SECRET=replace-me
TF_CLOUD_ORGANIZATION=your-organization
TF_WORKSPACE=your-workspace
```

Run `direnv allow` after creating the file.

## Configuration

Copy the example for local execution:

```shell
cp config.auto.tfvars.example config.auto.tfvars
```

Only `ssh_public_key` is required. Project defaults are:

| Variable | Default |
| --- | --- |
| `manage_known_hosts` | `false` |
| `node_count` | `3` |
| `node_image` | `ubuntu-24.04` |
| `node_location` | `nbg1` |
| `node_name_prefix` | `k8s-lab-node` |
| `node_server_type` | `cx23` |
| `public_ipv4_enabled` | `true` |
| `tailscale_tag` | `tag:k8s-node` |

`node_count` is limited to 1–10. Public IPv4 addresses can incur an additional charge. The system-image name is resolved to a concrete image ID for the selected server architecture during planning; a later plan can therefore select a newer image and replace nodes.

## Workflow

```shell
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

With the `cloud` block, plan and apply use the selected HCP workspace unless that workspace is configured for local execution.

Terraform considers a server created before cloud-init and Tailscale registration necessarily finish. Verify the result with:

```shell
tailscale status
```

For bootstrap failures, use the Hetzner console:

```shell
cloud-init status --wait
sudo journalctl -u cloud-init
sudo journalctl -u tailscaled
sudo tailscale status
```

## SSH and known hosts

Public SSH is blocked by the Hetzner firewall. Connect through Tailscale MagicDNS:

```shell
ssh root@k8s-lab-node-1
```

When `manage_known_hosts = true`, Terraform runs `scripts/update-known-host.sh` after creating each node and writes scanned keys to `~/.ssh/known_hosts_k8s_lab` in the environment running Terraform. Use that file explicitly:

```shell
ssh -o UserKnownHostsFile="$HOME/.ssh/known_hosts_k8s_lab" root@k8s-lab-node-1
```

This option is intended for local execution. An HCP remote worker cannot populate the developer machine's known-hosts file.

## Destroy and cleanup

```shell
terraform destroy
```

Before deleting a server, Terraform makes a best-effort SSH call to `tailscale logout`; failure does not block destruction. Registered Tailscale devices are cloud-init side effects rather than Terraform resources, so verify the Tailscale admin console after destroy and remove stale devices if necessary.

The authentication keys are reusable, preauthorized, and recreated when invalid. They use the provider's 90-day default expiry. Nodes registered with them are ephemeral.

## Limitations

- Kubernetes installation and cluster bootstrapping are not implemented.
- Cloud-init is asynchronous initialization, not ongoing configuration management.
- The Tailscale installer is downloaded and executed at boot without a pinned version.
- Private-network ranges and shared resource names are project conventions.
- There is no automated CI/CD workflow; checks and Terraform operations are manual.

## License

This project is available under the [MIT License](LICENSE).
