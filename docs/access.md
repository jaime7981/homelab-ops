# Access & login control

The admin tools are reachable **only through a Cloudflare Tunnel**, the same pattern as the apps: a `cloudflared` container inside the compose project, no published ports, nothing exposed on the Pi's network.

| Layer | Controls | Where |
|---|---|---|
| Cloudflare Access | Who (identity), from which **country**, from which **IP** | Cloudflare Zero Trust dashboard |
| Traefik | CrowdSec bans, optional second IP allowlist, security headers | `core/traefik/dynamic/` |
| authentik | Users, passwords, MFA/passkeys, groups, login history | `https://auth.DOMAIN/if/admin/` |
| Tailscale | SSH into machines, agent → core connections | Tailscale admin console |

```
https://dash.ailabs.cl
 └─ Cloudflare Access: email + country=CL (+ IP) ✔
     └─ mgmt tunnel → cloudflared → Traefik :8080
         └─ CrowdSec: IP not banned ✔
             └─ allowlist.yml ✔
                 └─ authentik session? no → login + passkey ✔
                     └─ Homepage
```

> **Rule:** in the `mgmt` tunnel every public hostname points to `http://traefik:8080`.
> Never point a hostname straight at a container (`http://komodo-core:9120`): that skips CrowdSec and the authentik login.

---

## 1. Cloudflare

### Tunnel and hostnames

Domain: **`ailabs.cl`**. Existing app subdomains and their tunnels stay exactly as they are; this adds one more tunnel, `mgmt`, for the admin tools.

1. Check none of `dash`, `komodo`, `beszel`, `status`, `auth`, `ntfy`, `traefik` are already used in DNS. If one is, rename it in the Traefik labels (`core/compose.yaml`) and in `homepage/services.yaml`.
2. Zero Trust → Networks → Tunnels → **Create tunnel** `mgmt` (cloudflared) → copy the token into `core/.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
3. In the tunnel, add **Public hostnames**, all with service `HTTP` → `traefik:8080`:
   `dash`, `komodo`, `beszel`, `status`, `auth`, `ntfy`, `traefik` (each `.ailabs.cl`). Cloudflare creates the DNS records.

### Identity provider for Access

Zero Trust → Settings → Authentication → Login methods:

- **One-time PIN** (email code). Zero setup; start with this.
- Later, optionally, **authentik as OIDC** so it's one identity everywhere: authentik → OAuth2/OpenID provider + application `cloudflare-access`, redirect URI `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`; Cloudflare → *Generic OIDC* with issuer `https://auth.ailabs.cl/application/o/cloudflare-access/`.

### Access applications

Create these **before** the first `docker compose up`, so nothing is ever reachable unprotected.

**A. `Homelab admin`** (self-hosted). Domains: `dash`, `komodo`, `beszel`, `status`, `traefik`, `auth` `.ailabs.cl`. Session 24h.

Policy **Allow admins**:

| Rule | Selector | Value |
|---|---|---|
| Include | Emails | your email (and co-admins) |
| Require | Country | Chile (add countries when travelling) |
| Require *(optional)* | IP ranges | home, office, mobile ranges |

**B. `authentik OIDC`**. Domain `auth.ailabs.cl`, path `application/o`. Policy: **Bypass**, include **Everyone**.
Komodo's server calls these OIDC endpoints (token, userinfo, keys) directly. Everything else on `auth` (login pages, admin) stays behind application A.

**C. `Komodo webhook`**. Domain `komodo.ailabs.cl`, path `listener`. Policy: **Bypass**, include **Everyone**.
GitHub must reach it; it's authenticated by the webhook HMAC secret.

**ntfy** gets no Access application: the phone app can't do browser logins. It uses ntfy's own users/tokens (deny-all by default) plus CrowdSec.

More specific paths (B, C) take precedence over the whole-host application (A).

### Second IP layer (optional)

