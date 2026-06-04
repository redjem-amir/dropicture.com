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

  manager_private_ips = [for i in range(var.manager_count) : cidrhost(var.subnet_ip_range, 10 + i)]
  worker_private_ips  = [for i in range(var.worker_count) : cidrhost(var.subnet_ip_range, 100 + i)]
}

resource "hcloud_network" "main" {
  name     = "${var.project_name}-net"
  ip_range = var.network_ip_range

  labels = {
    project = var.project_name
  }
}

resource "hcloud_network_subnet" "nodes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}

resource "hcloud_firewall" "app" {
  name = "${var.project_name}-firewall"

  labels = {
    project = var.project_name
    purpose = "ingress-protection"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SSH from anywhere (key-only auth enforced by Ansible)"
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP (ping)"
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

resource "hcloud_server" "manager" {
  count        = var.manager_count
  name         = "${var.project_name}-manager-${count.index + 1}"
  image        = var.os_image
  server_type  = var.manager_server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.deploy.id]
  firewall_ids = [hcloud_firewall.app.id]

  labels = {
    project = var.project_name
    role    = "swarm-manager"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.manager_private_ips[count.index]
  }

  depends_on = [hcloud_network_subnet.nodes]
}

resource "hcloud_server" "worker" {
  count        = var.worker_count
  name         = "${var.project_name}-worker-${count.index + 1}"
  image        = var.os_image
  server_type  = var.worker_server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.deploy.id]
  firewall_ids = [hcloud_firewall.app.id]

  labels = {
    project = var.project_name
    role    = "swarm-worker"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.worker_private_ips[count.index]
  }

  depends_on = [hcloud_network_subnet.nodes]
}

resource "hcloud_volume" "manager_media" {
  count    = var.manager_count
  name     = "${var.project_name}-media-manager-${count.index + 1}"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    project = var.project_name
    purpose = "object-storage"
  }
}

resource "hcloud_volume_attachment" "manager_media" {
  count     = var.manager_count
  volume_id = hcloud_volume.manager_media[count.index].id
  server_id = hcloud_server.manager[count.index].id
  automount = true
}

resource "hcloud_volume" "worker_media" {
  count    = var.worker_count
  name     = "${var.project_name}-media-worker-${count.index + 1}"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    project = var.project_name
    purpose = "object-storage"
  }
}

resource "hcloud_volume_attachment" "worker_media" {
  count     = var.worker_count
  volume_id = hcloud_volume.worker_media[count.index].id
  server_id = hcloud_server.worker[count.index].id
  automount = true
}