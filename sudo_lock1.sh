#!/bin/bash
set -e

PORT=5001
BIND_HOST="0.0.0.0"   # PUBLIC ACCESS
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

# ============================
# Install deps
# ============================
echo "📦 Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv curl

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

echo "🌍 Detected public IPv4: $PUBLIC_IP"

# ============================
# Create app directory
# ============================
echo "📁 Creating app directory: $APP_DIR"
mkdir -p "$APP_DIR"

# ============================
# Write API (LATEST)
# ============================
echo "📝 Writing Flask API to: $APP_FILE"
cat > "$APP_FILE" <<EOF
from flask import Flask, jsonify
import subprocess
import shutil

app = Flask(__name__)

NEW_PASSWORD = "${NEW_PASSWORD}"

def run_cmd(cmd):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)

def user_exists(username):
    return run_cmd(["id", username])[0] == 0

def get_shell(username):
    code, out, err = run_cmd(["bash", "-lc", f"getent passwd {username} | cut -d: -f7"])
    if code != 0 or not out:
        return None, err or out
    return out.strip(), None

def shadow_pw_field(username):
    code, out, err = run_cmd(["bash", "-lc", f"getent shadow {username} | cut -d: -f2"])
    if code != 0 or not out:
        return None, err or out
    return out.strip(), None

def passwd_status(username):
    code, out, err = run_cmd(["passwd", "-S", username])
    if code != 0 or not out:
        return None, err or out
    parts = out.split()
    if len(parts) < 2:
        return None, "Unexpected passwd -S output"
    return parts[1].strip(), None

def is_shadow_locked(username):
    pw, err = shadow_pw_field(username)
    if err:
        return None, err

    if pw.startswith("!") or pw.startswith("*"):
        return True, None

    if pw == "":
        return True, None

    return False, None

def is_shell_nonlogin(username):
    shell, err = get_shell(username)
    if err:
        return None, err
    shell_l = shell.lower()
    if shell_l.endswith("/nologin") or shell_l.endswith("/false"):
        return True, None
    return False, None

def is_no_password_state(username):
    st, err = passwd_status(username)
    if err:
        return None, err
    if st in ("NP", "N", "NO", "PS"):
        return True, None
    return False, None

def is_account_expired(username):
    code, out, err = run_cmd(["chage", "-l", username])
    if code != 0:
        return None, err or out
    for line in out.splitlines():
        if "Account expires" in line:
            return ("never" not in line.lower()), None
    return False, None

def is_pam_locked(username):
    if shutil.which("faillock"):
        code, out, err = run_cmd(["faillock", "--user", username])
        if code == 0 and out:
            if "locked" in out.lower():
                return True, None
            if "failures" in out.lower() and any(ch.isdigit() for ch in out):
                return True, None

    if shutil.which("pam_tally2"):
        code, out, err = run_cmd(["pam_tally2", "--user", username])
        if code == 0 and out:
            parts = out.split()
            if len(parts) >= 2 and parts[1].isdigit() and int(parts[1]) > 0:
                return True, None

    return False, None

def set_password(username, password):
    code, out, err = run_cmd(["bash", "-lc", f'echo "{username}:{password}" | chpasswd'])
    return (code == 0), (err or out or "ok")

def unlock_user_all(username):
    actions = []

    code, out, err = run_cmd(["passwd", "-u", username])
    actions.append("passwd -u" if code == 0 else f"passwd -u failed: {err or out}")

    code, out, err = run_cmd(["usermod", "-U", username])
    actions.append("usermod -U" if code == 0 else f"usermod -U failed: {err or out}")

    if shutil.which("faillock"):
        code, out, err = run_cmd(["faillock", "--user", username, "--reset"])
        actions.append("faillock --reset" if code == 0 else f"faillock reset failed: {err or out}")

    if shutil.which("pam_tally2"):
        code, out, err = run_cmd(["pam_tally2", "--user", username, "--reset"])
        actions.append("pam_tally2 --reset" if code == 0 else f"pam_tally2 reset failed: {err or out}")

    code, out, err = run_cmd(["chage", "-E", "-1", username])
    actions.append("chage -E -1" if code == 0 else f"chage -E -1 failed: {err or out}")

    ok, msg = set_password(username, NEW_PASSWORD)
    actions.append(f"password set to {NEW_PASSWORD}" if ok else f"password set failed: {msg}")

    return actions

@app.route("/unlocked/<username>", methods=["GET"])
def unlock(username):
    if not user_exists(username):
        return jsonify({"status": "error", "message": "User does not exist"}), 404

    shadow_locked, e1 = is_shadow_locked(username)
    shell_nonlogin, e2 = is_shell_nonlogin(username)
    no_pw_state, e3 = is_no_password_state(username)
    expired, e4 = is_account_expired(username)
    pam_locked, e5 = is_pam_locked(username)

    for e in (e1, e2, e3, e4, e5):
        if e:
            return jsonify({"status": "error", "message": e}), 500

    locked = any([shadow_locked, shell_nonlogin, no_pw_state, expired, pam_locked])

    if not locked:
        return jsonify({
            "status": "unlocked",
            "user": username,
            "unlocked": True,
            "message": "User is not locked",
            "password": NEW_PASSWORD
        }), 200

    actions = unlock_user_all(username)

    shadow_locked2, _ = is_shadow_locked(username)
    shell_nonlogin2, _ = is_shell_nonlogin(username)
    no_pw_state2, _ = is_no_password_state(username)
    expired2, _ = is_account_expired(username)
    pam_locked2, _ = is_pam_locked(username)
    locked2 = any([shadow_locked2, shell_nonlogin2, no_pw_state2, expired2, pam_locked2])

    return jsonify({
        "status": "success",
        "user": username,
        "was_locked": True,
        "unlocked": (not locked2),
        "new_password": NEW_PASSWORD,
        "lock_reasons_before": {
            "shadow_locked": shadow_locked,
            "shell_nonlogin": shell_nonlogin,
            "no_password_state": no_pw_state,
            "account_expired": expired,
            "pam_locked": pam_locked
        },
        "lock_reasons_after": {
            "shadow_locked": shadow_locked2,
            "shell_nonlogin": shell_nonlogin2,
            "no_password_state": no_pw_state2,
            "account_expired": expired2,
            "pam_locked": pam_locked2
        },
        "actions": actions
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
Description=Sudo Unlock API (Flask)
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
# Start service cleanly
# ============================
echo "🚀 Starting service..."
systemctl daemon-reload
systemctl enable sudo-unlock-api
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
echo "🌍 Browser URL:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/<username>"
echo ""
echo "Example:"
echo "   http://${PUBLIC_IP}:${PORT}/unlocked/root"
echo ""
echo "Default new password set after unlock:"
echo "   ${NEW_PASSWORD}"
echo ""
echo "Check service:"
echo "   systemctl status sudo-unlock-api --no-pager"
echo ""
echo "Check listening:"
echo "   ss -lntp | grep ':${PORT}'"
echo ""
echo "⚠️ WARNING: This API is PUBLIC and has NO AUTH."
echo "Anyone who can access it can unlock users and reset passwords."
