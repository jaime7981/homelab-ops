# The dashboard (Homepage)

`https://dash.DOMAIN` (anywhere, via Cloudflare Access) or `https://dash.lab.DOMAIN` (tailnet).

## Layout

| Section | What you see | Click goes to |
|---|---|---|
| Top bar | Core host CPU / RAM / disk, time, search | — |
| **Fleet** | Komodo: servers / stacks up vs down. Beszel: systems, alerts. Uptime Kuma: sites up / down, uptime %. | Each tool |
| **Security** | authentik: users, logins, failed logins (24h). CrowdSec: alerts and bans (24h). | authentik admin, CrowdSec console, Traefik |
| **Servers** | One tile per machine | Cockpit on that machine |
| **Websites** | Live status + response time per public site | The site |

Everything that needs action (deploy, restart, logs, shell, update) is one click away in Komodo or Cockpit, behind the same login.

## Files

All under `core/homepage/`, mounted into the container. Changes apply on reload; no restart needed for most of them.

| File | Purpose |
|---|---|
| `services.yaml` | Tiles and widgets |
| `widgets.yaml` | Top bar |
| `settings.yaml` | Title, theme, section layout |
| `bookmarks.yaml` | Links to Cloudflare, Tailscale, GitHub |
| `docker.yaml` | Read-only Docker access (via `socket-proxy`) for container status dots |

Secrets for widgets are in `core/homepage.env` (git-ignored) and referenced as `{{HOMEPAGE_VAR_NAME}}`.

## Widget credentials

| Widget | Create in | `homepage.env` |
|---|---|---|
| Komodo | Komodo → Settings → API keys (a dedicated read-only user is better) | `HOMEPAGE_VAR_KOMODO_KEY`, `_SECRET` |
| Beszel | Beszel → create user `homepage` (role readonly) | `HOMEPAGE_VAR_BESZEL_USER`, `_PASS` |
| Uptime Kuma | Status page with slug `homelab` (no key needed) | — |
| authentik | Directory → Tokens → API token for a service account | `HOMEPAGE_VAR_AUTHENTIK_TOKEN` |
| CrowdSec | `cscli machines add homepage ...` | `HOMEPAGE_VAR_CROWDSEC_USER`, `_PASS` |

## Adding a tile

```yaml
- Websites:
    - Property admin:
        icon: mdi-home-city
        href: https://properties.DOMAIN
        siteMonitor: https://properties.DOMAIN
        description: Family property management
```

Icons: names from https://dashboardicons.com (`plex.png`) or Material Design (`mdi-*`).
More widgets (Plex, Tautulli, qBittorrent, …): https://gethomepage.dev/widgets/

Show a container's status dot (for containers on the core host):

```yaml
        server: core-docker
        container: <container_name>
```

## Family access

To give family read-only access to the dashboard only:
1. authentik: user in group `family`.
2. Cloudflare Access: add their emails to a policy on `dash.DOMAIN` only (a separate Access application).
3. Komodo/Beszel stay restricted to `admins` via authentik application policies.

## Later: a custom portal

If you find yourself repeating the same multi-click actions (pull a model and reload llama.cpp, rotate an AI API key, redeploy a set of stacks), build a small app that calls the Komodo, Beszel and Uptime Kuma APIs. Deploy it as a stack behind the same `secured-public@file` / `secured-tailnet@file` middlewares. The `X-authentik-username` header it receives tells it who's calling, so it needs no login code of its own.
