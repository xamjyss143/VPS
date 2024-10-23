#!/bin/bash

# Update package list and install tinyproxy
sudo apt update
sudo apt install tinyproxy apache2-utils -y

# Create password file for authentication
echo "xproxy" | sudo htpasswd -i -c /etc/tinyproxy/passwd xproxy

# Clean and configure the tinyproxy configuration file
sudo truncate -s 0 /etc/tinyproxy/tinyproxy.conf

sudo tee -a /etc/tinyproxy/tinyproxy.conf <<EOF
# Set the listening port
Port 8888

# Allow access from all IPs (change this as needed)
Allow 0.0.0.0/0

# Enable basic authentication
BasicAuth xproxy $(cat /etc/tinyproxy/passwd | grep xproxy | cut -d ':' -f 2)

# PID file setting
PidFile "/run/tinyproxy/tinyproxy.pid"

# Log settings
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info

# MaxClients setting
MaxClients 100
EOF

# Create necessary directories and set permissions
sudo mkdir -p /run/tinyproxy
sudo chown tinyproxy:tinyproxy /run/tinyproxy

# Restart and enable tinyproxy service
sudo systemctl restart tinyproxy
sudo systemctl enable tinyproxy

# Check the configuration
sudo tinyproxy -c /etc/tinyproxy/tinyproxy.conf -d
