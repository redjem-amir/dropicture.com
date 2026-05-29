# dropicture/terraform/compute.tf
resource "hcloud_ssh_key" "deploy" {
  name       = "${var.project_name}-deploy-key"
  public_key = base64decode(var.ssh_public_key_b64)
}

data "http" "cloudflare_ipv4" {
  url             = "https://www.cloudflare.com/ips-v4/#"
  request_headers = { Accept = "text/plain" }
}

data "http" "cloudflare_ipv6" {
  url             = "https://www.cloudflare.com/ips-v6/#"
  request_headers = { Accept = "text/plain" }
}

locals {
  cloudflare_ipv4_cidrs = compact([
    for cidr in split("\n", data.http.cloudflare_ipv4.response_body) :
    trimspace(cidr) if trimspace(cidr) != ""
  ])

  cloudflare_ipv6_cidrs = compact([
    for cidr in split("\n", data.http.cloudflare_ipv6.response_body) :
    trimspace(cidr) if trimspace(cidr) != ""
  ])

  cloudflare_all_cidrs = concat(local.cloudflare_ipv4_cidrs, local.cloudflare_ipv6_cidrs)
}

resource "hcloud_firewall" "app" {
  name = "${var.project_name}-firewall"

  labels = {
    project = var.project_name
    purpose = "single-node-ingress-protection"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.admin_ips
    description = "SSH admin"
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = var.admin_ips
    description = "ICMP admin (ping)"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "4646"
    source_ips  = var.admin_ips
    description = "Nomad UI / API (admin only)"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = local.cloudflare_all_cidrs
    description = "HTTPS via Cloudflare only"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = local.cloudflare_all_cidrs
    description = "HTTP via Cloudflare only (80 -> 443 redirect)"
  }
}

resource "hcloud_server" "app" {
  name         = "${var.project_name}-app"
  image        = var.os_image
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.deploy.id]
  firewall_ids = [hcloud_firewall.app.id]

  labels = {
    project = var.project_name
    role    = "nomad-single-node"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

resource "hcloud_volume" "photos" {
  name     = "${var.project_name}-photos"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    project = var.project_name
    purpose = "photo-storage"
  }
}

resource "hcloud_volume_attachment" "photos" {
  volume_id = hcloud_volume.photos.id
  server_id = hcloud_server.app.id
  automount = true
}