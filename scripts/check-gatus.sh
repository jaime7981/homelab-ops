#!/usr/bin/env bash
# Validate core/gatus/ by starting the real Gatus image against it for a few seconds.
# Run before committing a monitor change:   ./scripts/check-gatus.sh
# Exit code 0 = config loads; otherwise prints Gatus' error.
set -euo pipefail

dir="$(cd "$(dirname "$0")/../core/gatus" && pwd)"
image="$(grep -oE 'twinproduction/gatus:[^[:space:]]+' "$dir/../compose.yaml" | head -1)"
name="gatus-check-$$"

docker run -d --name "$name" \
  -e GATUS_CONFIG_PATH=/config -e DOMAIN=example.com -e NTFY_TOKEN=tk_checkcheckcheckcheckcheckche \
  -v "$dir:/config:ro" --tmpfs /data "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 10); do
  sleep 1
  logs="$(docker logs "$name" 2>&1 || true)"
  if [[ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]]; then
    echo "Gatus exited: config is invalid"; echo "$logs" | tail -20; exit 1
  fi
  if grep -qiE 'listening on|monitoring' <<<"$logs"; then
    n=$(find "$dir" -name '*.y*ml' -exec grep -hE '^\s*- name:' {} + | wc -l)
    if grep -q 'Ignoring provider' <<<"$logs"; then
      echo "WARNING: an alert provider is misconfigured:"; grep 'Ignoring provider' <<<"$logs"
    fi
    echo "OK: core/gatus loads ($n endpoints defined, including disabled ones)"; exit 0
  fi
done
echo "Gatus did not report ready in 10 s. Last logs:"; echo "$logs" | tail -20; exit 1
