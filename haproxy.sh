#!/bin/bash

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   exit 1
fi

echo "✅ Installing HAProxy..."
apt update
apt install -y haproxy

echo "🔧 Backing up existing HAProxy config..."
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak.$(date +%s)

echo "✍️ Writing new HAProxy config..."
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    maxconn 2000
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend proxy_front
    bind *:8080
    default_backend proxy_pool

backend proxy_pool
    balance roundrobin

    server proxy1 223.29.253.137:80 check
    server proxy2 191.101.109.52:80 check
    server proxy3 196.244.48.44:80 check
    server proxy4 191.101.109.97:80 check
    server proxy5 191.101.109.80:80 check
    server proxy6 198.46.222.201:80 check
    server proxy7 192.3.236.222:80 check
    server proxy8 196.244.48.100:80 check
    server proxy9 196.244.48.252:80 check
    server proxy10 223.29.253.119:80 check
EOF

echo "🔄 Restarting HAProxy..."
systemctl restart haproxy

echo "✅ HAProxy has been installed and configured."
