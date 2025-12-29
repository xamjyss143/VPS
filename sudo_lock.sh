#!/bin/bash
set -e

# ============================
# CONFIG (edit these)
# ============================
PORT=5001
API_KEY="CHANGE_ME_SUPER_SECRET"
BIND_HOST="127.0.0.1"   # safer default; change to 0.0.0.0 if you really want public access

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

echo "✅ Setting up sudo unlock API on port $PORT..."

# ============================
# Install dependencies
# ============================
echo "📦 Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv

# ============================
# Create app directory
# ============================
echo "📁 Creating app directory: $APP_DIR"
mkdir -p "$APP_DIR"

# ============================
# Create Python app
# ============================
echo "📝 Writing Flask app to $APP_FILE"
cat > "$APP_FILE" <<EOF
from flask import Flask, jsonify, request
import subprocess
import shutil

app = Flask(__name__)
API_KEY = "${API_KEY}"

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
    # passwd -S user -> second field = L (locked) or P (active)
    code, out, err = run_cmd(["passwd", "-S", username])
    if code != 0:
        return None, f"passwd -S failed: {err or out}"

    parts = out.split()
    if len(parts) >= 2:
        status = parts[1]
        return (status == "L"), None

    return None, "Unexpected passwd -S output"

def unlock_account(username):
    actions = []

    # Unlock the account itself
    code, out, err = run_cmd(["passwd", "-u", username])
    if code == 0:
        actions.append("passwd -u")
    else:
        actions.append(f"passwd -u failed: {err or out}")

    # Reset faillock if present
    if shutil.which("faillock"):
        code, out, err = run_cmd(["faillock", "--user", username, "--reset"])
        if code == 0:
            actions.append("faillock --reset")
        else:
            actions.append(f"faillock reset failed: {err or out}")

    # Reset pam_tally2 if present
    if shutil.which("pam_tally2"):
        code, out, err = run_cmd(["pam_tally2", "--user", username, "--reset"])
        if code == 0:
            actions.append("pam_tally2 --reset")
        else:
            actions.append(f"pam_tally2 reset failed: {err or out}")

    return actions

@app.route("/unlocked/<username>", methods=["GET"])
def unlock_user(username):
    # API key protection
    client_key = request.headers.get("X-API-KEY")
    if client_key != API_KEY:
        return jsonify({"status": "error", "message": "Unauthorized"}), 401

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
# Setup virtualenv
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
Description=Sudo Unlock API (Flask)
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

echo ""
echo "✅ DONE!"
echo "Service status:"
systemctl --no-pager status sudo-unlock-api | head -n 20

echo ""
echo "🔗 API endpoint:"
echo "   http://<VPS-IP>:${PORT}/unlocked/<username>"
echo ""
echo "🔑 Use this header:"
echo "   X-API-KEY: ${API_KEY}"
echo ""
echo "Example test (localhost):"
echo "   curl -H \"X-API-KEY: ${API_KEY}\" http://127.0.0.1:${PORT}/unlocked/testuser"
echo ""
echo "⚠️ IMPORTANT SECURITY NOTE:"
echo "Currently binds to ${BIND_HOST}. If you change to 0.0.0.0, firewall it!"
