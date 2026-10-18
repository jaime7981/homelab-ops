# Local AI host (llama.cpp)

The one part of the homelab that doesn't fit a standard tool, so it's handled differently.

## Current setup

- `llama.cpp` (`llama-server`) runs **on the host**, not in Docker, to use the GPU directly.
- A Docker container in front of it handles **API users and credentials, usage tracking, Hugging Face downloads, and loading models** into the llama.cpp service.
- Exposed through its own Cloudflare Tunnel.

## How it plugs into the management stack

| Concern | Covered by |
|---|---|
| Gateway container: deploy, logs, restart | Komodo stack `stacks/ai-pc/ai-gateway/` |
| `llama-server` process: start/stop/restart, logs | **systemd** unit + Cockpit (Services, Logs) |
| GPU usage, VRAM, temps | Beszel (GPU-enabled agent) |
| API reachable from outside | Uptime Kuma HTTP check on `https://ai.DOMAIN/health` |
| Process died | systemd `Restart=always` + Uptime Kuma alert |

### Run llama.cpp as a systemd service

```ini
# /etc/systemd/system/llama-server.service
[Unit]
Description=llama.cpp server
After=network-online.target

[Service]
User=llama
EnvironmentFile=/etc/llama-server.env          # MODEL=..., ARGS=...
ExecStart=/opt/llama.cpp/build/bin/llama-server -m ${MODEL} --host 127.0.0.1 --port 8080 ${ARGS}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now llama-server
```

Bind to `127.0.0.1` (or the Docker bridge IP) so **only the gateway** can call it. The gateway is the only thing with auth.

## What stays custom

Your gateway already does the parts no tool covers well. Before extending it, check whether these replace part of it:

| Tool | Replaces | Notes |
|---|---|---|
| **llama-swap** | Loading/unloading models on demand | A proxy that starts the right `llama-server` per requested model. Config is a YAML of models. |
| **LiteLLM proxy** | API keys, per-user usage, budgets, rate limits | OpenAI-compatible, Postgres-backed, has an admin UI |

If they fit, the gateway shrinks to "download a model from Hugging Face and add it to the llama-swap config". If they don't, keep your gateway and add a small **admin API** to it:

```
GET    /admin/models              list local + loaded models
POST   /admin/models/pull         {repo, file}     download from Hugging Face
POST   /admin/models/{id}/load    switch the running model (restart llama-server)
GET    /admin/users               list API users + usage
POST   /admin/users               create user, return key
DELETE /admin/users/{id}          revoke
```

Expose `/admin/*` **only** on the tailnet path or behind Traefik + authentik (`secured-*` middlewares), never through the public AI tunnel. Trust the `X-authentik-username` header for who's calling.

A future custom portal ([dashboard.md](dashboard.md#later-a-custom-portal)) can then show models and users next to everything else.

## Restarting llama-server from the container

If the gateway needs to restart the host service after changing the model, avoid giving it full root. Options, safest first:
1. Use llama-swap, which does model switching itself (no restart needed).
2. A tiny root-owned helper allowed via `sudoers` for exactly `systemctl restart llama-server`, called over SSH from the container with a dedicated, command-restricted key.
3. Komodo Action / Procedure that runs the restart on `ai-pc` (button in Komodo, no gateway involvement).
