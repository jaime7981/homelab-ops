# Tools

Every tool in the stack, why it's here, and where to configure it.

## Edge & access

### Cloudflare Tunnel (`cloudflared`)
Outbound-only connection from the house to Cloudflare. Public hostnames map to internal services without opening router ports.
- Admin tunnel: `cloudflared` service in `core/compose.yaml` → Traefik.
- App tunnels: one `cloudflared` sidecar per public app (website, property admin, AI API), as you already do. See `stacks/_template`.
- Docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/

### Cloudflare Access
Zero Trust gate in front of public admin hostnames: identity (email OTP, Google, or authentik via OIDC), country, IP range, device posture. Free for up to 50 users.
- Configured in the Cloudflare dashboard. See [access.md](access.md).

### Tailscale
WireGuard mesh VPN between your devices and every PC. Also provides **Tailscale SSH** (SSH authenticated by your Tailscale identity, with ACLs and session logs) and MagicDNS names (`media-pc`, `ai-pc`).
- Installed on the host by `scripts/bootstrap-node.sh`.
- Docs: https://tailscale.com/kb/1193/tailscale-ssh

### Traefik v3
Reverse proxy for every management UI. Routes by hostname, applies middleware chains (CrowdSec, IP allowlist, SSO, headers), and (optionally) TLS certs for the VPN-only `*.lab.DOMAIN` path.
- `core/compose.yaml` (static config as flags), `core/traefik/dynamic/*.yml` (middlewares, allowlist).

### authentik
Identity provider: users, groups, MFA (TOTP, WebAuthn/passkeys), login/event log. Used as forward-auth for Traefik and as an OIDC provider for Komodo (and optionally Cloudflare Access).
- `core/compose.yaml` (`authentik-*` services). Admin UI: `https://auth.DOMAIN/if/admin/`.
- Docs: https://docs.goauthentik.io

### CrowdSec
Reads Traefik access logs and SSH auth logs, detects attacks (brute force, scanners, CVE probes), and bans IPs through the Traefik bouncer plugin. Also pulls the community blocklist.
- Engine: `crowdsec` in `core/`. Agents: `crowdsec-agent` profile in `node/`.
- `docker exec crowdsec cscli decisions list` / `cscli alerts list`.

## Fleet management

### Komodo
Multi-server Docker control plane. One core, one periphery agent per machine.
- Stacks from Git (this repo), deploy on push via webhook, redeploy/restart/pull buttons
- Container logs, stats, web terminal into containers and hosts
- Shows when newer images are available
- Alerters (send to ntfy), Procedures and Actions (scripted multi-step operations)
- Resource sync from `komodo/sync.toml`
- Docs: https://komo.do

### Cockpit
Web console per machine, over Tailscale: systemd services (e.g. `llama-server`), journald logs, package updates, login history (`last`), storage, terminal.
- Installed by bootstrap. URL: `https://<machine>:9090`.

### Ansible
Fleet-wide operations from your laptop over Tailscale: bootstrap a new PC, update all OSes one by one, run security audits.
- `ansible/playbooks/{bootstrap,update,audit}.yml`.

## Observability

### Beszel
Lightweight metrics hub + agents: CPU, RAM, disk, network, temperatures, GPU, per-container usage. Threshold alerts (e.g. disk > 85%, CPU > 90% for 10 min, system down).
- Hub: `core/`, agents: `node/`. Docs: https://beszel.dev

### Uptime Kuma
Checks every public URL and tunnel from the outside (HTTP, keyword, SSL expiry, TCP, ping). Status page for the Homepage widget.
- In `core/`. Move or duplicate to `offsite/` on a VPS so you're alerted when the house is offline.

### Homepage
The unified view: tiles with live data from Komodo, Beszel, Uptime Kuma, authentik and CrowdSec, plus site monitors and links to every console.
- `core/homepage/*.yaml`. See [dashboard.md](dashboard.md).

### ntfy
Self-hosted push notifications. Every tool posts to a topic; the ntfy phone app shows them.
- `core/` (`ntfy` service). Docs: https://docs.ntfy.sh

## Security scanning

| Tool | What it checks | How to run |
|---|---|---|
| Trivy | CVEs in the images you run | `scripts/scan-images.sh` (weekly), or `audit.yml` |
| Lynis | Host hardening (SSH, kernel, packages, permissions) | `ansible-playbook playbooks/audit.yml` |
| CrowdSec | Live attacks | Always on |
| unattended-upgrades | Installs security patches daily | Always on |

## Why these and not others

| Alternative | Why not (for now) |
|---|---|
| Portainer / Dockge / Dockhand | Good single-host UIs. Komodo is stronger for several machines + Git deploys. Dockhand is a fine add-on if you want image scanning in a UI. |
| Prometheus + Grafana + Loki | More powerful, much more to maintain. Add later if Beszel's metrics or Komodo's logs aren't enough. |
| Wazuh | Full SIEM. Heavy for 2–4 machines. CrowdSec + Lynis + Trivy cover the practical risks. |
| Coolify / Dokploy | PaaS-style, opinionated about how apps are built and exposed. Less control over tunnels, GPUs and non-Docker services like llama.cpp. |
| Keycloak | More enterprise. authentik is easier and has Traefik forward-auth built in. |
