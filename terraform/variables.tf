# dropicture/terraform/variables.tf
variable "hcloud_token" {
  description = "Hetzner Cloud API token (env: TF_VAR_hcloud_token)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_b64" {
  description = "Base64-encoded public SSH key (env: TF_VAR_ssh_public_key_b64)"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Prefix used to name all resources"
  type        = string
  default     = "dropicture"
}

variable "os_image" {
  description = "Server OS image"
  type        = string
  default     = "ubuntu-24.04"
}

variable "manager_server_type" {
  description = "Hetzner server type for Swarm managers (cpx21 = 3 vCPU / 4 GB, cpx31 = 4 vCPU / 8 GB, cpx41 = 8 vCPU / 16 GB)"
  type        = string
  default     = "cpx31"
}

variable "worker_server_type" {
  description = "Hetzner server type for Swarm workers (run the actual workloads)"
  type        = string
  default     = "cpx31"
}

variable "location" {
  description = "Hetzner datacenter (fsn1, nbg1, hel1)"
  type        = string
  default     = "fsn1"
}

variable "volume_size" {
  description = "Size of the per-node object-storage volume, in GB (Hetzner minimum = 10)"
  type        = number
  default     = 50

  validation {
    condition     = var.volume_size >= 10
    error_message = "A Hetzner volume must be at least 10 GB."
  }
}

variable "cloudflare_zone_name" {
  description = "Cloudflare zone name (e.g. dropicture.com)"
  type        = string
  default     = "dropicture.com"
}

variable "manager_count" {
  description = "Number of Swarm managers (Raft quorum). MUST be odd (1, 3, 5). 1 = single manager (no control-plane HA), 3 = HA."
  type        = number
  default     = 1

  validation {
    condition     = var.manager_count >= 1 && var.manager_count % 2 == 1
    error_message = "manager_count must be an odd number (1, 3, 5, ...) to keep a healthy Raft quorum."
  }
}

variable "worker_count" {
  description = "Number of Swarm workers. 0 = run workloads on the managers only. Freely scalable up or down."
  type        = number
  default     = 0

  validation {
    condition     = var.worker_count >= 0
    error_message = "worker_count must be >= 0."
  }
}

variable "network_ip_range" {
  description = "CIDR of the private network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_ip_range" {
  description = "CIDR of the nodes subnet (within network_ip_range)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "network_zone" {
  description = "Hetzner network zone (eu-central for fsn1/nbg1/hel1)"
  type        = string
  default     = "eu-central"
}