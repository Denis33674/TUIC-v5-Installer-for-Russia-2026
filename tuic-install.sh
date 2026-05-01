#!/bin/bash
# =============================================
# TUIC v5 Installer for Russia 2026
# Автор: Denis_110889
# Полная версия
# =============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%F %T')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%F %T')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%F %T')] ERROR: $1${NC}"
    exit 1
}

# Проверка root
if [[ $EUID -ne 0 ]]; then
    error "Запускайте скрипт от root (sudo)"
fi

log "Начинаем установку TUIC v5..."

# Обновление системы
apt update && apt upgrade -y

# Установка зависимостей
apt install -y curl unzip jq qrencode ufw

# Скачиваем последнюю версию TUIC
log "Скачиваем TUIC v5..."
LATEST_URL=$(curl -s https://api.github.com/repos/2dust/tuic/releases/latest | jq -r '.assets[] | select(.name | contains("x86_64-unknown-linux-gnu")) | .browser_download_url')
curl -L -o tuic.zip "$LATEST_URL"
unzip -o tuic.zip
mv tuic /usr/local/bin/tuic-server
chmod +x /usr/local/bin/tuic-server
rm -f tuic.zip

log "TUIC v5 успешно установлен!"

# Создаём папку
mkdir -p /etc/tuic

# Генерация конфигурации
log "Создаём конфигурацию сервера..."

UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -hex 16)
SERVER_IP=$(curl -4s https://ifconfig.me)

cat > /etc/tuic/config.json << EOF
{
  "server": "[::]:443",
  "uuid": "$UUID",
  "password": "$PASSWORD",
  "congestion_control": "bbr",
  "alpn": ["h3", "h2", "http/1.1"],
  "tls": {
    "enabled": true,
    "server_name": "www.microsoft.com",
    "certificate": "/etc/tuic/server.crt",
    "private_key": "/etc/tuic/server.key"
  },
  "udp_relay": true
}
EOF

# Создаём systemd сервис
log "Создаём systemd сервис..."

cat > /etc/systemd/system/tuic.service << EOF
[Unit]
Description=TUIC v5 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now tuic

log "TUIC v5 успешно запущен!"

# Генерация клиентской ссылки
log "Генерируем клиентскую ссылку..."

UUID=$(jq -r '.uuid' /etc/tuic/config.json)
PASS=$(jq -r '.password' /etc/tuic/config.json)
SERVER_IP=$(curl -4s https://ifconfig.me)

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}TUIC v5 успешно установлен!${NC}"
echo -e "IP: ${BLUE}$SERVER_IP${NC}"
echo -e "UUID: ${BLUE}$UUID${NC}"
echo -e "Password: ${BLUE}$PASS${NC}"
echo -e "${GREEN}=====================================${NC}"

echo "Клиентская ссылка (для Hiddify/Shadowrocket):"
echo "tuic://${UUID}:${PASS}@${SERVER_IP}:443?congestion_control=bbr&alpn=h3%2Ch2%2Chttp%2F1.1&sni=www.microsoft.com#TUIC-RU"

echo -e "${YELLOW}Не забудь открыть порт 443 UDP в панели VPS!${NC}"

# Проверка статуса
systemctl status tuic --no-pager -l | head -n 20
