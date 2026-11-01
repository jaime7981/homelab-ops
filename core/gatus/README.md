# Uptime checks (Gatus)

Everything Gatus monitors lives in this folder, so adding or changing a monitor is a Git change.
Gatus merges every `*.yaml` here (endpoint lists are appended) and reloads on its own when a file changes.

```
config.yaml              UI, storage, ntfy alerting (topic homelab-uptime)
endpoints/core.yaml      The management core (tunnel, Komodo, Beszel, ntfy)
endpoints/machines/      One file per machine: ping over Tailscale
endpoints/apps/          One file per app or site
```

Status page: `https://status.DOMAIN`. Alerts: ntfy topic `homelab-uptime` (machines with priority 4).

## Add a monitor

1. Create `endpoints/apps/<app>.yaml` (or `endpoints/machines/<name>.yaml`) from a snippet below.
2. `./scripts/check-gatus.sh`: starts Gatus against this folder and prints any error.
3. Commit and push. The Pi picks up the change when its checkout is updated (`git pull` in `/opt/homelab-ops`); Gatus reloads by itself.
4. Check `docker logs gatus --since 2m` on the Pi. An invalid change is ignored (the last good config keeps running) and logged there.

Remove a monitor: delete its file. Pause one: `enabled: false`.

## Snippets

Public website or API:

```yaml
endpoints:
  - name: My site
    group: websites
    url: https://site.${DOMAIN}
    interval: 1m
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == pat(*text only shown when healthy*)"   # catches error pages served with 200
      - "[CERTIFICATE_EXPIRATION] > 240h"
    alerts:
      - type: ntfy
```

JSON health endpoint:

```yaml
    url: https://api.${DOMAIN}/health
    conditions:
      - "[STATUS] == 200"
      - "[BODY].status == ok"
      - "[RESPONSE_TIME] < 2000"
```

Service on a machine, over the tailnet (Tailscale names resolve inside the Gatus container):

```yaml
endpoints:
  - name: Grafana
    group: apps
    url: http://ai-pc:3000/api/health
    interval: 2m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: ntfy
```

Port only (database, SSH, anything without HTTP):

```yaml
    url: tcp://ai-pc:5432
    conditions:
      - "[CONNECTED] == true"
```

Machine reachable:

```yaml
endpoints:
  - name: ai-pc
    group: machines
    url: icmp://ai-pc
    interval: 1m
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: ntfy
```

## Notes

- `${DOMAIN}` and `${NTFY_TOKEN}` come from the `gatus` service environment (`core/compose.yaml`). Any other `$` must be written `$$`.
- Groups in use: `core`, `machines`, `websites`, `apps`. The dashboard and alerts are grouped by them.
- Sites behind Cloudflare Access: an anonymous check sees the Access login page (status 200). That proves the tunnel and Cloudflare are up, not the app. To check the app itself, use a public health path that bypasses Access (an Access *Bypass* policy on `/health`) or check it over the tailnet.
- Gatus checks from inside the house. If the house loses internet, nothing here can alert you: use `offsite/` on a VPS for that.
- All conditions: https://github.com/TwiN/gatus#conditions
