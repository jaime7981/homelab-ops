# Add an app (stack)

Every app is a folder `stacks/<machine>/<app>/` with a `compose.yaml`, registered in `komodo/sync.toml`. Komodo deploys it on that machine and redeploys on every push.

## 1. Choose how it's exposed

| Pattern | Use for | How |
|---|---|---|
| **A. Public** | Website, property admin, AI API | `cloudflared` sidecar with its own tunnel token. No ports. Optionally add a Cloudflare Access app in front (e.g. property admin for family only). |
| **B. Tailnet only** | Internal tools, admin UIs, APIs only you call | Publish on the machine's Tailscale IP: `${TAILSCALE_IP}:8080:8080` |
| **C. Internal** | Databases, workers | No `ports:` at all; other containers reach it by service name |

Rule of thumb: if it has no login of its own, it must not be pattern A without Cloudflare Access in front.

## 2. Write the compose file

```bash
cp -r stacks/_template stacks/<machine>/<app>
$EDITOR stacks/<machine>/<app>/compose.yaml
```

- Pin the image version.
- Reference secrets as `${VAR}`; never write values here.
- Add a `healthcheck`, so Komodo shows the real state.
- Bind-mount data under `/srv/<app>/` on the host so backups have one place to look.

## 3. Register it in Komodo

Add to `komodo/sync.toml`:

```toml
[[stack]]
name = "<app>"
tags = ["<machine>"]
[stack.config]
server = "<machine>"
git_provider = "github.com"
repo = "jaime7981/homelab-ops"
branch = "main"
run_directory = "stacks/<machine>/<app>"
webhook_enabled = true
environment = """
DATABASE_URL=[[APP_DATABASE_URL]]
TUNNEL_TOKEN=[[APP_TUNNEL_TOKEN]]
"""
```

Create the referenced secrets in Komodo → Settings → **Variables** (mark as *secret*).

## 4. Public apps: tunnel + hostname

Cloudflare Zero Trust → Networks → Tunnels → *Create* `<app>` → copy the token into the Komodo secret.
*Public hostname*: `<sub>.DOMAIN` → `http://app:<port>` (the service name inside the stack).

Optional Access app for it (e.g. property admin: allow family emails only, country Chile).

## 5. Ship it

```bash
git add stacks/<machine>/<app> komodo/sync.toml
git commit -m "Add <app> on <machine>"
git push
```

Komodo → Syncs → *Execute* (first time only, to create the stack) → Stacks → `<app>` → *Deploy*.
After that, every push that changes the folder redeploys it automatically.

## 6. Monitor it

- **Uptime Kuma:** HTTP(s) monitor on the public URL, *keyword* check if it has a health endpoint, certificate expiry notification on.
- **Homepage:** add it under **Websites** with `siteMonitor:`, or under its machine.
- **Komodo:** stack → enable alerts for *unhealthy* / *stopped*.

## Migrating your existing apps

For each app currently started by hand:

1. Copy its existing `docker-compose.yml` into `stacks/<machine>/<app>/compose.yaml`, moving secrets to `${VAR}`.
2. In Komodo, create the stack with the **same project name** as the running one (the folder name compose used, or `name:`). Komodo then adopts the running containers instead of creating duplicates.
3. *Deploy* once from Komodo, check, push.

Suggested order: personal website → property admin → AI gateway → Plex.
