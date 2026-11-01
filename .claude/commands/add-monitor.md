---
description: Monitor an app, service, site or machine (Gatus check + dashboard tile), without migrating it to Komodo
argument-hint: <name> <url-or-host> [machine] [health path / keyword]
---

Add monitoring for: $ARGUMENTS

Monitors are files in `core/gatus/endpoints/`, so this is fully doable from the repo. Read `core/gatus/README.md` for snippets. Use this for anything you only want to watch: an app started by hand, a systemd service (llama.cpp), an external site. To also deploy it from Git, use `/add-app`.

1. Work out what's missing (ask only for what you can't infer): display name, URL or host and port, which machine it runs on, public or tailnet-only, and how to tell it's healthy (a health path, a JSON field, or a keyword only present when it works). If unsure what the page returns, fetch it once with `curl -s` and propose a keyword.
2. Write `core/gatus/endpoints/apps/<slug>.yaml` (or `machines/<name>.yaml` for a whole machine):
   - Public URL: `https://...` with `[STATUS] == 200`, a keyword or JSON condition, and `[CERTIFICATE_EXPIRATION] > 240h`. Use `${DOMAIN}` for ailabs.cl hostnames.
   - Tailnet service: `http://<machine>:<port>/...` by Tailscale name (resolves inside Gatus). Port only: `tcp://<machine>:<port>` + `[CONNECTED] == true`.
   - Group: `websites` (public), `apps` (tailnet), `machines`. Always add `alerts: [{type: ntfy}]` unless the user says it shouldn't page.
   - Sites behind Cloudflare Access: an anonymous check only sees the Access login page. Say so, and suggest a `/health` path with an Access Bypass policy or a tailnet check instead.
3. If it runs on a machine that isn't in the fleet yet (`core/gatus/endpoints/machines/`, `core/homepage/services.yaml` Servers), say so and suggest `/add-server`, since the agents add logs (Komodo) and CPU/RAM/disk (Beszel).
4. If it has a URL people open, add a tile to `core/homepage/services.yaml` (Websites, with `siteMonitor:`). If gethomepage.dev has a widget for the app, add it commented out and the `HOMEPAGE_VAR_*` names (empty) to `core/homepage.env.example`.
5. Run `./scripts/check-gatus.sh` and fix any error. Show the diff, then commit (`Monitor <name>`) and push once the user agrees.
6. Finish: if you're not on the Pi, tell the user to `git -C /opt/homelab-ops pull` there. Then check (or ask them to check) `docker logs gatus --since 2m` and `https://status.ailabs.cl`. No other manual step is needed.
