# Deploy the management core

First-time install on the core host (the Raspberry Pi). About 1.5 hours end to end.
Access is tunnel-only: the Pi exposes nothing on its network.

## Prerequisites

- `ailabs.cl` on Cloudflare.
- Tailscale on the Pi and on your laptop/phone.
- Pi 4 (4 GB+) or Pi 5, **64-bit OS** (`uname -m` → `aarch64`), Docker data on an **SSD**, not the SD card.

## 1. Prepare the Pi

```bash
sudo git clone https://github.com/jaime7981/homelab-ops.git /opt/homelab-ops
sudo chown -R $USER /opt/homelab-ops && cd /opt/homelab-ops
ALLOW_LAN_CIDR=192.168.1.0/24 ./scripts/bootstrap-node.sh
```

The bootstrap disables SSH passwords and enables a firewall (Tailscale + LAN allowed). Make sure your SSH key is in `~/.ssh/authorized_keys` or that `ssh <user>@<pi>` works over Tailscale SSH first. It doesn't touch your existing containers or tunnels.

Log out and in again (docker group).

## 2. Cloudflare: tunnel and Access first

Do this **before** starting anything, so no admin page is ever reachable without Access.

1. Tunnel `mgmt` → copy its token → public hostnames `dash`, `komodo`, `beszel`, `status`, `auth`, `ntfy`, `traefik` → all `HTTP traefik:8080`.
2. Access login method: **One-time PIN**.
3. Access applications A, B, C from [access.md § Access applications](access.md#access-applications).

## 3. Configure and start

```bash
cd /opt/homelab-ops/core
cp .env.example .env
cp homepage.env.example homepage.env
../scripts/gen-secrets.sh          # paste output into .env
nano .env                          # TAILSCALE_IP, CLOUDFLARE_TUNNEL_TOKEN, AUTHENTIK_TAG
mkdir -p traefik/logs authentik/{data,certs,custom-templates}
docker compose up -d
docker compose ps                  # all running / healthy after 1–2 min (slower on a Pi)
docker compose logs cloudflared    # "Registered tunnel connection" x4
```

Zero Trust → Tunnels: `mgmt` should show **Healthy**.

## 4. authentik

`https://auth.ailabs.cl/if/flow/initial-setup/` → Access email code → create the authentik admin.
Then follow [access.md § authentik](access.md#2-authentik-single-login): MFA, forward-auth provider + embedded outpost.

✅ `https://dash.ailabs.cl` → Access → authentik → Homepage.

## 5. Agents on the Pi itself

```bash
cd /opt/homelab-ops/node
cp .env.example .env        # NODE_NAME=raspi, CORE_HOST=<Pi tailscale IP>
```

- **Komodo:** `https://komodo.ailabs.cl`, log in with `KOMODO_INIT_ADMIN_*` → Settings → *Onboarding keys* → create → `KOMODO_ONBOARDING_KEY`.
- **Beszel:** `https://beszel.ailabs.cl` → create the admin → *Add system* `raspi` → copy `KEY` and `TOKEN`.

```bash
docker compose up -d        # no crowdsec profile on the core (it runs the full engine)
```

✅ `raspi` appears in Komodo (Servers) and Beszel.

## 6. Komodo: Git, webhook, OIDC

1. Settings → *Git accounts*: GitHub fine-grained token with read access to `homelab-ops`.
2. Syncs → New → repo `jaime7981/homelab-ops`, resource path `komodo/sync.toml` → *Refresh* → review the diff → *Execute*.
3. GitHub repo → Settings → Webhooks → URL shown by Komodo (`https://komodo.ailabs.cl/listener/github/...`), secret = `KOMODO_WEBHOOK_SECRET`, JSON, push events.
4. authentik `komodo` OIDC provider ([access.md](access.md#2-authentik-single-login) step 3) → `KOMODO_OIDC_*` in `.env` → `docker compose up -d komodo-core`.

## 7. CrowdSec

```bash
docker exec crowdsec cscli bouncers list     # "traefik" listed
docker exec crowdsec cscli metrics           # traefik + auth.log parsers reading lines
docker exec crowdsec cscli console enroll <key from app.crowdsec.net>   # optional
docker exec crowdsec cscli machines add homepage --password '<pw>' -f /dev/null   # for the dashboard widget
```

## 8. Notifications

[operations.md § Notifications](operations.md#notifications): ntfy user + token, phone app, then point Komodo, Beszel and Uptime Kuma at it.

## 9. Dashboard

Fill `homepage.env` (Komodo API key, Beszel user, authentik token, CrowdSec password), edit `homepage/services.yaml` for your machines and sites, `docker compose restart homepage`. See [dashboard.md](dashboard.md).

## 10. Uptime Kuma

`https://status.ailabs.cl` → admin → monitors for each site and machine ([operations.md](operations.md#websites-and-tunnels)) → status page with slug `homelab`.

## 11. Your existing Pi apps

Move the two apps already on the Pi into `stacks/raspi/<app>/compose.yaml` (keep their own `cloudflared` sidecars) and register them in `komodo/sync.toml`. See [add-app.md](add-app.md#migrating-your-existing-apps).

## Upgrading the core

```bash
cd /opt/homelab-ops && git pull
cd core && docker compose pull && docker compose up -d
docker image prune -f
```

For authentik, read the release notes before bumping `AUTHENTIK_TAG`, one minor version at a time.

## Raspberry Pi notes

- **Komodo database image:** if `ghcr.io/ferretdb/postgres-documentdb` fails to pull on ARM, replace `komodo-pg` + `komodo-ferretdb` with a single MongoDB service: `mongo:7` on a Pi 5, `mongo:4.4` on a Pi 4 (newer MongoDB needs ARMv8.2, which the Pi 4 lacks). Point `KOMODO_DATABASE_ADDRESS` at it.
- **Memory:** the core uses ~2–2.5 GB. On a 4 GB Pi add `mem_limit`s if your apps compete, and enable zram swap.
- **Storage:** both databases write constantly. Keep `/var/lib/docker` on SSD.
