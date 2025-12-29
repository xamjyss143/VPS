#!/bin/bash
set -e

PORT=5001
BIND_HOST="0.0.0.0"
NEW_PASSWORD="xJxAm12345"

APP_DIR="/opt/sudo-unlock-api"
APP_FILE="$APP_DIR/sudo_unlock_api.py"
SERVICE_FILE="/etc/systemd/system/sudo-unlock-api.service"
VENV_DIR="$APP_DIR/venv"

# ============================
# MUST RUN AS ROOT
# ============================
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run as root: sudo bash $0"
  exit 1
fi

echo "✅ Installing Password Reset API on port ${PORT}"
echo "✅ New password to set: ${NEW_PASSWORD}"
echo "✅ URL: http://<IP>:${PORT}/unlocked/<username>"

# ============================
# Install deps
# ============================
echo "📦 Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv curl psmisc

# ============================
# Detect public IPv4
# ============================
PUBLIC_IP="$(curl -4 -s ifconfig.me || true)"
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(curl -4 -s ipinfo.io/ip || true)"
fi
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(hostname -I | awk '{print $1}')"
fi
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="YOUR_SERVER_IP"
fi

echo "🌍 Detected public IPv4: ${PUBLIC_IP}"

# ============================
# Create app directory
# ============================
echo "📁 Creating app directory: ${APP_DIR}"
mkdir -p "$APP_DIR"

# ============================
# Write Flask API (PASSWORD RESET ONLY)
# ============================
echo "📝 Writing Flask API to: ${APP_FILE}"
cat > "$APP_FILE" <<EOF
from flask import Flask, jsonify
import subprocess

app = Flask(__name__)
NEW_PASSWORD = "${NEW_PASSWORD}"

def run_cmd(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def user_exists(username):
    return run_cmd(["id", username])[0] == 0

def set_password(username, password):
    # Use chpasswd (most reliable)
    code, out, err = run_cmd(["bash", "-lc", f'echo "{username}:{password}" | chpasswd'])
    return code == 0, (err or out or "ok")

@app.route("/unlocked/<username>", methods=["GET"])
def reset_password(username):
    if not user_exists(username):
        return jsonify({
            "status": "error",
            "message": "User does not exist",
            "user": username
        }), 404

    ok, msg = set_password(username, NEW_PASSWORD)
    if not ok:
        return jsonify({
            "status": "error",
            "message": "Failed to change password",
            "details": msg,
            "user": username
        }), 500

    return jsonify({
        "status": "success",
        "message": "Password changed",
        "user": username,
        "new_password": NEW_PASSWORD
    }), 200

if __name__ == "__main__":
    app.run(host="${BIND_HOST}", port=${PORT})
EOF

# ============================
# Setup venv
# ============================
echo "🐍 Creating Python venv..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install flask

# ============================
# Create systemd service
# ============================
echo "⚙️ Creating systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Password Reset API (Flask)
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${VENV_DIR}/bin/python ${APP_FILE}
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# ============================
# Start service CLEANLY (kills anything on port)
# ============================
echo "🚀 Starting service cleanly..."
systemctl daemon-reload
systemctl enable sudo-unlock-api || true
systemctl stop sudo-unlock-api || true
fuser -k ${PORT}/tcp || true
systemctl start sudo-unlock-api

# ============================
# Open firewall
# ============================
echo "🔥 Opening firewall port ${PORT}..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp || true
  ufw reload || true
else
  iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT || true
fi

echo ""
echo "✅ DONE!"
echo ""
echo "🌍 Password reset URL:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/<username>"
echo ""
echo "Example:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/root"
echo ""
echo "Password it sets:"
echo "   ${NEW_PASSWORD}"
echo ""
echo "Check service:"
echo "   systemctl status sudo-unlock-api --no-pager"
echo ""
echo "Check listening:"
echo "   ss -lntp | grep ':${PORT}'"
echo ""
echo "⚠️ WARNING: PUBLIC + NO AUTH = ANYONE CAN RESET PASSWORDS."
echo "Strongly recommended: firewall allow only your IP."
