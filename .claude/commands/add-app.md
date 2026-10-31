---
description: Add a new app, or migrate an existing one, as a Komodo-managed stack
argument-hint: <machine> <app> [image / existing compose / how it should be exposed]
---

Add an app as a stack: $ARGUMENTS

Follow `docs/add-app.md` and the rules in `CLAUDE.md`.

1. Gather what's missing: target machine (must already be in the fleet, see `komodo/sync.toml` and `core/homepage/services.yaml`), app name, image or the existing `docker-compose.yml`, internal port, and exposure:
   - **A. Public** (website/API): `cloudflared` sidecar, own tunnel. No login of its own means it needs a Cloudflare Access app in front.
   - **B. Tailnet only**: `${TAILSCALE_IP}:PORT:PORT`.
   - **C. Internal**: no ports.
   If the app already runs on the server, ask for its current compose file and its **compose project name** (`docker compose ls` on that machine), so Komodo adopts the running containers instead of duplicating them.
2. Create `stacks/<machine>/<app>/compose.yaml` from `stacks/_template/compose.yaml`: keep only the chosen pattern, pin the image tag, use `${VAR}` for every secret, add a healthcheck, put data under `/srv/<app>/`. For a migration, keep the same project name (`name:` at the top if needed).
3. Add a `[[stack]]` block to `komodo/sync.toml` (copy the commented example). `environment` lists `VAR=[[SECRET_NAME]]` for each secret.
4. If it has a URL, add a tile to `core/homepage/services.yaml` under **Websites** with `siteMonitor:` (or under its machine if it's tailnet-only).
5. Validate: `docker compose -f stacks/<machine>/<app>/compose.yaml config -q` (export dummy values for the `${VAR}`s). Show the diff, then commit (`Add <app> on <machine>`) and push once the user agrees.
6. End with the manual checklist:
   - Komodo → Settings → Variables: create each `SECRET_NAME` (secret).
   - Public apps: Cloudflare tunnel `<app>` → token into the Komodo secret; public hostname `<sub>.ailabs.cl` → `http://<service>:<port>`; optional Access app.
   - Komodo → Syncs → Refresh → Execute, then Stacks → `<app>` → Deploy. Enable alerts for unhealthy/stopped.
   - Uptime Kuma: HTTP(s) - Keyword monitor, cert expiry on, 60 s interval, 2 retries.
