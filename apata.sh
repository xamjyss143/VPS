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
SERVER_IP="\$(curl -s ifconfig.me)"
API_URL="\$PANEL_URL/api/server/\$SERVER_IP/accounts"

json=\$(curl -s "\$API_URL")

ok=\$(echo "\$json" | jq -r '.ok')
[ "\$ok" != "true" ] && exit 1

echo "\$json" | jq -c '.accounts[]' | while read -r acc; do
  id=\$(echo "\$acc" | jq -r '.id')
  username=\$(echo "\$acc" | jq -r '.username')
  password=\$(echo "\$acc" | jq -r '.password')
  date_expired=\$(echo "\$acc" | jq -r '.date_expired // empty')

  if id "\$username" >/dev/null 2>&1; then
    echo "✔ \$username already exists"
    continue
  fi

  # Build useradd expiry flag if date_expired exists (YYYY-MM-DD)
  expire_flag=""
  if [ -n "\$date_expired" ]; then
    expire_flag="-e \$date_expired"
  fi

  echo "➕ Creating \$username (expires: \${date_expired:-none})"

  # Create user (no shell login) + optional expiry date
  useradd "\$username" -s /bin/false \$expire_flag

  # Set password (non-interactive)
  echo -e "\$password\\n\$password" | passwd "\$username" >/dev/null

  # notify panel (mark as synced)
  curl -s -X POST \\
    -H "Content-Type: application/json" \\
    -d "{\\"id\\": \$id}" \\
    "\$PANEL_URL/api/accounts/synced" >/dev/null

  echo "✅ Synced \$username"
done
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
