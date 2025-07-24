#!/bin/bash
set -e

WG_INTERFACE="wg0"
WG_PORT=51820
WG_CONF_DIR="/etc/wireguard"
CLIENT_DIR="${WG_CONF_DIR}/clients"
SERVER_CONF="${WG_CONF_DIR}/${WG_INTERFACE}.conf"
CLIENT_ALLOWED_IP="0.0.0.0/0"
SUBNET_FILE="${WG_CONF_DIR}/vpn_subnet.conf"

function install_dependencies() {
    echo "[+] Installing WireGuard and tools..."
    apt update
    apt install -y wireguard qrencode curl iptables iproute2
}

function generate_random_subnet() {
    if [[ -f "$SUBNET_FILE" ]]; then
        VPN_SUBNET=$(cat "$SUBNET_FILE")
        echo "[*] Using existing VPN subnet: $VPN_SUBNET"
    else
        X=$(( RANDOM % 256 ))
        Y=$(( RANDOM % 256 ))
        VPN_SUBNET="10.${X}.${Y}.0/24"
        echo "$VPN_SUBNET" > "$SUBNET_FILE"
        echo "[*] Generated new VPN subnet: $VPN_SUBNET"
    fi
    SERVER_IP=$(echo "$VPN_SUBNET" | cut -d/ -f1 | awk -F '.' '{print $1"."$2"."$3".1"}')
}

function generate_server_keys() {
    mkdir -p "${WG_CONF_DIR}"
    umask 077
    if [[ ! -f "${WG_CONF_DIR}/server_private.key" ]]; then
        wg genkey | tee "${WG_CONF_DIR}/server_private.key" | wg pubkey > "${WG_CONF_DIR}/server_public.key"
        echo "[*] Generated new server keys."
    else
        echo "[*] Server keys already exist."
    fi
}

function setup_server_config() {
    if [[ ! -f "$SERVER_CONF" ]]; then
        SERVER_PRIVATE_KEY=$(cat "${WG_CONF_DIR}/server_private.key")
        cat > "$SERVER_CONF" <<EOF
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = true
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o \$(ip route get 1 | awk '{print \$5; exit}') -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o \$(ip route get 1 | awk '{print \$5; exit}') -j MASQUERADE
EOF
        chmod 600 "$SERVER_CONF"
        echo "[*] Created WireGuard server config."
    else
        echo "[*] Server config already exists."
    fi
}

function enable_ip_forwarding() {
    echo "[*] Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
}

function enable_service() {
    systemctl enable wg-quick@"${WG_INTERFACE}"
    systemctl start wg-quick@"${WG_INTERFACE}"
    echo "[*] WireGuard service started and enabled."
}

function install_add_wireguard_script() {
    mkdir -p "$CLIENT_DIR"
    cat > /usr/local/bin/add_wireguard <<EOF
#!/bin/bash
set -e

WG_INTERFACE="wg0"
WG_CONF_DIR="/etc/wireguard"
CLIENT_DIR="\${WG_CONF_DIR}/clients"
CLIENT_ALLOWED_IP="0.0.0.0/0"
WG_PORT=51820

SUBNET_FILE="\${WG_CONF_DIR}/vpn_subnet.conf"
VPN_SUBNET=\$(cat "\$SUBNET_FILE")
SERVER_IP=\$(echo "\$VPN_SUBNET" | cut -d/ -f1 | awk -F '.' '{print \$1"." \$2"." \$3".1"}')

while getopts ":u:e:" opt; do
  case \$opt in
    u) USERNAME="\$OPTARG" ;;
    e) EXPIRE_DAYS="\$OPTARG" ;;
    \?) echo "Invalid option: -\$OPTARG" >&2; exit 1 ;;
    :) echo "Option -\$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

if [[ -z "\$USERNAME" ]]; then
  echo "Usage: add_wireguard -u <username> [-e <expiration_days>]"
  exit 1
fi

if [[ -z "\$EXPIRE_DAYS" ]]; then
  EXPIRE_DAYS=7
fi

