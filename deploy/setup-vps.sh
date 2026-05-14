#!/bin/bash
# One-shot VPS-Setup für CEELIS-Atlas auf Debian 13 (Trixie).
# Erste Schritte AUF dem VPS, ALS ROOT, nach erster SSH-Connection.
#
# Usage:
#   ssh root@<vps-ip>
#   curl -fsSL https://raw.githubusercontent.com/Paskrone/ceelis-hermes/main/deploy/setup-vps.sh | bash -s pascal
set -euo pipefail

USER_NAME="${1:-pascal}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: muss als root laufen (initial SSH login als root)."
  exit 1
fi

echo "==> System-Update"
apt update && apt upgrade -y

echo "==> User '${USER_NAME}' anlegen"
if ! id "${USER_NAME}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${USER_NAME}"
  usermod -aG sudo "${USER_NAME}"
fi
mkdir -p "/home/${USER_NAME}/.ssh"
cp /root/.ssh/authorized_keys "/home/${USER_NAME}/.ssh/authorized_keys"
chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.ssh"
chmod 700 "/home/${USER_NAME}/.ssh"
chmod 600 "/home/${USER_NAME}/.ssh/authorized_keys"

echo "==> Sudo-NOPASSWD für '${USER_NAME}' (Komfort für docker-compose Aufrufe)"
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"
chmod 440 "/etc/sudoers.d/${USER_NAME}"

echo "==> SSH-Hardening (Root-Login disabled, Password-Auth disabled)"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

echo "==> Firewall + fail2ban"
apt install -y ufw fail2ban curl git
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Unattended Security-Updates"
apt install -y unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

echo "==> Docker + Compose"
curl -fsSL https://get.docker.com | sh
usermod -aG docker "${USER_NAME}"

echo "==> Verzeichnis-Layout"
mkdir -p /srv/{hermes/data,caddy}
chown -R "${USER_NAME}:${USER_NAME}" /srv

echo "==> Docker-Network 'web' (Caddy ↔ Hermes)"
docker network create web 2>/dev/null || true

echo "==> Repo klonen (ceelis-hermes deploy-files)"
sudo -u "${USER_NAME}" git clone https://github.com/Paskrone/ceelis-hermes.git "/home/${USER_NAME}/ceelis-hermes"
sudo -u "${USER_NAME}" cp "/home/${USER_NAME}/ceelis-hermes/deploy/docker-compose.yml" /srv/hermes/docker-compose.yml
sudo -u "${USER_NAME}" cp -r "/home/${USER_NAME}/ceelis-hermes/deploy/caddy/." /srv/caddy/
sudo -u "${USER_NAME}" cp "/home/${USER_NAME}/ceelis-hermes/deploy/.env.example" /srv/hermes/.env
chmod 600 /srv/hermes/.env
chown "${USER_NAME}:${USER_NAME}" /srv/hermes/.env

echo
echo "============================================================"
echo "DONE — VPS ist bereit. Nächste Schritte:"
echo "  1. Re-Login als ${USER_NAME}:   ssh ${USER_NAME}@<vps-ip>"
echo "  2. /srv/hermes/.env editieren (Tokens eintragen)"
echo "  3. Caddy starten:               cd /srv/caddy   && docker compose up -d"
echo "  4. Volume-Inhalt einspielen:    siehe README im ceelis-hermes-Repo"
echo "  5. Hermes starten:              cd /srv/hermes  && docker compose up -d"
echo "============================================================"
