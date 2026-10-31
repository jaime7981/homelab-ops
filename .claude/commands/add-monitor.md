---
description: Monitor an app or service without migrating it to Komodo (dashboard + uptime + alerts)
argument-hint: <name> <url-or-host> [machine] [health path / keyword]
---

Add monitoring for: $ARGUMENTS

Use this for things you only want to watch: an app started by hand, a non-Docker service (systemd, llama.cpp), an external site. To also deploy it from Git, use `/add-app` instead.

1. Work out what's missing: display name, URL or host, which machine it runs on (if it's one of ours), a health endpoint or a keyword that only appears when it's healthy, and whether it's public or tailnet-only.
2. If it runs on a fleet machine that isn't in `core/homepage/services.yaml` under **Servers** yet, say so and suggest `/add-server` first: the machine's agents give container logs/status in Komodo and CPU/RAM/disk in Beszel.
3. Edit `core/homepage/services.yaml`:
   - Public URL → under **Websites**, with `href`, `siteMonitor` (the health URL if there is one), an icon (`mdi-*` or a dashboardicons.com name) and a description.
   - Tailnet-only service → under **Websites** with the `http://<machine>:<port>` URL. Homepage reaches it only if the Pi is on the tailnet (it is).
   - If gethomepage.dev has a widget for this app (Plex, Tautulli, Immich, …), add a commented-out `widget:` block with the needed `HOMEPAGE_VAR_*` names, and add those names (empty) to `core/homepage.env.example`.
4. Validate the YAML, commit (`Monitor <name>`) and push once the user agrees. Homepage reloads by itself.
5. Give the user the exact Uptime Kuma monitor to create:
   - Type: **HTTP(s) - Keyword** (or **HTTP(s)** / **Ping** / **TCP Port** for a service without a page), URL/host, keyword, interval 60 s, retries 2, cert expiry notification on for HTTPS, notification `homelab-uptime`.
   - Add it to the `homelab` status page so the dashboard widget counts it.
   - If the service runs in a container on a fleet machine: Komodo → Server → Containers shows it already; suggest enabling server alerts there.
