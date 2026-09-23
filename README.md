# Disposable Kubernetes Lab on Hetzner Cloud

This repository provisions disposable Hetzner Cloud servers with Terraform and connects them to a Tailscale tailnet. It is a small, single-developer learning project and a public reference for Terraform, HCP Terraform, Hetzner Cloud, cloud-init, and Tailscale integration.

The current Terraform configuration creates the infrastructure foundation only. It does **not** install or configure Kubernetes yet.

## What it creates

- A Hetzner Cloud private network using the 10.0.0.0/16 range.
- A 10.0.1.0/24 cloud-network subnet in the eu-central network zone.
- A shared Hetzner Cloud firewall.
- A configurable number of Ubuntu servers attached to the private network.
- One short-lived Tailscale authentication key per server.
- Cloud-init configuration that installs Tailscale and registers each server as an ephemeral node.

Each server currently has:

- No public IPv4 address.
- A public IPv6 address for outbound connectivity and Tailscale bootstrap.
- Only inbound UDP port 41641 permitted by the Hetzner firewall.
- All other inbound public traffic, including public SSH, denied by the Hetzner firewall.
- OpenSSH available over the Tailscale network using an existing Hetzner Cloud SSH key.

## Scope and assumptions

- The lab is used by one developer at a time.
- Servers and related resources are expected to be created and destroyed frequently.
- The configuration is not designed as a production Kubernetes platform.
- There is no automatic GitHub Actions workflow or automatic apply. Formatting, validation, plans, applies, and destroys are run manually.
- The current node module expects an existing Hetzner Cloud SSH key named **Hetzner Neu**. This is an account-specific prerequisite until the SSH-key handling is made configurable.

## Repository layout

    .
    ├── main.tf                         # Providers and shared infrastructure
    ├── variables.tf                    # Root input variables
    ├── outputs.tf                      # Reserved for future useful outputs
    ├── config.auto.tfvars.example      # Example non-secret configuration
    ├── .terraform.lock.hcl             # Locked provider versions and checksums
    └── modules/
        └── node/
            ├── main.tf                 # Hetzner server
            ├── variables.tf
            ├── providers.tf
            └── templates/
                └── cloud-init.yml      # SSH hardening and Tailscale bootstrap

## Prerequisites

### Local tools

- Terraform 1.16.4.
- Optional: direnv for loading .env.local through the committed .envrc.
- An SSH client and a device connected to the target Tailscale tailnet.

The repository pins:

- hetznercloud/hcloud 1.60.1
- tailscale/tailscale 0.29.2

Keep .terraform.lock.hcl committed so all environments use the same provider builds.

### Accounts and external configuration

You need:

1. A Hetzner Cloud project and a read/write API token.
2. An existing Hetzner Cloud SSH key named Hetzner Neu.
3. A Tailscale tailnet.
4. A Tailscale OAuth client with:
   - The auth_keys scope.
   - Permission to create keys carrying tag:k8s-node.
5. A Tailscale access policy that allows your developer device to reach tag:k8s-node.
6. An existing HCP Terraform organization and workspace.

The provider uses tailnet = "-", so it operates on the tailnet that owns the supplied Tailscale OAuth credentials.

## HCP Terraform configuration

The empty cloud block deliberately avoids committing a personal HCP organization or workspace name.

Authenticate the local Terraform CLI:

~~~shell
terraform login
~~~

Select the existing HCP organization and workspace in your local shell:

~~~shell
export TF_CLOUD_ORGANIZATION="your-organization"
export TF_WORKSPACE="your-workspace"
~~~

Set the HCP workspace Terraform version to 1.16.4.

For the default HCP remote-execution mode, configure these as **sensitive environment variables** in the HCP workspace:

- HCLOUD_TOKEN
- TAILSCALE_OAUTH_CLIENT_ID
- TAILSCALE_OAUTH_CLIENT_SECRET

Configure these as HCP workspace **Terraform variables**:

- node_count
- node_image
- node_server_type

The local tfvars files are intentionally excluded from HCP configuration uploads. Remote runs therefore receive input values from the workspace, not from config.auto.tfvars.

## Optional local environment

If the HCP workspace uses local execution, or for local provider commands, .envrc loads an ignored .env.local file when direnv is installed.

Example:

~~~dotenv
HCLOUD_TOKEN=replace-me
TAILSCALE_OAUTH_CLIENT_ID=replace-me
TAILSCALE_OAUTH_CLIENT_SECRET=replace-me
TF_CLOUD_ORGANIZATION=your-organization
TF_WORKSPACE=your-workspace
~~~

