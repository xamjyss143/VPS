#!/bin/bash
set -e

PORT=5001
BIND_HOST="0.0.0.0"   # PUBLIC ACCESS

APP_DIR="/opt/sudo-unlock-api"
APP_FILE="$APP_DIR/sudo_unlock_api.py"
SERVICE_FILE="/etc/systemd/system/sudo-unlock-api.service"
VENV_DIR="$APP_DIR/venv"

# ============================
# MUST RUN AS ROOT
# ============================
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run this script as root: sudo bash $0"
  exit 1
fi

# ============================
# Detect public IPv4
# ============================
PUBLIC_IP="$(curl -4 -s ifconfig.me || true)"

if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(curl -4 -s ipinfo.io/ip || true)"
fi

if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="YOUR_SERVER_IP"
fi

echo "🌍 Detected public IPv4: $PUBLIC_IP"

echo "✅ Installing Sudo Unlock API on port $PORT (NO AUTH, PUBLIC)..."

# ============================
# Install dependencies
# ============================
echo "📦 Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv curl

# ============================
# Create app directory
# ============================
echo "📁 Creating app directory: $APP_DIR"
mkdir -p "$APP_DIR"

# ============================
# Create Python Flask API (NO AUTH)
# ============================
echo "📝 Writing Flask app to $APP_FILE"
cat > "$APP_FILE" <<EOF
from flask import Flask, jsonify
import subprocess
import shutil

app = Flask(__name__)

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)

def user_exists(username):
    code, _, _ = run_cmd(["id", username])
    return code == 0

def is_account_locked(username):
    code, out, err = run_cmd(["passwd", "-S", username])
    if code != 0:
        return None, err or out

    parts = out.split()
    if len(parts) >= 2:
        return parts[1] == "L", None

    return None, "Unexpected passwd -S output"

def unlock_account(username):
    actions = []

    code, out, err = run_cmd(["passwd", "-u", username])
    if code == 0:
        actions.append("passwd -u")
    else:
        actions.append(f"passwd -u failed: {err or out}")

    if shutil.which("faillock"):
        code, out, err = run_cmd(["faillock", "--user", username, "--reset"])
        if code == 0:
            actions.append("faillock --reset")
        else:
            actions.append(f"faillock failed: {err or out}")

    if shutil.which("pam_tally2"):
        code, out, err = run_cmd(["pam_tally2", "--user", username, "--reset"])
        if code == 0:
            actions.append("pam_tally2 --reset")
        else:
            actions.append(f"pam_tally2 failed: {err or out}")

    return actions

@app.route("/unlocked/<username>", methods=["GET"])
def unlock_user(username):

    if not user_exists(username):
        return jsonify({"status": "error", "message": "User does not exist"}), 404

    locked, err = is_account_locked(username)
    if err:
        return jsonify({"status": "error", "message": err}), 500

    if locked is False:
        return jsonify({
            "status": "unlocked",
            "user": username,
            "unlocked": True,
            "message": "User is not locked"
        }), 200

    actions = unlock_account(username)

    locked_after, err = is_account_locked(username)
    if err:
        return jsonify({"status": "error", "message": err, "actions": actions}), 500

    return jsonify({
        "status": "success",
        "user": username,
        "was_locked": True,
        "unlocked": (locked_after is False),
        "actions": actions
    }), 200

if __name__ == "__main__":
    app.run(host="${BIND_HOST}", port=${PORT})
EOF

# ============================
# Setup Python venv
# ============================
echo "🐍 Creating Python venv..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install flask

# ============================
# Create systemd service
# ============================
echo "⚙️ Creating systemd service: $SERVICE_FILE"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sudo Unlock API (Flask - NO AUTH)
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/python $APP_FILE
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# ============================
# Enable + Start service
# ============================
echo "🚀 Enabling and starting service..."
systemctl daemon-reload
systemctl enable sudo-unlock-api
systemctl restart sudo-unlock-api

# ============================
# Open firewall
# ============================
echo "🔥 Opening firewall port $PORT..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp || true
  ufw reload || true
else
  iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT || true
fi

echo ""
echo "✅ DONE!"
echo ""
echo "🌍 Browser URLs:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/<username>"
echo ""
echo "Example:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/root"
echo ""
echo "Check service:"
echo "   systemctl status sudo-unlock-api --no-pager"
echo ""
echo "Check listening:"
echo "   ss -tulnp | grep ${PORT}"
echo ""
echo "⚠️ WARNING: This API is PUBLIC and has NO AUTH."
echo "Anyone who reaches it can unlock users."
