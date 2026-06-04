# HELP — Running your own dropicture

dropicture is open source (MIT): anyone can run their own instance. Two supported
setups: **Cloud** (your own sovereign deployment on Hetzner, behind your own
domain) or **Self-hosted** (your own machine — Linux, macOS, Windows).

---

## 1. Cloud (Hetzner + Cloudflare)

**Bring your own:** a Hetzner Cloud account (API token), a domain managed by
Cloudflare, an AWS account (S3 bucket for the Terraform state + Secrets Manager),
and your public IP.

**Provision once:**

```bash
# terraform/terraform.tfvars — set at least cloudflare_zone_name = "<your-domain>"
# and export TF_VAR_hcloud_token, TF_VAR_ssh_public_key_b64, TF_VAR_admin_ips
terraform -chdir=terraform apply

# needs AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / SSH_PRIVATE_KEY_B64
ansible-playbook ansible/playbook.yml
```

**Images:** the job deploys the project's published images
(`ghcr.io/<owner>/dropicture.com/{backend,frontend}`). Running a fork? Push a
`vX.Y.Z` git tag (CI publishes the images under your namespace — set the GHCR
packages to **Public**) and update `image_base` in `cloud.nomad.hcl`.

**Step 1 — Create `.env`** (once; PostgreSQL keeps the first credentials it is
initialized with; never commit this file):

```bash
cat >> .env <<EOF
POSTGRES_HOST=10.0.1.10
POSTGRES_DB=dropicture
POSTGRES_USER=$(openssl rand -hex 12)
POSTGRES_PASSWORD=$(openssl rand -hex 12)
REDIS_HOST=10.0.1.10
EOF
```

`POSTGRES_HOST` / `REDIS_HOST` are the node's private IP — `10.0.1.10` with the
default network settings (`terraform output server_private_ips` to confirm).

**Step 2 — Deploy:**

```bash
# Cluster address + ACL token (stored in AWS Secrets Manager by Ansible)
export NOMAD_ADDR="http://$(terraform -chdir=terraform output -raw server_public_ip):4646"
export NOMAD_TOKEN="$(aws secretsmanager get-secret-value \
  --secret-id nomad/dropicture/management-token \
  --region eu-west-3 --query SecretString --output text)"

# Job variables from .env
set -a; source .env; set +a
export NOMAD_VAR_postgres_host="$POSTGRES_HOST" \
       NOMAD_VAR_postgres_db="$POSTGRES_DB" \
       NOMAD_VAR_postgres_user="$POSTGRES_USER" \
       NOMAD_VAR_postgres_password="$POSTGRES_PASSWORD" \
       NOMAD_VAR_redis_host="$REDIS_HOST"

# Deploy a pinned version — rollback = re-run with the previous one
nomad job run -var="app_version=1.0.0" cloud.nomad.hcl
```

**Step 3 — Verify:** `nomad job status dropicture` (all 5 groups running), then
`curl -I https://<your-domain>`.

**If it fails:** `connection refused` → your IP is not in `admin_ips` ·
`403` → bad/missing `NOMAD_TOKEN` · `no value for required variable` → missing
`NOMAD_VAR_*` export · `missing host volumes` → re-run the Ansible playbook ·
image pull error → GHCR package still private, or the tag was never built.

---

## 2. Self-hosted (your own machine)

Runs the same stack on a single-node Nomad agent with Docker — no cloud account,
no domain: Docker named volumes for the data, services exposed on `localhost`.

**Prerequisites**

- **Docker** — Docker Desktop (macOS, Windows) or Docker Engine (Linux).
- **Nomad** — single binary from [releases.hashicorp.com/nomad](https://releases.hashicorp.com/nomad/);
  put it on your `PATH` (e.g. `~/bin`, no admin rights needed).

**Step 1 — Start the agent** (keep it running in its own terminal):

```bash
# macOS — point Nomad at the Docker Desktop user socket (works without admin):
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
nomad agent -dev -bind 127.0.0.1

# Linux:   sudo nomad agent -dev -bind 127.0.0.1
# Windows: nomad agent -dev -bind 127.0.0.1   (Docker Desktop running)
```

**Step 2 — Deploy:** same `.env` as the cloud section, with
`POSTGRES_HOST=localhost` and `REDIS_HOST=localhost`, then:

```bash
set -a; source .env; set +a
export NOMAD_VAR_postgres_host="$POSTGRES_HOST" \
       NOMAD_VAR_postgres_db="$POSTGRES_DB" \
       NOMAD_VAR_postgres_user="$POSTGRES_USER" \
       NOMAD_VAR_postgres_password="$POSTGRES_PASSWORD" \
       NOMAD_VAR_redis_host="$REDIS_HOST"

nomad job run -var="app_version=1.0.0" selfhost.nomad.hcl
```

**Step 3 — Verify:** `nomad job status dropicture`, then open
`http://localhost:3000` (frontend) — the API answers on `http://localhost:3001`.

**If it fails:** `missing drivers` → Docker not running, or `DOCKER_HOST` not set
(macOS) · job stuck `pending` → check `nomad alloc status <id>` for the reason ·
ports already in use → stop whatever holds `3000/3001/5432/6379`.