# dropicture/.terraform/outputs.tf
output "server_public_ip" {
  description = "Public IPv4 address of the server"
  value       = hcloud_server.app.ipv4_address
}

output "server_public_ipv6" {
  description = "Public IPv6 address of the server"
  value       = hcloud_server.app.ipv6_address
}

output "ssh" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.app.ipv4_address}"
}

output "nomad_ui" {
  description = "Nomad UI (reachable from admin_ips only)"
  value       = "http://${hcloud_server.app.ipv4_address}:4646"
}

output "photo_volume_device" {
  description = "Device path of the photo volume (auto-mounted under /mnt/HC_Volume_<id>)"
  value       = hcloud_volume.photos.linux_device
}

output "site_url" {
  description = "Public URL of the site"
  value       = "https://${var.cloudflare_zone_name}"
}

output "cloudflare_ipv4_count" {
  description = "Number of Cloudflare IPv4 ranges whitelisted in the firewall"
  value       = length(local.cloudflare_ipv4_cidrs)
}