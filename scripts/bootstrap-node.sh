#!/usr/bin/env bash
# Prepare a fresh Ubuntu/Debian machine to join the homelab.
# Run as a sudo-capable user:  curl ... | bash   or   ./scripts/bootstrap-node.sh
#
# What it does:
#   1. Base packages, automatic security updates
#   2. Docker Engine + compose plugin
#   3. Tailscale (you finish login interactively, with Tailscale SSH enabled)
#   4. Cockpit web console (reachable only over Tailscale)
#   5. Lynis (security audit) + Trivy (image scanning)
#   6. Firewall: deny all inbound except via tailscale0
#   7. SSH hardening: keys only, no root login
#
# Idempotent: safe to run again. Ansible equivalent: ansible/playbooks/bootstrap.yml

set -euo pipefail

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
USER_NAME="${SUDO_USER:-$USER}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Base packages"
$SUDO apt-get update -y
$SUDO apt-get install -y ca-certificates curl gnupg git ufw unattended-upgrades \
  apt-listchanges needrestart lynis jq

log "Automatic security updates"
$SUDO dpkg-reconfigure -f noninteractive unattended-upgrades
$SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

log "Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | $SUDO sh
fi
$SUDO usermod -aG docker "$USER_NAME"
$SUDO systemctl enable --now docker
# Rotate container logs so disks don't fill up
$SUDO tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "log-driver": "json-file", "log-opts": { "max-size": "20m", "max-file": "5" } }
EOF
$SUDO systemctl restart docker

log "Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | $SUDO sh
fi

log "Cockpit"
$SUDO apt-get install -y cockpit cockpit-pcp || $SUDO apt-get install -y cockpit
$SUDO systemctl enable --now cockpit.socket

log "Trivy"
if ! command -v trivy >/dev/null; then
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | $SUDO sh -s -- -b /usr/local/bin
fi

log "SSH hardening (keys only, no root)"
$SUDO tee /etc/ssh/sshd_config.d/10-homelab.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
if [[ ! -s "/home/$USER_NAME/.ssh/authorized_keys" ]]; then
  echo "WARNING: /home/$USER_NAME/.ssh/authorized_keys is empty."
  echo "         Add your public key before reconnecting with plain SSH,"
  echo "         or use Tailscale SSH (step below), which does not need it."
fi
$SUDO systemctl reload ssh || $SUDO systemctl reload sshd

log "Firewall: allow only Tailscale (+ optional LAN) inbound"
# ALLOW_LAN_CIDR=192.168.1.0/24 ./bootstrap-node.sh  -> keeps LAN access (needed for Plex on TVs, etc.)
if ! tailscale status >/dev/null 2>&1; then
  echo "Tailscale is not logged in yet: skipping firewall so you don't lock yourself out."
  echo "Run 'sudo tailscale up --ssh' and then re-run this script."
else
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  $SUDO ufw allow in on tailscale0
  $SUDO ufw allow 41641/udp comment 'tailscale direct connections'
  if [[ -n "${ALLOW_LAN_CIDR:-}" ]]; then
    $SUDO ufw allow from "$ALLOW_LAN_CIDR" comment 'home LAN'
  fi
  $SUDO ufw --force enable
fi

cat <<EOF

Done. Remaining manual steps:

  1. Join the tailnet with SSH enabled:
       sudo tailscale up --ssh --hostname=<machine-name>
  2. Log out and back in (docker group).
  3. Clone this repo, then:
       cd homelab-ops/node && cp .env.example .env && \$EDITOR .env
       docker compose up -d
  4. Follow docs/add-machine.md to register it in Komodo, Beszel and Uptime Kuma.

NOTE: Docker-published ports bypass ufw. Always publish admin ports on the
      Tailscale IP (100.x.y.z:PORT:PORT) or not at all; public apps go through
      Cloudflare Tunnel, which needs no published port.
EOF
