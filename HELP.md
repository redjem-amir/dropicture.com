# HELP — Quick deploy

Prereqs: infra provisioned (`terraform apply` + `ansible-playbook ansible/playbook.yml`).
All commands run from the repository root.

## 0. Configure (once)

```bash
cat > .env <<EOF
IMAGE_TAG=latest
POSTGRES_DB=dropicture
POSTGRES_USER=$(openssl rand -hex 12)
POSTGRES_PASSWORD=$(openssl rand -hex 12)
GARAGE_RPC_SECRET=$(openssl rand -hex 32)
GARAGE_KEY_ID=GK$(openssl rand -hex 12)
GARAGE_KEY_SECRET=$(openssl rand -hex 32)
EOF
```

`.env` is gitignored — never commit it.

## 1. Cloud (Docker Swarm)

```bash
docker context create dropicture \
  --docker "host=ssh://root@$(terraform -chdir=terraform output -raw manager_public_ip)"

docker context use dropicture
set -a; source .env; set +a
docker stack deploy --detach=false -c docker-compose.yml dropicture
```

First deploy only — init Garage (S3):

```bash
G=$(docker ps -qf name=dropicture_dropicture-garage)
docker exec $G /garage status
docker exec $G /garage layout assign -z dc1 -c 40G <node_id>
docker exec $G /garage layout apply --version 1
docker exec $G /garage key import --yes "$GARAGE_KEY_ID" "$GARAGE_KEY_SECRET" -n dropicture-app
docker exec $G /garage bucket create dropicture-media
docker exec $G /garage bucket allow --read --write dropicture-media --key dropicture-app
```

Check: `docker stack services dropicture`, then `curl -I https://dropicture.com`.
Update / rollback: redeploy with another `IMAGE_TAG`.

## 2. Local

```bash
docker context use default
docker compose -f docker-compose.local.yml up -d
```

First run only — init Garage:

```bash
set -a; source .env; set +a
dc() { docker compose -f docker-compose.local.yml "$@"; }
dc exec dropicture-garage /garage status
dc exec dropicture-garage /garage layout assign -z dc1 -c 10G <node_id>
dc exec dropicture-garage /garage layout apply --version 1
dc exec dropicture-garage /garage key import --yes "$GARAGE_KEY_ID" "$GARAGE_KEY_SECRET" -n dropicture-app
dc exec dropicture-garage /garage bucket create dropicture-media
dc exec dropicture-garage /garage bucket allow --read --write dropicture-media --key dropicture-app
```

Open http://localhost:3000 (API: http://localhost:3001).
Stop: `docker compose -f docker-compose.local.yml down` (`-v` wipes data).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `"VAR is required"` | `set -a; source .env; set +a` |
| `permission denied (publickey)` | load the deploy key: `ssh-add` |
| `config not found: dropicture_origin_*` | re-run the Ansible playbook |
| pull denied / `No such image` | GHCR package is private after first push → set it **Public**; or tag not built |
| task stuck `Pending` | `docker service ps dropicture_<svc> --no-trunc` |
| nginx `502` | `docker service logs dropicture_dropicture-backend` |
| `failed to update config` | configs are immutable → bump `name:` (`_v2` → `_v3`) |
| Cloudflare `52x` | zone SSL mode = **Full (strict)** |
| deploys to the wrong place | `docker context ls` → `use default` (local) / `use dropicture` (cloud) |
| app S3 errors | Garage init step skipped |