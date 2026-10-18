# Deploy the management core

First-time install on the core host. About 1–2 hours end to end.

## Prerequisites

- A domain on Cloudflare (`DOMAIN` below).
- A Tailscale account; your laptop/phone already on it.
- The core host: Ubuntu 22.04/24.04 or Debian 12, always on, ideally wired. 4 GB RAM is enough for the core.

## 1. Prepare the host

```bash
git clone https://github.com/jaime7981/homelab-ops.git /opt/homelab-ops
cd /opt/homelab-ops
./scripts/bootstrap-node.sh
sudo tailscale up --ssh --hostname=core-pc
ALLOW_LAN_CIDR=192.168.1.0/24 ./scripts/bootstrap-node.sh   # re-run: now enables the firewall
```

Log out and in again (docker group). Get the Tailscale IP: `tailscale ip -4`.

## 2. Cloudflare

1. **API token** (My Profile → API Tokens → Create → *Edit zone DNS* template, zone = DOMAIN) → `CF_DNS_API_TOKEN`.
2. **Tunnel** `mgmt` → token → `CLOUDFLARE_TUNNEL_TOKEN`. Public hostnames → `http://traefik:8080` (list in [access.md](access.md#dns--tunnel)).
3. **DNS** `*.lab` → `A` → Tailscale IP, DNS only.

Access policies come later (step 7), once you can log in.

## 3. Configure and start

```bash
cd /opt/homelab-ops/core
cp .env.example .env
cp homepage.env.example homepage.env
../scripts/gen-secrets.sh          # paste output into .env
$EDITOR .env                       # DOMAIN, ACME_EMAIL, TAILSCALE_IP, CF_*, AUTHENTIK_TAG
mkdir -p traefik/logs authentik/{data,certs,custom-templates}
docker compose up -d
docker compose ps                  # all running / healthy after ~1 min
docker compose logs -f traefik     # watch the *.lab.DOMAIN certificate get issued
```

## 4. authentik

From a tailnet device open `https://auth.lab.DOMAIN/if/flow/initial-setup/`, create the admin.
Then follow [access.md § authentik](access.md#3-authentik-single-login): MFA, forward-auth provider + embedded outpost, Komodo OIDC provider.

Test: `https://dash.lab.DOMAIN` should redirect to authentik and back to Homepage.

## 5. Agents on the core itself

```bash
cd /opt/homelab-ops/node
cp .env.example .env    # NODE_NAME=core-pc, CORE_HOST=<core tailscale IP>
```

- **Komodo:** open `https://komodo.lab.DOMAIN`, log in with `KOMODO_INIT_ADMIN_*`. Settings → *Onboarding keys* → create one → `KOMODO_ONBOARDING_KEY`.
- **Beszel:** open `https://beszel.lab.DOMAIN`, create the admin, *Add system* `core-pc` → copy `KEY` and `TOKEN`.

```bash
docker compose up -d     # no crowdsec profile on the core (it runs the full engine)
```

`core-pc` should appear in Komodo (Servers) and Beszel within seconds.

## 6. Komodo: Git, webhook, OIDC

1. Komodo → Settings → *Git accounts*: add a GitHub fine-grained token with read access to `homelab-ops`.
2. Syncs → New → repo `jaime7981/homelab-ops`, resource path `komodo/sync.toml` → *Refresh* → review the diff → *Execute*.
3. GitHub repo → Settings → Webhooks → add the URL Komodo shows on the Sync/Stack (`https://komodo.DOMAIN/listener/github/...`), secret = `KOMODO_WEBHOOK_SECRET`, content type JSON, push events.
4. Set `KOMODO_OIDC_ENABLED=true` + client ID/secret in `core/.env`, then `docker compose up -d komodo-core`. "Log in with OIDC" appears.

## 7. Cloudflare Access

Create the application and policies in [access.md § Cloudflare Access](access.md#1-cloudflare-access-public-path).
Test from your phone **with Wi-Fi off and Tailscale off**: `https://dash.DOMAIN` → Access → authentik → Homepage.

## 8. CrowdSec

```bash
docker exec crowdsec cscli bouncers list     # "traefik" should be listed
docker exec crowdsec cscli metrics           # traefik + auth.log parsers reading lines
# Optional: free console with the community blocklist and a nice UI
docker exec crowdsec cscli console enroll <key from app.crowdsec.net>
```

Homepage widget user:
`docker exec crowdsec cscli machines add homepage --password '<pw>' -f /dev/null` → `homepage.env`.

## 9. Notifications

See [operations.md § Notifications](operations.md#notifications). Create the ntfy admin + token, install the ntfy phone app, point Komodo, Beszel and Uptime Kuma at it.

## 10. Dashboard

Fill `homepage.env` (API keys from Komodo, Beszel user, authentik token, CrowdSec password), then edit `homepage/services.yaml` for your machines and sites. `docker compose restart homepage`. See [dashboard.md](dashboard.md).

## 11. Uptime Kuma

`https://status.lab.DOMAIN` → create admin → add monitors (see [operations.md](operations.md#websites-and-tunnels)). Create a **status page** with slug `homelab` for the Homepage widget.

## Upgrading the core

Image tags in `core/compose.yaml` are either pinned (`traefik:v3.5`, `komodo-core:2`, `AUTHENTIK_TAG`) or `latest`.

```bash
cd /opt/homelab-ops && git pull
cd core && docker compose pull && docker compose up -d
docker image prune -f
```

For authentik, read the release notes before bumping `AUTHENTIK_TAG`, and only move one minor version at a time.

Once everything works, you can also add the core itself as a Komodo stack (path `core/`) so upgrades are one click. Keep the `.env` on the host, and add `komodo.skip` to services you never want Komodo to stop.
