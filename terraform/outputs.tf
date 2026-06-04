# dropicture/terraform/outputs.tf
output "manager_public_ip" {
  description = "Public IPv4 of the primary manager (manager 1)"
  value       = hcloud_server.manager[0].ipv4_address
}

output "manager_public_ipv6" {
  description = "Public IPv6 of the primary manager (manager 1)"
  value       = hcloud_server.manager[0].ipv6_address
}

output "ssh" {
  description = "SSH command to connect to the primary manager (manager 1)"
  value       = "ssh root@${hcloud_server.manager[0].ipv4_address}"
}

output "docker_context" {
  description = "Command to manage the Swarm remotely over SSH from any machine"
  value       = "docker context create dropicture --docker \"host=ssh://root@${hcloud_server.manager[0].ipv4_address}\""
}

output "manager_public_ips" {
  description = "Public IPv4 of every Swarm manager"
  value       = hcloud_server.manager[*].ipv4_address
}

output "manager_private_ips" {
  description = "Private IPs of every Swarm manager (advertise/join targets)"
  value       = local.manager_private_ips
}

# --- Worker addresses --------------------------------------------------------
output "worker_public_ips" {
  description = "Public IPv4 of every Swarm worker"
  value       = hcloud_server.worker[*].ipv4_address
}

output "worker_private_ips" {
  description = "Private IPs of every Swarm worker"
  value       = local.worker_private_ips
}

# --- Combined (managers first, then workers) for convenience -----------------
output "node_public_ips" {
  description = "Public IPv4 of every node (managers first, then workers)"
  value       = concat(hcloud_server.manager[*].ipv4_address, hcloud_server.worker[*].ipv4_address)
}

output "node_private_ips" {
  description = "Private IPs of every node (managers first, then workers)"
  value       = concat(local.manager_private_ips, local.worker_private_ips)
}

output "media_volume_devices" {
  description = "Device path of each node's object-storage volume (auto-mounted under /mnt/HC_Volume_<id>)"
  value       = concat(hcloud_volume.manager_media[*].linux_device, hcloud_volume.worker_media[*].linux_device)
}

output "site_url" {
  description = "Public URL of the site"
  value       = "https://${var.cloudflare_zone_name}"
}

output "cloudflare_ipv4_count" {
  description = "Number of Cloudflare IPv4 ranges whitelisted in the firewall"
  value       = length(local.cloudflare_ipv4_cidrs)
}

output "origin_cert_pem" {
  description = "Cloudflare Origin CA certificate (PEM) for the reverse proxy"
  value       = cloudflare_origin_ca_certificate.origin.certificate
  sensitive   = true
}

output "origin_key_pem" {
  description = "Private key (PEM) matching the Origin CA certificate"
  value       = tls_private_key.origin.private_key_pem
  sensitive   = true
}