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

# Prefer IPv4 (panel server IP is usually stored as IPv4)
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
  echo "!! Body preview:"
  head -c 300 "\$TMP" || true
  echo ""
  rm -f "\$TMP"
  exit 1
fi

if ! jq -e . "\$TMP" >/dev/null 2>&1; then
  echo "!! Response is not valid JSON from \$API_URL"
  echo "!! Body preview:"
  head -c 300 "\$TMP" || true
  echo ""
  rm -f "\$TMP"
  exit 1
fi

ok="\$(jq -r '.ok // false' "\$TMP")"
if [ "\$ok" != "true" ]; then
  echo "!! API returned ok=false"
  cat "\$TMP"
  rm -f "\$TMP"
  exit 1
fi

jq -c '.accounts[]?' "\$TMP" | while read -r acc; do
  id="\$(echo "\$acc" | jq -r '.id')"
  username="\$(echo "\$acc" | jq -r '.username')"
  password="\$(echo "\$acc" | jq -r '.password')"
  date_expired="\$(echo "\$acc" | jq -r '.date_expired // empty')"

  if [ -z "\$username" ] || [ -z "\$password" ] || [ "\$username" = "null" ] || [ "\$password" = "null" ]; then
    echo "!! Skipping invalid account payload: \$acc"
    continue
  fi

  # ✅ FAST check (better than `id`)
  if getent passwd "\$username" >/dev/null 2>&1; then
    echo "✔ \$username already exists"
    # still notify panel per-server
    curl -sS -X POST \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "{\\"id\\":\${id},\\"ip\\":\\"\${SERVER_IP}\\"}" \
      "\${PANEL_URL}/api/accounts/synced" >/dev/null 2>&1 || true
    continue
  fi

  echo "➕ Creating \$username (expires: \${date_expired:-none})"

  # Create user with optional expiry date
  if [ -n "\$date_expired" ] && [ "\$date_expired" != "null" ]; then
    useradd "\$username" -s /bin/false -e "\$date_expired"
  else
    useradd "\$username" -s /bin/false
  fi

  # Set password non-interactive
  echo -e "\$password\\n\$password" | passwd "\$username" >/dev/null

  # ✅ notify panel per-server
  curl -sS -X POST \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{\\"id\\":\${id},\\"ip\\":\\"\${SERVER_IP}\\"}" \
    "\${PANEL_URL}/api/accounts/synced" >/dev/null 2>&1 || true

  echo "✅ Synced \$username"
done

rm -f "\$TMP"
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

echo "==> Reloading systemd + enabling timer..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now xjvpn-account-sync.timer

echo ""
echo "✅ Done!"
echo "Check timer:   systemctl list-timers | grep xjvpn"
echo "View logs:     journalctl -u xjvpn-account-sync.service -f"
