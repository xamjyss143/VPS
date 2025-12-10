#!/bin/bash
set -e

APP_DIR="/opt/vps-status-api"
SERVICE_NAME="vps-status"

echo "[1/4] Installing Python + Flask + vnStat..."
apt update -y
apt install -y python3 python3-flask vnstat curl

echo "[2/4] Creating API directory..."
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

def size_to_bytes(s):
    if not s:
        return 0
    parts = s.split()
    if len(parts) != 2:
        return 0
    num, unit = parts
    try:
        num = float(num)
    except Exception:
        return 0
    unit = unit.lower()
    m = {"b": 1, "kib": 1024, "mib": 1024**2, "gib": 1024**3, "tib": 1024**4}
    return int(num * m.get(unit, 1))

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

    # parts[10] is monthly total e.g. "151.54 GiB"
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
#  HYSTERIA (udp.service) ACTIVE USERS
# ============================================================
def get_hysteria_users():
    """
    Count active Hysteria UDP clients based on number of:
        'Client connected'
    minus
        'Client disconnected'
    since the last 'Server up and running' marker.

    - Multiple connections from the SAME IP are all counted.
    - If there are 4 connects and 1 disconnect, result = 3.
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

    if not proc.stdout:
        return 0

    active = 0

    for line in proc.stdout:
        # Reset from last server start marker
        if "Server up and running" in line:
            active = 0
            continue

        if "Client connected" in line:
            active += 1
        elif "Client disconnected" in line:
            if active > 0:
                active -= 1

    if active < 0:
        active = 0

    return active

# ============================================================
#  META + SPECS (for infoPage)
# ============================================================
def get_meta_and_specs():
    # --- META ---
    host = run_cmd("hostname")
    if not host:
        host = run_cmd("uname -n")

    # OS pretty name
    pretty_os = ""
    try:
        with open("/etc/os-release", "r", errors="ignore") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    val = line.split("=", 1)[1].strip()
                    pretty_os = val.strip('"').strip("'")
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
        # fallback to lscpu output
        out = run_cmd("lscpu | awk -F: '/Model name/ {print $2; exit}'")
        cpu_model = out.strip()

    meta = {
        "host": host or "—",
        "os": pretty_os or "—",
        "kernel": kernel or "—",
        "cpu": cpu_model or "—",
    }

    # --- SPECS / DISK ---
    disk_total_bytes = disk_used_bytes = disk_free_bytes = 0
    disk_total_h = disk_used_h = disk_free_h = "—"

    df_bytes = run_cmd("df -B1 / 2>/dev/null | awk 'NR==2{print $2\"|\"$3\"|\"$4}'")
    if df_bytes:
        parts = df_bytes.split("|")
        if len(parts) >= 3:
            try:
                disk_total_bytes = int(parts[0])
                disk_used_bytes  = int(parts[1])
                disk_free_bytes  = int(parts[2])
            except Exception:
                pass

    df_h = run_cmd("df -h / 2>/dev/null | awk 'NR==2{print $2\"|\"$3\"|\"$4}'")
    if df_h:
        parts_h = df_h.split("|")
        if len(parts_h) >= 3:
            disk_total_h = parts_h[0] or "—"
            disk_used_h  = parts_h[1] or "—"
            disk_free_h  = parts_h[2] or "—"

    if disk_total_bytes > 0:
        disk_num = {
            "total_gb": round(disk_total_bytes / (1024**3)),
            "used_gb":  round(disk_used_bytes  / (1024**3)),
            "free_gb":  round(disk_free_bytes  / (1024**3)),
        }
    else:
        disk_num = {"total_gb": 0, "used_gb": 0, "free_gb": 0}

    disk_h = {
        "total": disk_total_h,
        "used":  disk_used_h,
        "free":  disk_free_h,
    }

    # --- RAM ---
    ram_total_mb = ram_used_mb = ram_free_mb = 0

    try:
        mem_total_kb = mem_avail_kb = 0
        with open("/proc/meminfo", "r", errors="ignore") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    mem_total_kb = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    mem_avail_kb = int(line.split()[1])
        if mem_total_kb > 0:
            ram_total_mb = round(mem_total_kb / 1024)
            avail_mb     = round(mem_avail_kb / 1024)
            ram_used_mb  = max(0, ram_total_mb - avail_mb)
            ram_free_mb  = avail_mb
    except Exception:
        # fallback to `free -m`
        out = run_cmd("free -m | awk '/^Mem:/ {print $2\"|\"$7\"|\"$3}'")
        if out:
            parts = out.split("|")
            if len(parts) >= 3:
                try:
                    t = int(parts[0])
                    a = int(parts[1])
                    u = int(parts[2])
                    ram_total_mb = t
                    ram_used_mb  = max(0, t - a)
                    ram_free_mb  = a
                except Exception:
                    pass

    # --- CPU PCT (like vmstat logic) ---
    cpu_pct = 0.0
    vm_out = run_cmd("vmstat 1 2 | tail -1")
    if vm_out:
        cols = vm_out.split()
        # idle is usually the 15th column; we just guard by length
        try:
            if len(cols) >= 15:
                idle = float(cols[14])
                cpu_pct = max(0.0, min(100.0, 100.0 - idle))
        except Exception:
            pass

    # --- VCPU COUNT ---
    vcpu = 0
    out_nproc = run_cmd("nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 0")
    if out_nproc:
        try:
            vcpu = int(out_nproc)
        except Exception:
            vcpu = 0

    specs = {
        "vcpu": vcpu if vcpu > 0 else "—",
        "ram_mb": ram_total_mb,
        "ram_used_mb": ram_used_mb,
        "ram_free_mb": ram_free_mb,
        "disk": disk_h,
        "disk_num": disk_num,
        "cpu_pct": cpu_pct,
    }

    return meta, specs

# ============================================================
#  SYSTEM (simple CPU/RAM string for existing AJAX)
# ============================================================
def get_system_info():
    # CPU % (string)
    cpu_pct_str = "0.0"
    vm_out = run_cmd("vmstat 1 2 | tail -1")
    if vm_out:
        cols = vm_out.split()
        try:
            if len(cols) >= 15:
                idle = float(cols[14])
                cpu_pct_val = max(0.0, min(100.0, 100.0 - idle))
                cpu_pct_str = f"{cpu_pct_val:.1f}"
        except Exception:
            pass

    # RAM used/total (GB)
    used_mb = total_mb = 0
    try:
        with open("/proc/meminfo", "r", errors="ignore") as f:
            mem_total_kb = mem_avail_kb = 0
            for line in f:
                if line.startswith("MemTotal:"):
                    mem_total_kb = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    mem_avail_kb = int(line.split()[1])
        if mem_total_kb > 0:
            total_mb = round(mem_total_kb / 1024)
            avail_mb = round(mem_avail_kb / 1024)
            used_mb  = max(0, total_mb - avail_mb)
    except Exception:
        out = run_cmd("free -m | awk '/^Mem:/ {print $2\"|\"$7\"|\"$3}'")
        if out:
            parts = out.split("|")
            if len(parts) >= 3:
                try:
                    t = int(parts[0])
                    a = int(parts[1])
                    u = int(parts[2])
                    total_mb = t
                    used_mb  = max(0, t - a)
                except Exception:
                    pass

    used_gb  = used_mb / 1024.0 if total_mb > 0 else 0.0
    total_gb = total_mb / 1024.0 if total_mb > 0 else 0.0

    return {
        "cpu_usage": f"{cpu_pct_str}%",
        "ram_usage": f"{used_gb:.1f}GB/{total_gb:.1f}GB"
    }

# ============================================================
#  SERVICE CHECKS
# ============================================================
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
    try:
        return "active" if subprocess.call(
            ["systemctl", "is-active", "--quiet", unit]
        ) == 0 else "inactive"
    except Exception:
        return "inactive"

def get_services_status():
    return {name: check_service(unit) for name, unit in SERVICES.items()}

# ============================================================
#  UUID / KEY (best-effort, used by infoPage)
# ============================================================
def get_uuid_and_key():
    uuid = read_first_line("/etc/xray/uuid")
    key  = read_first_line("/etc/JuanScript/server.pub")
    return uuid, key

# ============================================================
#  API ROUTES
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
    return Response(json.dumps({"message":"Use /status"}, indent=4), mimetype="application/json")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

chmod +x "$APP_DIR/app.py"

echo "[3/4] Creating main systemd service (Restart=always)..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=VPS Status API (Flask)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
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

echo "[3.5/4] Creating global healthcheck (restart ALL services if API is down)..."
cat > /usr/local/bin/${SERVICE_NAME}-healthcheck.sh <<'EOF'
#!/bin/bash
URL="http://127.0.0.1:5000/status"

# Try once (you can add retries here if you want)
if curl -fsS --max-time 5 "$URL" >/dev/null 2>&1; then
    exit 0
fi

echo "[healthcheck] $URL unreachable, restarting core services..."

SERVICES=(
  "vps-status.service"
  "JuanTCP.service"
  "juansshd.service"
  "JuanDNSTT.service"
  "JuanWS.service"
  "stunnel4.service"
  "openvpn-server@tcp.service"
  "nginx.service"
  "xray.service"
  "udp.service"
  "ddos.service"
  "badvpn-udpgw.service"
  "squid.service"
)

for svc in "${SERVICES[@]}"; do
    echo " - restarting $svc"
    systemctl restart "$svc" 2>/dev/null || true
done
EOF

chmod +x /usr/local/bin/${SERVICE_NAME}-healthcheck.sh

cat > /etc/systemd/system/${SERVICE_NAME}-health.service <<EOF
[Unit]
Description=Healthcheck for VPS Status API (restart all services if API is down)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${SERVICE_NAME}-healthcheck.sh
EOF

cat > /etc/systemd/system/${SERVICE_NAME}-health.timer <<EOF
[Unit]
Description=Run VPS Status API healthcheck every 1 minute

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Unit=${SERVICE_NAME}-health.service

[Install]
WantedBy=timers.target
EOF

echo "[4/4] Enabling services & timer..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}
systemctl enable ${SERVICE_NAME}-health.timer
systemctl restart ${SERVICE_NAME}-health.timer

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo "API:      http://${SERVER_IP}:5000/status"
echo "Service:  systemctl status ${SERVICE_NAME}"
echo "Health:   systemctl status ${SERVICE_NAME}-health.timer"
echo "=============================================="
