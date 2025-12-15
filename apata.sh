#!/usr/bin/env bash
set -euo pipefail

PANEL_URL="https://xjvpn.ph/xjvpn"

SYNC_SCRIPT_PATH="/usr/local/bin/xjvpn-account-sync.sh"
SERVICE_PATH="/etc/systemd/system/xjvpn-account-sync.service"
TIMER_PATH="/etc/systemd/system/xjvpn-account-sync.timer"

echo "==> Installing dependencies (curl, jq)..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >/dev/null
  apt-get install -y curl jq >/dev/null
elif command -v yum >/dev/null 2>&1; then
  yum install -y curl jq >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y curl jq >/dev/null
else
  echo "!! Could not detect package manager (apt/yum/dnf). Please install curl and jq manually."
fi

echo "==> Writing sync script to $SYNC_SCRIPT_PATH ..."
cat > "$SYNC_SCRIPT_PATH" <<EOF
#!/bin/bash
set -euo pipefail

PANEL_URL="${PANEL_URL}"

# Prefer IPv4
SERVER_IP="\$(curl -4 -sS --max-time 10 ifconfig.me || true)"
if [ -z "\$SERVER_IP" ]; then
  SERVER_IP="\$(curl -4 -sS --max-time 10 https://api.ipify.org || true)"
fi

if [ -z "\$SERVER_IP" ]; then
  echo "!! Could not detect SERVER_IP (IPv4)"
  exit 1
fi

SERVER_IP_ENC="\$(printf '%s' "\$SERVER_IP" | jq -sRr @uri)"
API_URL="\${PANEL_URL}/api/server/\${SERVER_IP_ENC}/accounts"
TMP="\$(mktemp)"

HTTP_CODE="\$(curl -sS -L -o "\$TMP" -w "%{http_code}" \
  -H "Accept: application/json" \
  --max-time 20 \
  "\$API_URL" || true)"

if [ "\$HTTP_CODE" != "200" ]; then
  echo "!! HTTP \$HTTP_CODE when calling \$API_URL"
  head -c 300 "\$TMP" || true
  rm -f "\$TMP"
  exit 1
fi

ok="\$(jq -r '.ok // false' "\$TMP")"
if [ "\$ok" != "true" ]; then
  echo "!! API returned ok=false for accounts"
  cat "\$TMP"
  rm -f "\$TMP"
  exit 1
fi

# =============================
# CREATE / SYNC ACCOUNTS
# =============================
jq -c '.accounts[]?' "\$TMP" | while read -r acc; do
  id="\$(echo "\$acc" | jq -r '.id')"
  username="\$(echo "\$acc" | jq -r '.username')"
  password="\$(echo "\$acc" | jq -r '.password')"
  date_expired="\$(echo "\$acc" | jq -r '.date_expired // empty')"

  if [ -z "\$username" ] || [ -z "\$password" ] || [ "\$username" = "null" ]; then
    continue
  fi

  if getent passwd "\$username" >/dev/null 2>&1; then
    echo "✔ exists: \$username (mark synced)"
    curl -sS -X POST \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "{\\"id\\":\${id},\\"ip\\":\\"\${SERVER_IP}\\"}" \
      "\${PANEL_URL}/api/accounts/synced" >/dev/null 2>&1 || true
    continue
  fi

  echo "➕ create: \$username"
  if [ -n "\$date_expired" ] && [ "\$date_expired" != "null" ]; then
    useradd "\$username" -s /bin/false -e "\$date_expired"
  else
    useradd "\$username" -s /bin/false
  fi

  echo -e "\$password\\n\$password" | passwd "\$username" >/dev/null

  curl -sS -X POST \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{\\"id\\":\${id},\\"ip\\":\\"\${SERVER_IP}\\"}" \
    "\${PANEL_URL}/api/accounts/synced" >/dev/null 2>&1 || true

  echo "✅ synced: \$username"
done

rm -f "\$TMP"

# =============================
# DELETE ACCOUNTS REMOVED IN DB
# =============================
# ✅ FIXED ENDPOINT:
#   /api/server/{ip}/accounts/deleted
DEL_URL="\${PANEL_URL}/api/server/\${SERVER_IP_ENC}/accounts/deleted"
DEL_TMP="\$(mktemp)"

HTTP_CODE="\$(curl -sS -L -o "\$DEL_TMP" -w "%{http_code}" \
  -H "Accept: application/json" \
  --max-time 20 \
  "\$DEL_URL" || true)"

if [ "\$HTTP_CODE" != "200" ]; then
  echo "!! HTTP \$HTTP_CODE when calling \$DEL_URL"
  head -c 300 "\$DEL_TMP" || true
  rm -f "\$DEL_TMP"
  exit 0
fi

ok="\$(jq -r '.ok // false' "\$DEL_TMP")"
if [ "\$ok" != "true" ]; then
  echo "!! API returned ok=false for deleted"
  cat "\$DEL_TMP"
  rm -f "\$DEL_TMP"
  exit 0
fi

jq -c '.accounts[]?' "\$DEL_TMP" | while read -r acc; do
  username="\$(echo "\$acc" | jq -r '.username')"
  if [ -z "\$username" ] || [ "\$username" = "null" ]; then
    continue
  fi

  if getent passwd "\$username" >/dev/null 2>&1; then
    echo "🗑 deleting: \$username"
    userdel -r "\$username" || true
  else
    echo "↷ skip (not linux user): \$username"
  fi
done

rm -f "\$DEL_TMP"
EOF

chmod +x "$SYNC_SCRIPT_PATH"

echo "==> Creating systemd service $SERVICE_PATH ..."
cat > "$SERVICE_PATH" <<'EOF'
[Unit]
Description=XJVPN Account Sync
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xjvpn-account-sync.sh
User=root
EOF

echo "==> Creating systemd timer $TIMER_PATH (every 10 seconds) ..."
cat > "$TIMER_PATH" <<'EOF'
[Unit]
Description=Run XJVPN account sync every 10 seconds

[Timer]
OnBootSec=10s
OnUnitActiveSec=10s
AccuracySec=1s
Unit=xjvpn-account-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now xjvpn-account-sync.timer

echo "✅ Done"