`core/traefik/dynamic/allowlist.yml` ships open (`0.0.0.0/0`). Copy the IP ranges from your Access policy there to enforce them on your own hardware too. Traefik reloads it on save.

---

## 2. authentik (single login)

First run, at `https://auth.ailabs.cl/if/flow/initial-setup/` (already behind Access, so only you can reach it). Create your admin user, then:

1. **MFA:** User settings → MFA devices → add a passkey/WebAuthn and a TOTP app. Flows → `default-authentication-flow` → the MFA validation stage → *Not configured action: Force the user to configure*.
2. **Forward-auth for all admin UIs:**
   - Applications → Providers → *Create* → **Proxy provider** → *Forward auth (domain level)*.
     Authentication URL `https://auth.ailabs.cl`, Cookie domain `ailabs.cl`.
   - Applications → *Create* `Homelab`, provider = the one above.
   - Outposts → *authentik Embedded Outpost* → add the `Homelab` application.
3. **Komodo OIDC:** Providers → OAuth2/OpenID → `komodo`, redirect `https://komodo.ailabs.cl/auth/oidc/callback`, application slug `komodo`. Copy client ID/secret to `KOMODO_OIDC_*` in `.env`, set `KOMODO_OIDC_ENABLED=true`, `docker compose up -d komodo-core`.
4. **Groups:** `admins` (you), optionally `family` (dashboard only). Bind policies on the `Homelab` application.
5. **Login history:** Events → Logs. Notification rule for `login_failed` → ntfy (see [operations.md](operations.md#notifications)).

Your app domains share the `ailabs.cl` cookie domain, but authentik only checks requests that go through this Traefik, so your other apps are unaffected.

---

## 3. Tailscale (SSH and agents only)

Tailscale is **not** used to browse the admin tools. It does two things:

- **SSH** into every machine (`ssh jaime@raspi`), including when Cloudflare or authentik are down.
- **Agent traffic**: Komodo periphery, Beszel and CrowdSec agents on other machines connect to the core on its Tailscale IP (ports 9120, 8090, 8081, bound only to that IP).

### ACL policy

Admin console → Access controls:

```jsonc
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:core":   ["autogroup:admin"]
  },
  "acls": [
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:server:*", "tag:core:*"] },
    // agents on servers reach only the core's agent ports
    { "action": "accept", "src": ["tag:server"], "dst": ["tag:core:9120,8090,8081"] }
  ],
  "ssh": [
    // "check" re-asks for your Tailscale login every 12h before SSH
    { "action": "check", "src": ["autogroup:admin"], "dst": ["tag:server", "tag:core"],
      "users": ["autogroup:nonroot", "root"] }
  ]
}
```

Tag the Pi (core) `tag:core`, every other machine `tag:server`, and disable key expiry for all of them.

### SSH keys

- **Primary:** Tailscale SSH. No keys to distribute; sessions logged in the Tailscale console.
- **Fallback:** OpenSSH with keys only (bootstrap disables passwords and root login). Keep an `ed25519` key, ideally hardware-backed (`ssh-keygen -t ed25519-sk`), in `authorized_keys`.
- **Last resort:** physical console.

### Emergency access to a UI without the tunnel

If the tunnel or Access is broken, forward a port over Tailscale SSH and use the tool locally:

```bash
ssh -L 9120:localhost:9120 jaime@raspi     # then open http://localhost:9120 (Komodo, local admin login)
```

Komodo, Beszel and CrowdSec already listen on the Pi's Tailscale IP, so `http://raspi:9120` and `http://raspi:8090` also work directly from a tailnet device.

### Optional: VPN-only path (`*.lab.ailabs.cl`)

If you later want a full second way in through the browser over Tailscale, enable `core/compose.tailnet.yaml` (instructions at the top of that file). It adds HTTPS on the Pi's Tailscale IP with a Let's Encrypt wildcard for `*.lab.ailabs.cl`.
