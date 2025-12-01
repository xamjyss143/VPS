#!/bin/bash
set -e

APP_DIR="/opt/vps-status-api"
SERVICE_NAME="vps-status"

echo "[1/3] Installing Python + Flask + vnStat..."
apt update -y
apt install -y python3 python3-flask vnstat

echo "[2/3] Creating API directory..."
mkdir -p "$APP_DIR"

echo "[Writing app.py...]"
cat > "$APP_DIR/app.py" <<'EOF'
#!/usr/bin/env python3
from flask import Flask, request, Response
import subprocess, json, os

app = Flask(__name__)
TCP_STATUS_FILE = "/etc/openvpn/tcp_stats.log"

def get_default_iface():
    try:
        return subprocess.check_output(
            "ip -4 route ls | grep default | grep -Po '(?<=dev )\\S+' | head -1",
            shell=True, text=True
        ).strip() or "eth0"
    except:
        return "eth0"

def size_to_bytes(s):
    if not s:
        return 0
    num, unit = s.split()
    num = float(num)
    unit = unit.lower()
    m = {"b":1,"kib":1024,"mib":1024**2,"gib":1024**3,"tib":1024**4}
    return int(num * m.get(unit, 1))

def get_network_usage():
    iface = get_default_iface()
    try:
        line = subprocess.check_output(
            f"vnstat --oneline -i {iface}", shell=True, text=True
        ).strip()
    except:
        return {"ext_iface": iface, "main_usage": "0 B"}

    parts = line.split(";")
    if len(parts) < 11:
        return {"ext_iface": iface, "main_usage": "0 B"}

    return {"ext_iface": iface, "main_usage": parts[10].strip()}

def get_ssh_users():
    users = []
    try:
        for line in open("/etc/passwd"):
            p = line.split(":")
            if len(p) > 2:
                try:
                    uid = int(p[2])
                    if 1000 <= uid <= 10000:
                        users.append(p[0])
                except:
                    pass
    except:
        return 0

    total = 0
    for u in users:
        try:
            out = subprocess.check_output(
                ["ps", "-u", u, "-o", "comm="], text=True
            )
            total += sum(1 for l in out.splitlines() if "sshd" in l)
        except:
            pass
    return total

def get_openvpn_tcp_users():
    if not os.path.exists(TCP_STATUS_FILE):
        return 0
    try:
        count = sum(1 for l in open(TCP_STATUS_FILE, errors="ignore") if "CLIENT_LIST" in l)
        return max(count - 1, 0)
    except:
        return 0

def get_system_info():
    try:
        cpu = subprocess.check_output(
            "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'",
            shell=True, text=True
        ).strip()
    except:
        cpu = "0.0"

    try:
        mem = subprocess.check_output("free -m", shell=True, text=True).splitlines()[1].split()
        used, total = int(mem[2]), int(mem[1])
    except:
        used = total = 0

    return {
        "cpu_usage": f"{cpu}%",
        "ram_usage": f"{used/1024:.1f}GB/{total/1024:.1f}GB"
    }

SERVICES = {
    "multiplexer":"JuanTCP.service",
    "ssh":"juansshd.service",
    "slowdns":"JuanDNSTT.service",
    "websocket":"JuanWS.service",
    "stunnel":"stunnel4.service",
    "openvpn":"openvpn-server@tcp.service",
    "nginx":"nginx.service",
    "xray":"xray.service",
    "hysteria":"udp.service",
    "ddos":"ddos.service",
    "badvpn":"badvpn-udpgw.service",
    "squid":"squid.service"
}

def check_service(unit):
    return "active" if subprocess.call(
        ["systemctl","is-active","--quiet",unit]
    ) == 0 else "inactive"

@app.route("/status")
def status():
    data = {
        "server_ip": request.host.split(":")[0],
        "network": get_network_usage(),
        "online_users": {
            "ssh": get_ssh_users(),
            "openvpn_tcp": get_openvpn_tcp_users()
        },
        "system": get_system_info(),
        "services": {k:check_service(v) for k,v in SERVICES.items()}
    }

    return Response(json.dumps(data, indent=4), mimetype="application/json")

@app.route("/")
def home():
    return Response(json.dumps({"message":"Use /status"}, indent=4), mimetype="application/json")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

chmod +x "$APP_DIR/app.py"

echo "[3/3] Creating systemd service..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=VPS Status API (Flask)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
WorkingDirectory=${APP_DIR}
Restart=always
RestartSec=3
User=root
Environment=PYTHONUNBUFFERED=1
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

echo "=============================================="
echo "API Running: http://YOUR_IP:5000/status"
echo "Service: systemctl status ${SERVICE_NAME}"
echo "=============================================="
