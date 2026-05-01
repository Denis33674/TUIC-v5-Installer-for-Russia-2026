#!/bin/bash
# =============================================
# TUIC v5 Installer for Russia 2026
# Автор: Denis_110889
# Полная версия
# =============================================

#!/usr/bin/env bash
set -Eeuo pipefail

# TUIC v5 installer
# Ubuntu/Debian
# Author: Denis_110889

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT="${PORT:-443}"
SNI="${SNI:-www.microsoft.com}"
CONF_DIR="/etc/tuic"
BIN="/usr/local/bin/tuic-server"
SERVICE="/etc/systemd/system/tuic.service"
CONFIG="$CONF_DIR/config.json"

log(){ echo -e "${GREEN}[$(date '+%F %T')] $*${NC}"; }
warn(){ echo -e "${YELLOW}[$(date '+%F %T')] WARNING: $*${NC}"; }
die(){ echo -e "${RED}[$(date '+%F %T')] ERROR: $*${NC}"; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root: sudo bash $0"

command -v apt >/dev/null || die "Поддерживаются только Debian/Ubuntu"

log "Установка зависимостей..."
apt update
apt install -y curl jq openssl qrencode ufw ca-certificates

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ASSET="tuic-server-1.0.0-x86_64-unknown-linux-gnu" ;;
  aarch64|arm64) ASSET="tuic-server-1.0.0-aarch64-unknown-linux-gnu" ;;
  armv7l) ASSET="tuic-server-1.0.0-armv7-unknown-linux-gnueabihf" ;;
  *) die "Неподдерживаемая архитектура: $ARCH" ;;
esac

URL="https://github.com/tuic-protocol/tuic/releases/latest/download/${ASSET}"

log "Скачиваем TUIC: $ASSET"
curl -fL --retry 3 -o "$BIN" "$URL" || die "Не удалось скачать TUIC"
chmod +x "$BIN"

log "Настраиваем BBR..."
cat >/etc/sysctl.d/99-tuic-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=2500000
net.core.wmem_max=2500000
EOF
sysctl --system >/dev/null || warn "sysctl применился не полностью"

log "Создаём конфигурацию..."
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"

UUID="$(cat /proc/sys/kernel/random/uuid)"
PASSWORD="$(openssl rand -hex 16)"
SERVER_IP="$(curl -4fsS https://ifconfig.me || hostname -I | awk '{print $1}')"

openssl req -x509 -newkey rsa:2048 \
  -keyout "$CONF_DIR/server.key" \
  -out "$CONF_DIR/server.crt" \
  -days 3650 -nodes \
  -subj "/CN=$SNI" >/dev/null 2>&1

chmod 600 "$CONF_DIR/server.key"

cat > "$CONFIG" <<EOF
{
  "server": "[::]:${PORT}",
  "users": {
    "${UUID}": "${PASSWORD}"
  },
  "certificate": "${CONF_DIR}/server.crt",
  "private_key": "${CONF_DIR}/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "auth_timeout": "3s",
  "task_negotiation_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500
}
EOF

chmod 600 "$CONFIG"

log "Создаём systemd service..."
cat > "$SERVICE" <<EOF
[Unit]
Description=TUIC v5 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${BIN} -c ${CONFIG}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

log "Открываем UDP порт ${PORT}..."
ufw allow "${PORT}/udp" >/dev/null || warn "UFW не настроен, открой UDP ${PORT} вручную"

systemctl daemon-reload
systemctl enable --now tuic
sleep 2

systemctl is-active --quiet tuic || {
  journalctl -u tuic --no-pager -n 50
  die "TUIC не запустился"
}

CLIENT_LINK="tuic://${UUID}:${PASSWORD}@${SERVER_IP}:${PORT}?congestion_control=bbr&alpn=h3&sni=${SNI}&allow_insecure=1#TUIC-RU"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TUIC v5 установлен и запущен${NC}"
echo -e "IP:       ${BLUE}${SERVER_IP}${NC}"
echo -e "Port:     ${BLUE}${PORT}/udp${NC}"
echo -e "UUID:     ${BLUE}${UUID}${NC}"
echo -e "Password: ${BLUE}${PASSWORD}${NC}"
echo -e "SNI:      ${BLUE}${SNI}${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "$CLIENT_LINK"
echo
qrencode -t ansiutf8 "$CLIENT_LINK" || true
echo
echo -e "${YELLOW}Важно: в панели VPS тоже открой UDP ${PORT}.${NC}"
echo "Проверка:"
echo "  systemctl status tuic --no-pager"
echo "  journalctl -u tuic -f"
