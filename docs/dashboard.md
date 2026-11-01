# The dashboard (Homepage)

`https://dash.ailabs.cl`, from anywhere, through the `mgmt` tunnel and Cloudflare Access.

## Layout

| Section | What you see | Click goes to |
|---|---|---|
| Top bar | Core host CPU / RAM / disk, time, search | — |
| **Fleet** | Komodo: servers / stacks up vs down. Beszel: systems, alerts. Gatus: endpoints up / down, uptime. | Each tool |
| **Security** | CrowdSec: alerts and bans (24h). authentik logins (if enabled). | CrowdSec console, Traefik |
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
| Gatus | Nothing (reads the public API on the Docker network) | — |
| authentik (if enabled) | Directory → Tokens → API token for a service account | `HOMEPAGE_VAR_AUTHENTIK_TOKEN` |
| CrowdSec | `cscli machines add homepage ...` | `HOMEPAGE_VAR_CROWDSEC_USER`, `_PASS` |

## Adding a tile

```yaml
- Websites:
    - Property admin:
        icon: mdi-home-city
        href: https://realestate.DOMAIN
        siteMonitor: https://realestate.DOMAIN
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
1. Cloudflare Access: a separate Access application for `dash.DOMAIN` (and `status.DOMAIN` if useful) with a policy that includes their emails.
2. Application A (Komodo, Beszel, Traefik) keeps only your email, so they can't reach the tools.
3. With authentik enabled you can manage this as groups (`family`, `admins`) instead.

## Later: a custom portal

If you find yourself repeating the same multi-click actions (pull a model and reload llama.cpp, rotate an AI API key, redeploy a set of stacks), build a small app that calls the Komodo, Beszel and Gatus APIs. Deploy it as a stack behind the same `secured-public@file` / `secured-tailnet@file` middlewares. The `Cf-Access-Authenticated-User-Email` header (or `X-authentik-username` with authentik) tells it who's calling, so it needs no login code of its own.