Then enable it:

~~~shell
direnv allow
~~~

Never commit .env.local. Both Git and HCP Terraform upload rules exclude it.

## Terraform inputs

The non-secret example is:

~~~hcl
node_count       = 3
node_image       = "ubuntu-24.04"
node_server_type = "cx23"
~~~

For local execution, copy it:

~~~shell
cp config.auto.tfvars.example config.auto.tfvars
~~~

For HCP remote execution, configure the same values as workspace Terraform variables instead.

## Provisioning

Initialize the working directory:

~~~shell
terraform init
~~~

Run local static checks:

~~~shell
terraform fmt -check -recursive
terraform validate
~~~

Review and apply:

~~~shell
terraform plan
terraform apply
~~~

With HCP remote execution, plan and apply run in the selected HCP workspace. The local directory is uploaded according to .terraformignore.

## Verifying provisioning

Hetzner server creation completes before cloud-init and Tailscale registration are necessarily finished. A successful Terraform apply therefore does not guarantee that every node has joined the tailnet.

Check the Tailscale admin console or run the following from an existing tailnet device:

~~~shell
tailscale status
~~~

Expected node names are:

- k8s-lab-node-1
- k8s-lab-node-2
- and so on, according to node_count.

If a node does not appear, use the Hetzner web console and inspect:

~~~shell
cloud-init status --wait
sudo journalctl -u cloud-init
sudo journalctl -u tailscaled
sudo tailscale status
~~~

The Tailscale key expires after one hour, is single-use, and is not reusable. If bootstrap fails after the key expires or is consumed, replace the affected key and server together.

Example for the first node:

~~~shell
terraform apply \
  -replace='tailscale_tailnet_key.node[0]' \
  -replace='module.nodes[0].hcloud_server.this'
~~~

## Connecting to a node

Public SSH is blocked by the Hetzner firewall. Connect through Tailscale using regular OpenSSH and the private key matching the Hetzner Cloud key named Hetzner Neu:

~~~shell
ssh root@k8s-lab-node-1
~~~

This assumes Tailscale MagicDNS is enabled. Otherwise, use the node's Tailscale IP from tailscale status or the admin console.

The current cloud-init command does not enable Tailscale SSH; it installs Tailscale as a network transport for ordinary OpenSSH.

## Destroy and cleanup

Destroy the lab when it is no longer needed:

~~~shell
terraform destroy
~~~

Terraform owns and destroys:

- Hetzner servers.
- The Hetzner firewall.
- The private network and subnet.
- Tailscale authentication-key resources.

Terraform does **not** own the Tailscale device records created when the servers register. The current keys create ephemeral nodes, so Tailscale removes them automatically after the destroyed servers have been offline for a while. Cleanup is not immediate.

After destroy:

1. Confirm that the Hetzner servers, firewall, network, subnet, and Primary IP resources are gone.
2. Check the Tailscale admin console for stale nodes.
3. Manually remove any node that does not disappear automatically.

If destroy fails partway through, restore valid provider credentials and run terraform destroy again. Hetzner resources that remain continue to incur cost.

## Security and secret handling

- Provider credentials are supplied through environment variables, never Terraform input variables.
- .gitignore excludes local credentials, tfvars, state, saved plans, private keys, and local editor files.
- .terraformignore separately excludes those files from HCP Terraform configuration uploads.
- HCP Terraform state can contain generated Tailscale keys and rendered server user-data. Restrict access to the workspace and its state.
- The Tailscale keys are short-lived, single-use, preauthorized, tagged, and create ephemeral nodes.
- The Hetzner firewall is the enforcement boundary preventing public SSH and accidental exposure of future services.
- The current Tailscale installer is downloaded at boot from tailscale.com and is not version-pinned. This is an accepted convenience for this disposable lab, not a production supply-chain pattern.

## Known limitations

- Kubernetes installation and cluster bootstrapping are not implemented.
- The Hetzner SSH-key name is currently hard-coded.
- Server location and network settings are project defaults rather than inputs.
- Cloud-init is initialization, not ongoing configuration management.
- Terraform cannot directly verify or immediately delete the Tailscale device created by a node.
- Partial server replacement requires replacing its single-use Tailscale key as well.
- There is no automated CI/CD workflow by design; checks are run manually.
