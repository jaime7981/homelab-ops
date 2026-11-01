# Architecture

## Principles

1. **Use existing tools; write code only for the gaps.** Monitoring, auth, deploy and alerting are solved problems. Custom code is limited to the llama.cpp admin layer and, later, an optional custom portal.
2. **Nothing admin-related is open to the internet.** No port forwarding on the router. Admin traffic arrives only through a Cloudflare Tunnel (outbound connection); Tailscale is for SSH and agents.
3. **Defense in depth on the tunnel path.** Cloudflare Access (identity + country + IP) → CrowdSec → Traefik IP allowlist → the tool's own login where it has one (Komodo, Beszel). Optional authentik SSO/MFA adds one more layer on your own hardware.
4. **Agents dial out.** Komodo periphery, Beszel agent and CrowdSec agents connect *to* the core over Tailscale. New machines don't need inbound ports.
5. **Git is the source of truth** for app definitions (`stacks/`). Secrets live in Komodo / `.env` files, never in Git.
6. **Config as code wherever the tool allows it.** Stacks (`stacks/`, `komodo/sync.toml`), uptime checks (`core/gatus/`), dashboard (`core/homepage/`) and middlewares are files in Git, so an agent or a PR can change them. Only secrets and a few one-time UI steps live outside.

## Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ 1. Access        Cloudflare Access (public)      Tailscale (VPN)       │
│                  SSO, country, IP, device         WireGuard, ACLs, SSH  │
├──────────────────────────────────────────────────────────────────────┤
│ 2. Edge          cloudflared → Traefik           Traefik :443 on TS IP │
│                  CrowdSec bouncer · IP allowlist · (authentik fwd-auth) │
├──────────────────────────────────────────────────────────────────────┤
│ 3. Unified view  Homepage (widgets + links)                            │
├──────────────────────────────────────────────────────────────────────┤
│ 4. Tools         Komodo · Beszel · Gatus · CrowdSec · ntfy              │
├──────────────────────────────────────────────────────────────────────┤
│ 5. Agents        komodo-periphery · beszel-agent · crowdsec-agent       │
│    (every PC)    + Cockpit, unattended-upgrades, ufw, Tailscale SSH     │
├──────────────────────────────────────────────────────────────────────┤
│ 6. Apps          stacks/<machine>/<app> deployed by Komodo              │
│                  public apps expose themselves with their own tunnel    │
└──────────────────────────────────────────────────────────────────────┘
```

## Machines

| Role | Example name | Runs |
|---|---|---|
| Management core | `jaime-pi` | `core/` + `node/` (pick the most reliable, always-on machine) |
| App hosts | `media-pc`, `ai-pc`, … | `node/` + their stacks |
| Off-site watcher (optional) | `vps` | `offsite/` |

The core can also run apps. It's just a machine with extra services.

## Entry path: Cloudflare Tunnel only

```
Browser ──HTTPS──► Cloudflare edge ──► Cloudflare Access policy
                                         (email OTP / authentik, allowed countries, allowed IPs)
                    ──► mgmt tunnel ──► cloudflared (core compose) ──HTTP──► Traefik "web" :8080
                    ──► crowdsec ─► public-allowlist ─► authentik ─► app
```

- Same pattern as the apps: `cloudflared` runs inside the compose project. The host publishes no web ports.
- TLS terminates at Cloudflare. cloudflared → Traefik is plain HTTP on the private `proxy` Docker network.
- Every hostname in the `mgmt` tunnel points at `traefik:8080`; pointing one at a container directly would skip CrowdSec and authentik.
- The real client IP arrives as `CF-Connecting-IP` / `X-Forwarded-For`. Traefik trusts them only from `172.30.0.0/16` (the `proxy` network).
- Tailscale carries SSH and agent traffic, not browser traffic. If the tunnel is down, Komodo (`:9120`) and Beszel (`:8090`) are still reachable on the core's Tailscale IP.
- Optional: `core/compose.tailnet.yaml` adds a VPN-only browser path (`*.lab.DOMAIN` on the Tailscale IP, Let's Encrypt wildcard). Off by default.

## Ports

All admin ports bind to the **Tailscale IP only** (`${TAILSCALE_IP}:port`), so they're never reachable from the LAN or internet.

| Port | Service | Who connects |
|---|---|---|
| 443 | Traefik `tailnet` entrypoint (only with `compose.tailnet.yaml`) | You, over Tailscale |
| 9120 | Komodo core | Periphery agents (outbound WebSocket) |
| 8090 | Beszel hub | Beszel agents |
| 8081 | CrowdSec Local API | CrowdSec agents on other PCs |
| 9090 | Cockpit (every PC) | You, over Tailscale |
| 8080 | Traefik `web` entrypoint | cloudflared only (Docker network, not published) |

Docker-published ports bypass `ufw`. That's why they're bound to the Tailscale IP rather than relying on the firewall.

## Authentication model

| Tool | How you log in | Why |
|---|---|---|
| Homepage, Gatus, Traefik | Cloudflare Access only (+ authentik forward-auth if enabled) | No built-in login worth having; Access already checks identity, country, IP |
| Beszel | Cloudflare Access + its own login | Built-in users; also used by the Homepage widget |
| Komodo | Cloudflare Access + its local login (+ OIDC → authentik if enabled) | Local admin also works over Tailscale as break-glass |
| authentik *(optional)* | its own login + MFA/passkey | It *is* the identity provider |
| ntfy | ntfy users/tokens (deny-all default) | Phone app can't do SSO redirects |
| Komodo webhooks (`/listener`) | HMAC secret (`KOMODO_WEBHOOK_SECRET`) | GitHub calls it, not a person |
| SSH | Tailscale SSH (identity-based), or keys only | No passwords anywhere |

## Data flows

| Flow | Path |
|---|---|
| Deploy | `git push` → GitHub webhook → `komodo.DOMAIN/listener` → Komodo core → periphery on target PC → `docker compose up` |
| Metrics | beszel-agent (each PC) → Beszel hub :8090 over Tailscale |
| Logs | Komodo reads container logs via periphery on demand. Cockpit reads journald on each PC. |
| Security events | Traefik access log + auth.log → CrowdSec engine → decisions → Traefik bouncer blocks the IP |
| Uptime checks | Gatus (core) → HTTP/ICMP/TCP to sites, tunnels and machines (Tailscale names via MagicDNS) |
| Alerts | Komodo / Beszel / Gatus / scripts → ntfy topic → phone (and Telegram if configured) |

## Persistent data

| Volume | Contents | Back up? |
|---|---|---|
| `authentik-db`, `core/authentik/` | Users, MFA devices, policies (only with authentik) | Yes |
| `komodo-pg`, `komodo-backups` | Komodo servers, stacks, secrets, history | Yes (Komodo writes its own DB backups to `komodo-backups`) |
| `beszel-data` | Metrics history, alert rules | Optional |
| `gatus-data` | Check history (monitors themselves are in Git) | No |
| `ntfy-etc` | ntfy users/tokens | Yes (small) |
| `traefik-certs` | Let's Encrypt account + certs | No (re-issued automatically) |
| `crowdsec-*` | Decisions, hub items | No |

See [operations.md](operations.md#backups).
