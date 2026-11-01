# Deploy the management core

First-time install on the core host (the Raspberry Pi). About 1 hour end to end (add ~30 min if you enable authentik).
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

1. Tunnel `mgmt` → copy its token → public hostnames `dash`, `komodo`, `beszel`, `status`, `ntfy`, `traefik` (plus `auth` if you'll enable authentik) → all `HTTP traefik:8080`.
2. Access login method: **One-time PIN**.
3. Access applications from [access.md § Access applications](access.md#access-applications): A and C (B only with authentik).

## 3. Configure and start

```bash
cd /opt/homelab-ops/core
cp .env.example .env
cp homepage.env.example homepage.env
../scripts/gen-secrets.sh          # paste output into .env
nano .env                          # CORE_NAME, TAILSCALE_IP, TAILNET_DOMAIN, CLOUDFLARE_TUNNEL_TOKEN
mkdir -p traefik/logs
docker compose up -d
docker compose ps                  # all running / healthy after 1–2 min (slower on a Pi)
docker compose logs cloudflared    # "Registered tunnel connection" x4
```

Zero Trust → Tunnels: `mgmt` should show **Healthy**.

✅ `https://dash.ailabs.cl` → Cloudflare Access email code → Homepage.

## 4. (Optional) authentik

Skip this unless you want MFA/passkeys on your own hardware, user groups, or OIDC login for Komodo. Cloudflare Access already protects every admin hostname. To enable it later, follow [access.md § 2](access.md#2-authentik-optional-sso-layer).

## 5. Agents on the Pi itself

```bash
cd /opt/homelab-ops/node
cp .env.example .env        # NODE_NAME=<CORE_NAME> (jaime-pi), CORE_HOST=<Pi tailscale IP>
```

- **Komodo:** `https://komodo.ailabs.cl`, log in with `KOMODO_INIT_ADMIN_*` → Settings → *Onboarding keys* → create → `KOMODO_ONBOARDING_KEY`.
- **Beszel:** `https://beszel.ailabs.cl` → create the admin → *Add system* `jaime-pi` → copy `KEY` and `TOKEN`.

```bash
docker compose up -d        # no crowdsec profile on the core (it runs the full engine)
```

✅ `jaime-pi` appears in Komodo (Servers) and Beszel.

## 6. Komodo: Git and webhook

1. Settings → *Git accounts*: GitHub fine-grained token with read access to `homelab-ops`.
2. Syncs → New → repo `jaime7981/homelab-ops`, resource path `komodo/sync.toml` → *Refresh* → review the diff → *Execute*.
3. GitHub repo → Settings → Webhooks → URL shown by Komodo (`https://komodo.ailabs.cl/listener/github/...`), secret = `KOMODO_WEBHOOK_SECRET`, JSON, push events.
4. Only with authentik: `komodo` OIDC provider ([access.md § 2](access.md#2-authentik-optional-sso-layer), Configure step 3) → `KOMODO_OIDC_*` in `.env` → `docker compose up -d komodo-core`.

## 7. CrowdSec

```bash
docker exec crowdsec cscli bouncers list     # "traefik" listed
docker exec crowdsec cscli metrics           # traefik + auth.log parsers reading lines
docker exec crowdsec cscli console enroll <key from app.crowdsec.net>   # optional
docker exec crowdsec cscli machines add homepage --password '<pw>' -f /dev/null   # for the dashboard widget
```

## 8. Notifications

[operations.md § Notifications](operations.md#notifications): ntfy user + token, phone app, then point Komodo and Beszel at it. Put the token in `core/.env` as `GATUS_NTFY_TOKEN` and `docker compose up -d gatus`.

## 9. Dashboard

Fill `homepage.env` (Komodo API key, Beszel user, CrowdSec password; authentik token only if enabled), edit `homepage/services.yaml` for your machines and sites, `docker compose restart homepage`. See [dashboard.md](dashboard.md).

## 10. Uptime checks (Gatus)

Nothing to click: monitors are the files in `core/gatus/endpoints/`. Open `https://status.ailabs.cl` and check:

- **core** group green (tunnel, Komodo, Beszel, ntfy) and **Main site** green.
- Example machines and apps ship with `enabled: false`. Turn each on as it comes online (see [core/gatus/README.md](../core/gatus/README.md)).
- `docker compose logs gatus | grep -i ignoring` prints nothing (otherwise the ntfy token is wrong).

## 11. Your existing Pi apps

Move the two apps already on the Pi into `stacks/jaime-pi/<app>/compose.yaml` (keep their own `cloudflared` sidecars) and register them in `komodo/sync.toml`. See [add-app.md](add-app.md#migrating-your-existing-apps).

## Upgrading the core

```bash
cd /opt/homelab-ops && git pull
cd core && docker compose pull && docker compose up -d
docker image prune -f
```

For authentik, read the release notes before bumping `AUTHENTIK_TAG`, one minor version at a time.

## Raspberry Pi notes

- **Komodo database image:** if `ghcr.io/ferretdb/postgres-documentdb` fails to pull on ARM, replace `komodo-pg` + `komodo-ferretdb` with a single MongoDB service: `mongo:7` on a Pi 5, `mongo:4.4` on a Pi 4 (newer MongoDB needs ARMv8.2, which the Pi 4 lacks). Point `KOMODO_DATABASE_ADDRESS` at it.
- **Memory:** the core uses ~1.5 GB (~2–2.5 GB with authentik). On a 4 GB Pi add `mem_limit`s if your apps compete, and enable zram swap.
- **Storage:** both databases write constantly. Keep `/var/lib/docker` on SSD.
