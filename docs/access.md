# Access & login control

Four layers, each configured once:

| Layer | Controls | Where |
|---|---|---|
| Cloudflare Access | Who (identity), from which **country**, from which **IP**, for public admin hostnames | Cloudflare Zero Trust dashboard |
| Tailscale | Which devices are on the VPN, which ports each can reach, who can SSH where | Tailscale admin console (ACL policy) |
| Traefik | Tailnet-only rule, optional second IP allowlist, CrowdSec bans | `core/traefik/dynamic/` |
| authentik | Users, passwords, MFA/passkeys, groups, login history | `https://auth.DOMAIN/if/admin/` |

You can reach the dashboard **either** way:

- **From anywhere, no VPN:** `https://dash.DOMAIN` → Cloudflare Access login → authentik login (SSO; after the first login it's one click).
- **On Tailscale:** `https://dash.lab.DOMAIN` → authentik login. Works even if Cloudflare Access is misconfigured.

---

## 1. Cloudflare Access (public path)

### DNS & tunnel

1. Zero Trust → Networks → Tunnels → **Create tunnel** `mgmt` (type cloudflared). Copy the token into `core/.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
2. In the tunnel, add **Public hostnames**, all pointing to `http://traefik:8080`:
   `dash`, `komodo`, `beszel`, `status`, `auth`, `ntfy` (each `.DOMAIN`).
3. DNS → add a record for the tailnet path (not proxied):
   - `A  *.lab  100.x.y.z` (core's Tailscale IP), **DNS only (grey cloud)**.

### Identity provider

Zero Trust → Settings → Authentication → Login methods. Pick one:

- **One-time PIN** (email code). Zero setup, good enough to start.
- **authentik (OpenID Connect)**. One identity everywhere. In authentik create an OAuth2/OpenID provider + application `cloudflare-access`, redirect URI `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`, then add it in Cloudflare as a *Generic OIDC* login method with the client ID/secret and `https://auth.DOMAIN/application/o/cloudflare-access/` as the issuer.

### Application + policies

Zero Trust → Access → Applications → **Add self-hosted application** `Homelab admin`:

- Domains: `dash.DOMAIN`, `komodo.DOMAIN`, `beszel.DOMAIN`, `status.DOMAIN`
- Session duration: 24h

Policy **Allow admins** (action: Allow):

| Rule | Selector | Value |
|---|---|---|
| Include | Emails | your email (and family/co-admins) |
| Require | Country | Chile (add countries when travelling) |
| Require *(optional)* | IP ranges | home, office, mobile CGNAT ranges |

Everything not matched is denied by default.

Add a second application, **`Komodo webhook`**, for `komodo.DOMAIN` with path `listener`, with one policy: action **Bypass**, include **Everyone**. GitHub must reach it, and it's protected by the webhook HMAC secret plus CrowdSec.

Do **not** put `auth.DOMAIN` or `ntfy.DOMAIN` behind Access:
- `auth`: Komodo (and Cloudflare itself, if you use authentik as IdP) call it server-to-server for OIDC.
- `ntfy`: the phone app can't do browser logins. It uses ntfy's own tokens, with deny-all by default.

Both are still covered by CrowdSec; authentik also enforces MFA.

### Second IP layer (optional)

`core/traefik/dynamic/allowlist.yml` ships open (`0.0.0.0/0`). Put the same ranges as in the Access policy there to enforce them on your own hardware too. Traefik reloads it on save.

---

## 2. Tailscale (VPN path, SSH)

### Join machines

`sudo tailscale up --ssh --hostname=<name>` on each PC (the bootstrap script prints this).
In the admin console, **disable key expiry** for servers and apply tags.

### ACL policy

Admin console → Access controls. Starting point:

```jsonc
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:core":   ["autogroup:admin"]
  },
  "acls": [
    // You (admin) can reach everything on servers
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:server:*", "tag:core:*"] },
    // Agents on servers can reach only the core's agent ports
    { "action": "accept", "src": ["tag:server"], "dst": ["tag:core:9120,8090,8081"] }
  ],
  "ssh": [
    // "check" re-asks for your Tailscale login every 12h before SSH: good for emergency access
    { "action": "check", "src": ["autogroup:admin"], "dst": ["tag:server", "tag:core"],
      "users": ["autogroup:nonroot", "root"] }
  ]
}
```

Tag the core host `tag:core` and every other PC `tag:server`. A compromised app host then can't touch anything except the three agent ports on the core.

### SSH keys

- **Primary:** Tailscale SSH. `ssh jaime@media-pc` from any tailnet device. No keys to distribute; access is logged in the Tailscale console.
- **Fallback:** regular OpenSSH with keys only. The bootstrap disables passwords and root login. Keep an `ed25519` key (ideally on a hardware key: `ssh-keygen -t ed25519-sk`) in `~/.ssh/authorized_keys` on each machine, reachable over the tailnet or LAN.
- **Last resort:** physical console.

---

## 3. authentik (single login)

First run: `https://auth.DOMAIN/if/flow/initial-setup/` → create your admin user, then:

1. **MFA:** User settings → MFA devices → add a passkey/WebAuthn and a TOTP app. Then Flows → `default-authentication-flow` → enforce MFA (`default-authentication-mfa-validation` stage, *not configured action: Force the user to configure*).
2. **Forward-auth for all admin UIs:**
   - Applications → Providers → *Create* → **Proxy provider** → *Forward auth (domain level)*.
     Authentication URL `https://auth.DOMAIN`, Cookie domain `DOMAIN`.
   - Applications → *Create* `Homelab`, provider = the one above.
   - Outposts → *authentik Embedded Outpost* → add the `Homelab` application.
   The cookie on `DOMAIN` also covers `*.lab.DOMAIN`, so one login works on both paths.
3. **Komodo OIDC:** Providers → OAuth2/OpenID → `komodo`, redirect `https://komodo.DOMAIN/auth/oidc/callback` (and the `.lab.` one). Application slug `komodo`. Copy the client ID/secret to `KOMODO_OIDC_*` in `.env`, set `KOMODO_OIDC_ENABLED=true`, `docker compose up -d komodo-core`.
4. **Groups:** create `admins` (you) and optionally `family` (read-only dashboard). Bind policies on the `Homelab` application to restrict who passes.
5. **Login history:** Events → Logs. Add a Notification Rule for `login_failed` → webhook to ntfy (see [operations.md](operations.md#notifications)).

---

## Summary: what happens on a login

```
dash.DOMAIN
 └─ Cloudflare Access: email + country=CL (+ IP) ✔
     └─ tunnel → Traefik
         └─ CrowdSec: IP not banned ✔
             └─ allowlist.yml ✔
                 └─ authentik cookie? no → login + passkey ✔
                     └─ Homepage
```
