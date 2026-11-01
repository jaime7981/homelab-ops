# homelab-ops

One place to run, watch and secure every machine and app in the homelab:
Plex, the local AI API (llama.cpp), the personal website, the family property admin app, and whatever comes next.

**One login, one dashboard**, reachable only through a Cloudflare Tunnel + Access (no ports open on the house network), with alerts on your phone. Tailscale is used for SSH and agent traffic. Uptime checks are files in Git (`core/gatus/`), so adding a monitor is a commit.

```mermaid
flowchart TB
  subgraph Access["Access layer"]
    CFA["Cloudflare Access<br/>login · country · IP rules"]
  end
  CFA -->|"mgmt tunnel"| TR
  TR["Traefik<br/>reverse proxy · CrowdSec · optional authentik SSO"]
  TR --> HP["Homepage<br/>unified dashboard"]
  HP --> KO["Komodo<br/>deploy · logs · shell"]
  HP --> BE["Beszel<br/>host + GPU metrics"]
  HP --> GA["Gatus<br/>uptime checks as code"]
  HP --> CS["CrowdSec<br/>attacks blocked"]
  KO & BE & CS --> AG["Agents on every PC<br/>Komodo periphery · Beszel agent · CrowdSec"]
  TS["Tailscale<br/>SSH · agent traffic"] -.-> AG
  AG --> NT["ntfy / Telegram alerts"]
```

## What covers what

| Need | Tool | Where |
|---|---|---|
| Apps spread over several machines | Komodo (core + periphery agent per PC) | `core/`, `node/` |
| Deploy / redeploy / manual updates of apps | Komodo stacks from this repo (`git push` → redeploy) | `stacks/`, `komodo/sync.toml` |
| OS updates | unattended-upgrades (security, automatic) + Ansible `update.yml` (manual) | `ansible/` |
| Logs | Komodo (per container), Cockpit (systemd/journal, e.g. llama.cpp) | |
| Health metrics | Beszel: CPU, RAM, disk, network, temps, GPU, per-container | `core/`, `node/` |
| Websites & services up/down | Gatus: HTTP, keyword, cert expiry, TCP, ping; monitors are YAML files | `core/gatus/`, `offsite/` |
| Security checks | CrowdSec (bans), Trivy (image CVEs), Lynis (host audit) | `ansible/playbooks/audit.yml`, `scripts/` |
| Emergency / dev SSH | Tailscale SSH; Komodo web terminal; Cockpit terminal | `docs/operations.md` |
| Login control | Cloudflare Access (email code / Google, login log). Optional authentik for MFA/passkeys and groups | `docs/access.md` |
| IP & region filtering | Cloudflare Access policies + Traefik IP allowlist | `docs/access.md` |
| Notifications | ntfy (+ Telegram), fed by Komodo, Beszel, Gatus, scripts | `core/` |
| Single view | Homepage with live widgets for all of the above | `core/homepage/` |

## Repository layout

```
core/       Management core: Traefik, Komodo, Beszel, Gatus, ntfy, Homepage, CrowdSec, cloudflared (+ optional authentik)
node/       Agents installed on every machine (Komodo periphery, Beszel agent, CrowdSec agent)
offsite/    Uptime Kuma for a VPS outside the house (alerts when the whole house is down)
stacks/     Your apps, one compose file per app, grouped by machine. Deployed by Komodo.
komodo/     Komodo resource sync (which stack runs on which machine)
ansible/    Bootstrap, fleet-wide OS updates, security audit
scripts/    bootstrap-node.sh, gen-secrets.sh, scan-images.sh
docs/       Everything below
CLAUDE.md   Rules for Claude Code; .claude/commands/ has /add-server, /add-app, /add-monitor
```

## Docs

| | |
|---|---|
| [Architecture](docs/architecture.md) | Layers, hostnames, ports, data flows, design decisions |
| [Tools](docs/tools.md) | Every app used, what it does here, links |
| [Access](docs/access.md) | Cloudflare Access (SSO, country, IP), Tailscale, authentik, SSH keys |
| [Deploy the core](docs/deploy.md) | First-time install, step by step |
| [Add a machine](docs/add-machine.md) | New PC/server joins the fleet |
| [Add an app](docs/add-app.md) | New stack on an existing machine, public or private |
| [Dashboard](docs/dashboard.md) | Homepage: layout, widgets, adding tiles |
| [Operations](docs/operations.md) | Updates, logs, emergency SSH, security checks, alerts, backups, runbooks |
| [Local AI / llama.cpp](docs/llama-cpp.md) | How the AI host fits in, and what's custom |

## Quick start

```bash
# On the core host (already on Tailscale):
git clone https://github.com/jaime7981/homelab-ops.git /opt/homelab-ops
cd /opt/homelab-ops/core
cp .env.example .env && cp homepage.env.example homepage.env
../scripts/gen-secrets.sh        # paste into .env
$EDITOR .env
docker compose up -d
```

Then follow [docs/deploy.md](docs/deploy.md) from step 4 onwards.

## Hostnames at a glance

| Service | URL (tunnel + Cloudflare Access) |
|---|---|
| Dashboard | `https://dash.ailabs.cl` |
| Komodo | `https://komodo.ailabs.cl` |
| Beszel | `https://beszel.ailabs.cl` |
| Gatus (status) | `https://status.ailabs.cl` |
| authentik (optional) | `https://auth.ailabs.cl` |
| ntfy | `https://ntfy.ailabs.cl` (ntfy tokens, no Access) |
| Traefik | `https://traefik.ailabs.cl` |
| Cockpit (per machine) | `https://<machine>:9090` over Tailscale |
