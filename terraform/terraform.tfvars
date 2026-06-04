# dropicture/terraform/terraform.tfvars
project_name         = "dropicture"
os_image             = "ubuntu-24.04"
server_type          = "cpx32"
client_server_type   = "cpx32"
location             = "fsn1"
volume_size          = 50
cloudflare_zone_name = "dropicture.com"

manager_count = 1
worker_count  = 0