---
description: Join a new machine to the homelab fleet (agents, dashboard, inventory)
argument-hint: <name> [tailscale-ip] [notes]
---

Add a new server to the fleet: $ARGUMENTS

Follow `docs/add-machine.md` exactly. Steps:

1. If the name or the Tailscale IP is missing, ask for it. The name must be the machine's Tailscale MagicDNS name.
2. Tell the user what to run **on the new machine** (clone to `/opt/homelab-ops`, `scripts/bootstrap-node.sh`, `sudo tailscale up --ssh --hostname=<name>`, rerun bootstrap with `ALLOW_LAN_CIDR` if it needs LAN access). If you have `ssh <name>` access, offer to run it yourself, but confirm first.
3. Tell the user to get the Komodo onboarding key and the Beszel `KEY`/`TOKEN` (Add system, host = its Tailscale IP), and give them the exact `node/.env` contents with placeholders for those secrets. `CORE_HOST` is the Pi's Tailscale IP (`tailscale ip -4` on the Pi). Don't ask the user to paste secrets into the chat.
4. Edit the repo:
   - `core/homepage/services.yaml`: add a tile under **Servers** (`href: https://<name>:9090`, short description).
   - `core/gatus/endpoints/machines/<name>.yaml`: copy `media-pc.yaml`, rename, `enabled: true` once the machine is on the tailnet. Run `./scripts/check-gatus.sh`.
   - `ansible/inventory.example.ini`: add `<name>` under `[nodes]`. Also add it to `ansible/inventory.ini` if that file exists.
5. Validate the YAML, commit (`Add <name> to the fleet`) and push once the user agrees.
6. End with a checklist of what the user still has to do: Komodo server appears and alerts enabled, Beszel alerts (down, disk > 85%, CPU > 90% for 10 min), `git -C /opt/homelab-ops pull` on the Pi if you're not on it, remove `KOMODO_ONBOARDING_KEY` from `node/.env`, optional CrowdSec agent (`docs/add-machine.md` § 8).
