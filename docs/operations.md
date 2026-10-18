# Operations

Day-to-day tasks and what to do when something breaks.

## Where to do what

| Task | Go to |
|---|---|
| Is everything OK? | Homepage |
| Deploy / redeploy / restart an app | Komodo → Stacks |
| App logs | Komodo → Stack → Logs (search, follow) |
| Non-Docker service logs (llama.cpp, system) | Cockpit → Logs, or `journalctl -u <svc>` |
| Shell on a machine | Komodo → Server → Terminal, Cockpit → Terminal, or `ssh <machine>` (Tailscale) |
| CPU / RAM / disk / GPU history | Beszel |
| Who logged in / failed logins | authentik → Events. Tailscale console → Logs (SSH sessions). Cockpit → Logs (`sshd`). |
| Blocked attackers | `docker exec crowdsec cscli decisions list` / CrowdSec console |
| OS updates | Automatic (security). Manual: `ansible-playbook playbooks/update.yml` or Cockpit → Software updates |

## Updates

### Operating system
- **Security patches** install daily by themselves (`unattended-upgrades`). No reboots happen automatically.
- **Everything else, manually**, one machine at a time with reboot if needed:
  ```bash
  cd ansible
  ansible-playbook playbooks/update.yml                    # all machines, one by one
  ansible-playbook playbooks/update.yml --limit media-pc   # one
  ansible-playbook playbooks/update.yml -e reboot=false
  ```
- Check whether a reboot is pending: Cockpit shows a banner, or `ls /var/run/reboot-required`.

### Apps (stacks)
- Komodo marks stacks whose image has a newer version (*Update available*).
- **Pinned tag** (`app:1.4.2`): bump it in `stacks/.../compose.yaml`, push. Komodo redeploys.
- **`latest` tag**: Komodo → Stack → *Pull* + *Deploy*.
- Roll back: revert the commit and push, or redeploy the previous tag.

