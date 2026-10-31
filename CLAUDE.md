# homelab-ops: notes for Claude

Infrastructure-as-code for Jaime's homelab. The **Raspberry Pi (`raspi`) is the management core**: it runs `core/` (Traefik, authentik, Komodo, Beszel, Uptime Kuma, ntfy, Homepage, CrowdSec, cloudflared) plus `node/`. Every other server runs only `node/` (agents) and its apps from `stacks/`.

Reply to the user in Spanish. Keep code, comments and docs in English, matching the repo.

## Where things are

| Path | What |
|---|---|
| `core/compose.yaml`, `core/.env` | Management core (Pi only). `.env` holds secrets |
| `node/compose.yaml`, `node/.env` | Agents on every machine (Komodo periphery, Beszel agent, optional CrowdSec) |
| `stacks/<machine>/<app>/compose.yaml` | One folder per app, deployed by Komodo |
| `komodo/sync.toml` | Which stack runs on which server. Applied from Komodo → Syncs → Execute |
| `core/homepage/services.yaml` | Dashboard tiles (Servers, Websites) |
| `ansible/inventory.ini` | Fleet inventory (git-ignored; template is `inventory.example.ini`) |
| `docs/` | Step-by-step guides. **Follow them; don't invent a different procedure** |

Guides by task: core install `docs/deploy.md` · new server `docs/add-machine.md` · new app `docs/add-app.md` · dashboard `docs/dashboard.md` · alerts, runbooks `docs/operations.md` · access model `docs/access.md`.

## Rules

1. **Secrets never go in Git.** Don't read, print or `cat` `.env`, `homepage.env` or `node/.env`. To check if a key is set, use `grep -c '^KEY=.\+' file`. In compose files use `${VAR}`; values live in the Komodo stack Environment as `VAR=[[SECRET_NAME]]` (Komodo → Settings → Variables, marked secret).
2. **Nothing is published on the LAN or internet.** Admin/private ports bind to the Tailscale IP: `${TAILSCALE_IP}:PORT:PORT`. Public apps use a `cloudflared` sidecar with their own tunnel (pattern A in `stacks/_template`). Docker-published ports bypass ufw, so never use a bare `PORT:PORT`.
3. Every hostname on the `mgmt` tunnel points to `http://traefik:8080`, never directly to a container (that would skip CrowdSec + authentik).
4. Pin image versions in `stacks/` (`app:1.4.2`, not `latest`). Add a `healthcheck`. App data goes under `/srv/<app>/` on the host.
5. Machine names = Tailscale MagicDNS names = `NODE_NAME` in `node/.env` = `server` in `sync.toml`. The core is `raspi`.
6. Git is the source of truth: change files, commit, push. Komodo redeploys stacks on push (webhook). Don't `docker compose up` an app by hand on a server that Komodo manages, except to debug.
7. Before running anything destructive (`down -v`, `volume rm`, `prune -a`, deleting a stack/server, changing firewall rules) explain what it does and wait for confirmation.

## What Claude can do vs what the user must do

Claude can: edit files in this repo, commit and push, run `docker compose` / `docker logs` / `docker exec` on the machine it runs on, `ssh <machine>` over Tailscale if available, diagnose.

The user must do these in a browser (Claude gives exact values and clicks, then waits):
- Cloudflare Zero Trust: tunnels, public hostnames, Access applications
- Komodo: onboarding keys, Variables (secrets), Syncs → Execute, alerters
- Beszel: *Add system* (gives `KEY` / `TOKEN`), alert thresholds
- Uptime Kuma: monitors, notifications, status page
- authentik: users, providers, tokens
- Tailscale admin console: tags, key expiry

After file changes, always finish with a short checklist of the remaining manual steps.

## Useful commands (on the Pi)

```bash
cd /opt/homelab-ops/core && docker compose ps            # core health
docker compose logs --tail=100 <service>                 # e.g. komodo-core, cloudflared, traefik
docker compose -f /opt/homelab-ops/node/compose.yaml ps  # agents on this machine
docker exec crowdsec cscli metrics                      # also: cscli decisions list
docker compose config -q                                 # validate a compose file (run in its folder)
```

Validate before committing: `docker compose -f <file> config -q` for compose files (set dummy env vars if needed), `bash -n` for scripts.

## Raspberry Pi specifics

- 64-bit OS only, Docker data on SSD. The core uses ~2–2.5 GB RAM; on a 4 GB Pi use zram and `mem_limit`s.
- If `ghcr.io/ferretdb/postgres-documentdb` won't pull on ARM, replace `komodo-pg` + `komodo-ferretdb` with one MongoDB service (`mongo:7` on Pi 5, `mongo:4.4` on Pi 4) and point `KOMODO_DATABASE_ADDRESS` at it.
- `scripts/bootstrap-node.sh` installs rsyslog (CrowdSec reads `/var/log/auth.log`) and sets `ip_nonlocal_bind` so containers bound to the Tailscale IP start even if Docker comes up before Tailscale.

## Slash commands

- `/add-server <name> [tailscale-ip]`: join a new machine to the fleet
- `/add-app <machine> <app> [details]`: add or migrate an app as a Komodo stack
- `/add-monitor <name> <url-or-host>`: monitor something without migrating it to Komodo
