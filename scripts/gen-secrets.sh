#!/usr/bin/env bash
# Print random values for every secret in core/.env.example.
# Paste them into core/.env. Nothing is written to disk.
set -euo pipefail
rand() { openssl rand -base64 "${1:-36}" | tr -d '\n=/+' | cut -c1-"${2:-48}"; }

cat <<EOF
AUTHENTIK_SECRET_KEY=$(rand 60 64)
AUTHENTIK_PG_PASS=$(rand)
KOMODO_DB_PASSWORD=$(rand)
KOMODO_JWT_SECRET=$(rand)
KOMODO_WEBHOOK_SECRET=$(rand)
KOMODO_INIT_ADMIN_PASSWORD=$(rand 24 24)
CROWDSEC_BOUNCER_KEY=$(rand)
EOF
