#!/bin/bash

# Update package list and install tinyproxy
sudo apt update
sudo apt install tinyproxy apache2-utils -y

# Set the password for the user 'xproxy'
echo "xproxy:xproxy" | sudo tee /etc/tinyproxy/passwd

# Clear existing Tinyproxy configuration
sudo truncate -s 0 /etc/tinyproxy/tinyproxy.conf

# Create a new Tinyproxy configuration
sudo tee /etc/tinyproxy/tinyproxy.conf <<EOF
# Set the listening port
Port 8888

# Allow access from all IPs (change this as needed)
Allow 0.0.0.0/0

# Enable basic authentication
BasicAuth xproxy xproxy

# Log settings
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info

# PID file setting
PidFile "/run/tinyproxy/tinyproxy.pid"
EOF

# Create the necessary directories and set permissions
sudo mkdir -p /run/tinyproxy
sudo mkdir -p /var/log/tinyproxy
sudo chown -R tinyproxy:tinyproxy /etc/tinyproxy
sudo chown -R tinyproxy:tinyproxy /run/tinyproxy
sudo chown -R tinyproxy:tinyproxy /var/log/tinyproxy

# Restart and enable tinyproxy service
sudo systemctl restart tinyproxy
sudo systemctl enable tinyproxy

# Check the status
sudo systemctl status tinyproxy