CLIENT_CONF="\${CLIENT_DIR}/\${USERNAME}.conf"
CLIENT_META="\${CLIENT_DIR}/\${USERNAME}.meta"

if [[ -f "\$CLIENT_CONF" ]]; then
  echo "Client \$USERNAME already exists!"
  exit 1
fi

CLIENT_PRIVATE_KEY=\$(wg genkey)
CLIENT_PUBLIC_KEY=\$(echo "\$CLIENT_PRIVATE_KEY" | wg pubkey)

BASE_IP=\$(echo "\$VPN_SUBNET" | cut -d/ -f1 | awk -F '.' '{print \$1"." \$2"." \$3}')
CLIENT_COUNT=\$(ls "\$CLIENT_DIR"/*.conf 2>/dev/null | wc -l)
CLIENT_IP="\${BASE_IP}.\$((2 + CLIENT_COUNT))"

wg set \$WG_INTERFACE peer \$CLIENT_PUBLIC_KEY allowed-ips \$CLIENT_IP/32
echo -e "
[Peer]
PublicKey = \$CLIENT_PUBLIC_KEY
AllowedIPs = \$CLIENT_IP/32" >> "\${WG_CONF_DIR}/\${WG_INTERFACE}.conf"
systemctl restart wg-quick@\${WG_INTERFACE}

EXP_DATE=\$(date -d "+\$EXPIRE_DAYS days" +%Y-%m-%d)
echo "\$EXP_DATE" > "\$CLIENT_META"

cat > "\$CLIENT_CONF" <<EOL
[Interface]
PrivateKey = \$CLIENT_PRIVATE_KEY
Address = \$CLIENT_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = \$(cat "\${WG_CONF_DIR}/server_public.key")
Endpoint = \$(curl -s ifconfig.me):\$WG_PORT
AllowedIPs = \$CLIENT_ALLOWED_IP
PersistentKeepalive = 25
EOL

qrencode -t ansiutf8 < "\$CLIENT_CONF"
echo "[+] Client config created: \$CLIENT_CONF"
echo "    Expires on: \$EXP_DATE"
EOF
    chmod +x /usr/local/bin/add_wireguard
    echo "[*] Installed add_wireguard command."
}

function install_expiration_checker() {
    local cron_file="/etc/cron.daily/wg-expire-clean"
    cat > "$cron_file" <<'EOF'
#!/bin/bash
WG_CONF_DIR="/etc/wireguard"
CLIENT_DIR="${WG_CONF_DIR}/clients"
WG_INTERFACE="wg0"
today=$(date +%Y-%m-%d)

if ! command -v wg >/dev/null 2>&1; then
    exit 0
fi

for meta in ${CLIENT_DIR}/*.meta 2>/dev/null; do
    user=$(basename "$meta" .meta)
    expire_date=$(cat "$meta")
    if [[ "$expire_date" < "$today" ]]; then
        echo "Removing expired client $user"
        pubkey=$(grep PublicKey "${CLIENT_DIR}/$user.conf" | awk '{print $3}')
        wg set $WG_INTERFACE peer $pubkey remove
        sed -i "/$pubkey/,+1d" "${WG_CONF_DIR}/${WG_INTERFACE}.conf"
        rm -f "${CLIENT_DIR}/$user.conf" "${CLIENT_DIR}/$user.meta"
        systemctl restart wg-quick@$WG_INTERFACE
    fi
done
EOF
    chmod +x "$cron_file"
    echo "[*] Installed expiration checker cron job."
}

function main() {
    install_dependencies
    generate_random_subnet
    generate_server_keys
    setup_server_config
    enable_ip_forwarding
    enable_service
    install_add_wireguard_script
    install_expiration_checker

    echo ""
    echo "✅ WireGuard installed and running."
    echo "📥 VPN subnet: $VPN_SUBNET"
    echo "📥 Server VPN IP: $SERVER_IP"
    echo ""
    echo "To add clients run:"
    echo "  add_wireguard -u username -e 7"
    echo "  (expiration days default to 7)"
}

main
