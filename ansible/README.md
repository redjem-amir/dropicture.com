## Development setup

The playbook reads the node IPs from the Terraform remote state (S3) and
configures the whole Docker Swarm cluster over SSH: Docker Engine (CE) with
log rotation, key-only SSH hardening, `swarm init`/`join` bound to the Hetzner
private network, the ingress overlay recreated with MTU 1400, the Cloudflare
Origin CA certificate and key stored as a Swarm config/secret, and any node
removed from the Terraform state pruned from the cluster. It is idempotent —
re-run it after every `terraform apply`. It needs only three environment
variables — the SSH key is decoded by the playbook itself, so no ssh-agent
setup is required.

1. Create a `.env` file at the repository root (next to `playbook.yml`):

````bash
cat <<'EOF' > .env
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export SSH_PRIVATE_KEY_B64=""
EOF
````

2. Install the Ansible prerequisites:

````bash
pip install ansible boto3 botocore
ansible-galaxy collection install community.docker amazon.aws community.general ansible.posix
````

3. Fill in the values, then load them into your shell:

````bash
source .env
````

4. Run the playbook:

````bash
ansible-playbook playbook.yml
````

> `.env` is listed in `.gitignore` — never commit it.

### Corporate proxy (optional)

The playbook no longer makes any HTTP call to the cluster: provisioning,
`swarm init`/`join`, secrets and node pruning all go over SSH (port 22), which
is not affected by `http_proxy` / `https_proxy`. The only HTTP traffic from
the control machine is the Terraform state download from S3, which goes
through a corporate proxy normally. No `no_proxy` exclusions are needed
anymore.

## Requirements

- SSH (22) is open to the world in the firewall; authentication is key-only
  (enforced by the playbook), so `SSH_PRIVATE_KEY_B64` must match the public
  key declared in `hcloud_ssh_key.deploy` — there is no other way in.
- The AWS credentials only need read access to the state bucket
  (`s3:GetObject` on `dropicture-tfstate-prod/terraform.tfstate`). No Secrets
  Manager permissions are required.

## Deploying stacks

No management API is exposed publicly: deployments go through SSH using a
Docker context (the ready-to-use command is in the `docker_context` Terraform
output):

````bash
docker context create dropicture --docker "host=ssh://root@<manager_public_ip>"
docker context use dropicture

docker stack deploy -c app.stack.yml dropicture
docker stack services dropicture
docker service logs -f dropicture_app
````

The Origin CA material is available cluster-wide as the `dropicture_origin_cert`
config and the `dropicture_origin_key` secret — reference them with
`external: true` in your stack files. Persistent data lives under
`/opt/dropicture/data/<service>` on every node (stable symlink to the Hetzner
volume).

> **Every overlay network you declare must set MTU 1400** (Hetzner private
> networks have a 1450 MTU and VXLAN adds 50 bytes — without this, large
> packets silently drop between nodes):
>
> ```yaml
> networks:
>   backend:
>     driver: overlay
>     driver_opts:
>       com.docker.network.driver.mtu: "1400"
> ```

## License

Released under the MIT License. See [LICENSE](../LICENSE).