#!/usr/bin/env bash
# Scan every image used by running containers on this machine for HIGH/CRITICAL CVEs.
# Sends a summary to ntfy if NTFY_URL is set (e.g. https://ntfy.example.com/homelab)
# and NTFY_TOKEN holds an ntfy access token.
#
# Run weekly from cron or a Komodo Action:
#   0 6 * * 1  /opt/homelab-ops/scripts/scan-images.sh
set -euo pipefail

host="$(hostname)"
report="$(mktemp)"
trap 'rm -f "$report"' EXIT

images=$(docker ps --format '{{.Image}}' | sort -u)
total=0
for img in $images; do
  n=$(trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --format json "$img" 2>/dev/null \
      | jq '[.Results[]?.Vulnerabilities[]?] | length')
  total=$((total + n))
  [[ "$n" -gt 0 ]] && echo "$n  $img" >> "$report"
done

echo "Host: $host  HIGH/CRITICAL findings: $total"
sort -rn "$report" || true

if [[ -n "${NTFY_URL:-}" && "$total" -gt 0 ]]; then
  curl -fsS -H "Authorization: Bearer ${NTFY_TOKEN:-}" \
       -H "Title: Trivy: $total HIGH/CRITICAL on $host" -H "Tags: warning" \
       --data-binary @"$report" "$NTFY_URL" >/dev/null
fi
