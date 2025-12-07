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
import subprocess, json, os, re, sys

app = Flask(__name__)
TCP_STATUS_FILE = "/etc/openvpn/tcp_stats.log"

# ============================================================
#  SMALL HELPERS
# ============================================================
def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except Exception:
        return ""

def read_first_line(path):
    try:
        with open(path, "r", errors="ignore") as f:
            return f.readline().strip()
    except Exception:
        return ""

# ============================================================
#  DEFAULT IFACE + VNSTAT
# ============================================================
def get_default_iface():
    out = run_cmd("ip -4 route ls | grep default | grep -Po '(?<=dev )\\S+' | head -1")
    return out if out else "eth0"

def get_network_usage():
    iface = get_default_iface()
    try:
        line = subprocess.check_output(
            f"vnstat --oneline -i {iface}", shell=True, text=True
        ).strip()
    except Exception:
        return {"ext_iface": iface, "main_usage": "0 B"}

    parts = line.split(";")
    if len(parts) < 11:
        return {"ext_iface": iface, "main_usage": "0 B"}

    month_total = parts[10].strip()
    return {
        "ext_iface": iface,
        "main_usage": month_total
    }

# ============================================================
#  SSH + OVPN USERS
# ============================================================
def get_ssh_users():
    users = []
    try:
        with open("/etc/passwd", "r", errors="ignore") as f:
            for line in f:
                p = line.split(":")
                if len(p) > 2:
                    try:
                        uid = int(p[2])
                        if 1000 <= uid <= 10000:
                            users.append(p[0])
                    except Exception:
                        pass
    except Exception:
        return 0

    total = 0
    for u in users:
        try:
            out = subprocess.check_output(
                ["ps", "-u", u, "-o", "comm="], text=True
            )
            total += sum(1 for l in out.splitlines() if "sshd" in l)
        except Exception:
            pass
    return total

def get_openvpn_tcp_users():
    if not os.path.exists(TCP_STATUS_FILE):
        return 0
    try:
        with open(TCP_STATUS_FILE, "r", errors="ignore") as f:
            count = sum(1 for l in f if "CLIENT_LIST" in l)
        return max(count - 1, 0)
    except Exception:
        return 0

