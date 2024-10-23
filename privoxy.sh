#!/bin/bash

# Update package list and install Privoxy
sudo apt update
sudo apt install privoxy -y

# Install Apache Utils for authentication
sudo apt-get install apache2-utils -y
echo "xproxy" | sudo htpasswd -i -c /etc/privoxy/passwd xproxy

# Create and configure the Privoxy configuration file
sudo truncate -s 0 /etc/privoxy/config

sudo tee -a /etc/privoxy/config <<EOF
# Set the listening port
listen-address  0.0.0.0:8118

# Enable basic authentication
enable-remote-http-access  0.0.0.0/0
filter-incoming-requests  1

# Authentication
forward-socks5 / localhost:1080 .
use-header  Proxy-Authorization: Basic $(echo -n "xproxy:xproxy" | base64)

# Log settings
logfile /var/log/privoxy/logfile
EOF

# Restart and enable Privoxy service
sudo systemctl restart privoxy
sudo systemctl enable privoxy

# Check the configuration
sudo privoxy --check-config
