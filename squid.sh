apt install squid -y

sudo apt-get install apache2-utils -y 
echo "xproxy" | sudo htpasswd -i -c /etc/squid/passwd xproxy

cd /etc/squid/
truncate -s 0 squid.conf

sudo tee -a /etc/squid/squid.conf <<EOF
# Define ACLs
acl all src 0.0.0.0/0
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 1025-65535
acl CONNECT method CONNECT
acl SSL_ports port 443

# Define authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Squid Proxy Server
acl auth_users proxy_auth REQUIRED

# Allow access to all necessary headers
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access Cookie allow all
request_header_access Set-Cookie allow all
request_header_access Proxy-Authorization allow all
request_header_access X-Requested-With allow all

# Allow access to safe ports and methods
http_access allow auth_users
http_access allow Safe_ports
http_access allow CONNECT SSL_ports

# Deny access to everything else
http_access deny all

# Port configuration
http_port 8080

# DNS Nameservers
dns_nameservers 1.1.1.1 1.0.0.1

# Other settings
visible_hostname localhost
coredump_dir /var/spool/squid

# Refresh patterns
refresh_pattern ^ftp: 1440 20% 10080
refresh_pattern ^gopher: 1440 0% 1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
refresh_pattern . 0 20% 4320
EOF

systemctl restart squid
sudo systemctl enable squid
sudo squid -k parse


systemctl restart squid