# ============================================================
#  HYSTERIA (udp.service) ACTIVE DEVICE COUNT
# ============================================================
def get_hysteria_users():
    """
    Tracks active device connections based on ip:port.
    Even if 2 devices share same IP, each unique ip:port counts as 1 device.
    """
    try:
        proc = subprocess.Popen(
            ["journalctl", "-u", "udp.service", "-b", "--no-pager"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except Exception:
        return 0

    conn = {}  # ip:port -> active stream count
    pattern = re.compile(r"\[src:([0-9a-fA-F\.:]+):(\d+)\]")

    if not proc.stdout:
        return 0

    for line in proc.stdout:
        m = pattern.search(line)
        if not m:
            continue

        ip = m.group(1)
        port = m.group(2)
        ipport = f"{ip}:{port}"

        # TCP request opens stream
        if "TCP request" in line:
            conn[ipport] = conn.get(ipport, 0) + 1

        # TCP EOF / error closes stream
        if "TCP EOF" in line or "TCP error" in line:
            if conn.get(ipport, 0) > 0:
                conn[ipport] -= 1

        # Client disconnected → clear all streams for that IP
        if "Client disconnected" in line:
            for k in list(conn.keys()):
                if k.startswith(ip + ":"):
                    conn[k] = 0

    # 🔥 Count DEVICE connections = each ip:port with >0 streams
    active_devices = sum(1 for v in conn.values() if v > 0)
    return active_devices

# ============================================================
#  META + SPECS (for infoPage)
# ============================================================
def get_meta_and_specs():
    host = run_cmd("hostname") or run_cmd("uname -n")

    pretty_os = ""
    try:
        with open("/etc/os-release", "r", errors="ignore") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    pretty_os = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    except Exception:
        pass
    if not pretty_os:
        pretty_os = run_cmd("lsb_release -ds") or run_cmd("uname -s")

    kernel = run_cmd("uname -r")

    cpu_model = ""
    try:
        with open("/proc/cpuinfo", "r", errors="ignore") as f:
            for line in f:
                if "model name" in line:
                    cpu_model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    if not cpu_model:
        cpu_model = run_cmd("lscpu | awk -F: '/Model name/ {print $2; exit}'").strip()

    meta = {
        "host": host or "—",
        "os": pretty_os or "—",
        "kernel": kernel or "—",
        "cpu": cpu_model or "—",
    }

    # Disk
    disk_total = disk_used = disk_free = "—"
    disk_num = {"total_gb": 0, "used_gb": 0, "free_gb": 0}

    df_h = run_cmd("df -h / | awk 'NR==2{print $2\"|\"$3\"|\"$4}'")
    if df_h:
        parts = df_h.split("|")
        if len(parts) >= 3:
            disk_total, disk_used, disk_free = parts

    df_b = run_cmd("df -B1 / | awk 'NR==2{print $2\"|\"$3\"|\"$4}'")
    if df_b:
        p = df_b.split("|")
        if len(p) >= 3:
            try:
                disk_num = {
                    "total_gb": round(int(p[0]) / 1024**3),
                    "used_gb":  round(int(p[1]) / 1024**3),
                    "free_gb":  round(int(p[2]) / 1024**3),
                }
            except:
                pass

    # RAM
    ram_total = ram_used = ram_free = 0
    try:
        with open("/proc/meminfo", "r") as f:
            total = avail = 0
            for line in f:
                if line.startswith("MemTotal:"):
                    total = int(line.split()[1])
                if line.startswith("MemAvailable:"):
                    avail = int(line.split()[1])
            if total > 0:
                ram_total = round(total / 1024)
                ram_free = round(avail / 1024)
                ram_used = ram_total - ram_free
    except:
        pass

    # CPU usage
    cpu_pct = 0.0
    vm = run_cmd("vmstat 1 2 | tail -1")
    if vm:
        cols = vm.split()
        if len(cols) >= 15:
            try:
                cpu_pct = max(0, min(100, 100 - float(cols[14])))
            except:
                pass

    specs = {
        "vcpu": int(run_cmd("nproc") or 0),
        "ram_mb": ram_total,
        "ram_used_mb": ram_used,
        "ram_free_mb": ram_free,
        "disk": {
            "total": disk_total,
            "used": disk_used,
            "free": disk_free,
        },
        "disk_num": disk_num,
        "cpu_pct": cpu_pct,
    }

    return meta, specs

# ============================================================
#  SERVICES
# ============================================================
SERVICES = {
    "multiplexer": "JuanTCP.service",
    "ssh": "juansshd.service",
    "slowdns": "JuanDNSTT.service",
    "websocket": "JuanWS.service",
    "stunnel": "stunnel4.service",
    "openvpn": "openvpn-server@tcp.service",
    "nginx": "nginx.service",
    "xray": "xray.service",
    "hysteria": "udp.service",
    "ddos": "ddos.service",
    "badvpn": "badvpn-udpgw.service",
    "squid": "squid.service"
}

def check_service(unit):
    try:
        return "active" if subprocess.call(
            ["systemctl", "is-active", "--quiet", unit]
        ) == 0 else "inactive"
    except:
        return "inactive"

def get_services_status():
    return {name: check_service(unit) for name, unit in SERVICES.items()}

# ============================================================
#  UUID + KEY
# ============================================================
def get_uuid_and_key():
    return read_first_line("/etc/xray/uuid"), read_first_line("/etc/JuanScript/server.pub")

# ============================================================
#  ROUTES
# ============================================================
@app.route("/status")
def status():
    meta, specs = get_meta_and_specs()
    u, k = get_uuid_and_key()

    data = {
        "server_ip": request.host.split(":")[0],
        "network": get_network_usage(),
        "online_users": {
            "ssh": get_ssh_users(),
            "openvpn_tcp": get_openvpn_tcp_users(),
            "hysteria_udp": get_hysteria_users()
        },
        "system": get_system_info(),
        "meta": meta,
        "specs": specs,
        "services": get_services_status(),
        "uuid": u,
        "key": k,
    }

    return Response(json.dumps(data, indent=4), mimetype="application/json")

@app.route("/")
def home():
    return Response(json.dumps({"message": "Use /status"}, indent=4), mimetype="application/json")

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
