provider "hcloud" {}

provider "tailscale" {
  tailnet = "-"
  scopes  = ["auth_keys"]
}