### Core services
See [deploy.md § Upgrading the core](deploy.md#upgrading-the-core).

## Logs

| Source | Retention | Where |
|---|---|---|
| Container stdout/stderr | 5 × 20 MB per container (Docker rotation set by bootstrap) | Komodo |
| systemd services, kernel, SSH | journald defaults | Cockpit, `journalctl` |
| Traefik access log | grows. Add logrotate for `core/traefik/logs/` or prune monthly | CrowdSec reads it |
| authentik events | 1 year (configurable) | authentik → Events |

Need searchable, long-term logs across machines? Add Loki + Grafana Alloy later. It's not needed day one.

## Emergency / dev access

Order of preference:

1. **Komodo terminal** (browser, from anywhere via `komodo.DOMAIN`). Good for "restart this, read that".
2. **Tailscale SSH**: `ssh jaime@<machine>`. Works with Cloudflare down, needs only the tailnet.
3. **Plain SSH with key** over LAN or tailnet, if the Tailscale daemon on that box is broken.
4. **Cockpit** `https://<machine>:9090` if SSH itself is broken but the box is up.
5. **Physical console.**

Dev work on a server: VS Code / Cursor *Remote-SSH* to `<machine>` works through Tailscale SSH unchanged.

## Security checks

| What | When | How |
|---|---|---|
| Attack blocking | Always | CrowdSec + Traefik bouncer |
| Security patches | Daily | unattended-upgrades |
| Image CVEs | Weekly | `scripts/scan-images.sh` on each host (cron), reports to ntfy |
| Host hardening | Monthly | `ansible-playbook playbooks/audit.yml` (Lynis hardening index, warnings) |
| Access review | Quarterly | Tailscale machines/keys, authentik users, Cloudflare Access policies, Komodo API keys |

Weekly scan cron (per host):

```bash
sudo tee /etc/cron.d/trivy-scan >/dev/null <<'EOF'
NTFY_URL=https://ntfy.DOMAIN/homelab-security
NTFY_TOKEN=tk_xxx
0 6 * * 1 root /opt/homelab-ops/scripts/scan-images.sh >/var/log/trivy-scan.log 2>&1
EOF
```

## Notifications

### ntfy setup (once)

```bash
docker exec -it ntfy ntfy user add --role=admin jaime
docker exec -it ntfy ntfy token add jaime        # -> tk_... for tools
```

Phone: install the **ntfy** app → add server `https://ntfy.DOMAIN`, log in as `jaime` → subscribe to topics:

| Topic | Fed by |
|---|---|
| `homelab` | Komodo (deploy failed, server down, update available), Beszel (thresholds, system down) |
| `homelab-uptime` | Uptime Kuma (site down/up, cert expiring) |
| `homelab-security` | authentik (failed logins), Trivy scans, CrowdSec (optional) |

### Wiring each tool

| Tool | Setting |
|---|---|
| Komodo | Settings → Alerters → New → endpoint **Ntfy**, URL `http://ntfy/homelab` + token. Choose alert types. |
| Beszel | Settings → Notifications → URL `ntfy://:tk_xxx@ntfy.DOMAIN/homelab` (Shoutrrr format). Then set per-system alerts. |
| Uptime Kuma | Settings → Notifications → type **ntfy**, server `http://ntfy`, topic `homelab-uptime`, access token. Enable as default for all monitors. |
| authentik | Events → Notification transports → *Webhook* `https://ntfy.DOMAIN/homelab-security` (add `Authorization: Bearer tk_xxx` via a webhook mapping). Rules → `login_failed`, `suspicious_request`. |
| Telegram (optional) | Uptime Kuma and Beszel support Telegram directly. Add it as a second channel for "site down" and "system down" only. |

Keep the noise low: page yourself only for *down* and *security*. Leave "update available" for the dashboard.

### Websites and tunnels

In Uptime Kuma, for each public site:
- **HTTP(s) - Keyword**: the URL, plus a word that only appears when the app is healthy (catches Cloudflare error pages that return 200).
- Certificate expiry notification: on.
- Interval 60s, retries 2.

For each machine: **Ping** monitor on its Tailscale IP.
For the AI API: HTTP monitor on its health endpoint (`/health` on llama.cpp's server).

## Backups

What matters is the state listed in [architecture.md § Persistent data](architecture.md#persistent-data) plus each app's `/srv/<app>/`.

Minimum viable:
1. Komodo already writes nightly DB backups to the `komodo-backups` volume.
2. Nightly `restic` from each host to an off-site target (Backblaze B2, another PC, a USB disk) for `/srv`, `/opt/homelab-ops/core/authentik`, and the Docker volumes `authentik-db`, `komodo-backups`, `kuma-data`, `ntfy-etc`. For Postgres, dump first (`pg_dump`) instead of copying live files.
3. `core/.env`, `homepage.env`, `node/.env`: store them in a password manager. They are the only files not in Git.

Test a restore once. A backup you haven't restored is a hope, not a backup.

---

## Runbooks

### A website is down
1. Uptime Kuma: which check failed (DNS, TLS, keyword, timeout)?
2. Komodo → the stack: are containers running and healthy? Read logs.
3. `cloudflared` sidecar logs: tunnel connected? Cloudflare Zero Trust → Tunnels: *Healthy*?
4. Machine itself up? Beszel / Tailscale ping.

### A machine is unreachable
1. Beszel and Komodo both show it down → the machine or its network, not one agent.
2. Tailscale console: last seen? If online in Tailscale but agents down → `ssh` in, `docker compose -f /opt/homelab-ops/node/compose.yaml ps`.
3. Not on Tailscale: power, network cable, then physical console.

### Disk almost full
`docker system df` → `docker image prune -af --filter until=168h` → check `/srv` and media disks → Traefik access log size.

### Locked out of the dashboard
- Cloudflare Access denied → use the tailnet path `dash.lab.DOMAIN`, then fix the policy (common cause: travelling, country rule).
- authentik broken → Komodo local admin still works at `komodo.lab.DOMAIN` (bypass forward-auth temporarily by removing the middleware label and `docker compose up -d komodo-core`), or `ssh` to the core and `docker compose logs authentik-server`.
- Tailscale broken too → LAN SSH with key, or console.

### Cloudflare is down
Public sites are down (nothing to do but wait). Admin access works over Tailscale (`*.lab.DOMAIN`). The certificate is cached; only renewal needs Cloudflare's DNS API.

### Suspected compromise
1. Cut public exposure: Cloudflare → disable the affected tunnel(s).
2. Tailscale console: expire keys of the affected machine, review SSH session logs.
3. authentik → Events: logins, IPs, new tokens. Revoke sessions and tokens. Rotate passwords.
4. Komodo: rotate API keys, webhook secret, onboarding keys.
5. Rebuild the machine from scratch (bootstrap + redeploy stacks from Git) rather than cleaning it.
