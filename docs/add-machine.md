# Add a new machine

Time: ~15 minutes. The machine needs no open ports; everything connects outbound over Tailscale.

## Checklist

- [ ] 1. OS + bootstrap
- [ ] 2. Tailscale join, tag, key expiry off
- [ ] 3. Agents (`node/`)
- [ ] 4. Komodo: server appears
- [ ] 5. Beszel: system appears, alerts set
- [ ] 6. Uptime Kuma / Homepage entries
- [ ] 7. Ansible inventory
- [ ] 8. (optional) CrowdSec agent

## 1. Bootstrap

On the new machine (Ubuntu/Debian):

```bash
sudo apt-get install -y git
sudo git clone https://github.com/jaime7981/homelab-ops.git /opt/homelab-ops
sudo chown -R $USER /opt/homelab-ops
cd /opt/homelab-ops && ./scripts/bootstrap-node.sh
```

Or from your laptop, once step 2 is done: `ansible-playbook playbooks/bootstrap.yml --limit <name>`.

## 2. Tailscale

```bash
sudo tailscale up --ssh --hostname=<name>        # e.g. ai-pc
ALLOW_LAN_CIDR=192.168.1.0/24 ./scripts/bootstrap-node.sh   # enables firewall now that TS is up
```

Admin console → the machine → *Disable key expiry*, *Edit ACL tags* → `tag:server`.
From your laptop: `ssh <user>@<name>` should work through Tailscale SSH.

## 3. Agents

In **Komodo** → Settings → Onboarding keys → copy a key (or reuse one).
In **Beszel** → *Add system* → name `<name>`, host = its Tailscale IP → copy `KEY` and `TOKEN`.

```bash
cd /opt/homelab-ops/node
cp .env.example .env
$EDITOR .env      # NODE_NAME=<name>, CORE_HOST=<core tailscale IP>, KOMODO_ONBOARDING_KEY, BESZEL_KEY, BESZEL_TOKEN
docker compose up -d
docker compose logs -f komodo-periphery     # "connected to core"
```

## 4. Komodo

The server shows up under **Servers** as `<name>`. Open it:
- *Stats* and *Containers* load → agent works.
- *Terminal* → you have a shell from the browser.
- Settings → enable alerts (CPU, memory, disk thresholds; "server unreachable").

Remove `KOMODO_ONBOARDING_KEY` from `node/.env` afterwards; the agent keeps its own key in the `periphery-keys` volume.

## 5. Beszel

The system turns green. Set alerts on it: **Status** (down), **Disk** > 85%, **CPU** > 90% for 10 min, **Temperature** if relevant. GPU machines: Beszel shows NVIDIA/AMD/Intel GPU usage when the agent can see the GPU (see Beszel docs for the GPU agent variant).

## 6. Dashboard & uptime

- `core/homepage/services.yaml` → add the machine under **Servers** (Cockpit link `https://<name>:9090`).
- Uptime Kuma → add a **Ping** or **Tailscale Ping** monitor for the machine, plus HTTP monitors for any public apps it will host.

Commit and push. Homepage picks up config changes automatically.

## 7. Ansible

Add `<name>` under `[nodes]` in `ansible/inventory.ini`. Then `ansible <name> -m ping`.

## 8. CrowdSec agent (optional)

Useful if the machine runs public-facing apps or still accepts LAN SSH.

```bash
# on the core:
docker exec crowdsec cscli machines add <name> --password '<pw>' -f /dev/null
# on the new machine: set CROWDSEC_AGENT_PASSWORD in node/.env, then
docker compose --profile crowdsec up -d
```

Detections from this machine now appear in `cscli alerts list` on the core, and the IPs are banned at the Traefik edge.

---

## Removing a machine

1. Komodo: move or destroy its stacks, then delete the server.
2. Beszel: delete the system. Uptime Kuma: delete its monitors.
3. `docker compose down` in `node/`.
4. Tailscale console: remove the machine.
5. Remove it from `services.yaml`, `inventory.ini`, `komodo/sync.toml`. Commit.
