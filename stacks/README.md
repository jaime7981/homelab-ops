# Stacks

One folder per app, grouped by the machine that runs it:

```
stacks/
├── _template/compose.yaml      # copy this for a new app
├── media-pc/
│   └── plex/compose.yaml
├── web-pc/
│   ├── website/compose.yaml
│   └── property-admin/compose.yaml
└── ai-pc/
    └── ai-gateway/compose.yaml
```

Each folder is registered as a **Stack** in [`komodo/sync.toml`](../komodo/sync.toml).
When you push to `main`, the GitHub webhook tells Komodo to redeploy the stacks that changed.

Rules:

- Pin image versions (`app:1.4.2`, not `latest`) for anything you care about. Komodo shows when a newer image exists, and you bump the tag in a commit.
- No secrets in this folder. Use `${VAR}` here and set values in the Komodo stack's *Environment*, using Komodo secrets (`VAR=[[SECRET_NAME]]`).
- Public apps use a `cloudflared` sidecar (see the template). Admin/private apps publish only on the Tailscale IP.

See [docs/add-app.md](../docs/add-app.md) for the step-by-step.
