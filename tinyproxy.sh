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

# Create the necessary directories
PidFile "/run/tinyproxy/tinyproxy.pid"
EOF

# Create the necessary directories
sudo mkdir -p /run/tinyproxy
sudo mkdir -p /var/log/tinyproxy
sudo chown tinyproxy:tinyproxy /run/tinyproxy
sudo chown tinyproxy:tinyproxy /var/log/tinyproxy

# Restart and enable tinyproxy service
sudo systemctl restart tinyproxy
sudo systemctl enable tinyproxy

# Check the configuration
sudo tinyproxy -c /etc/tinyproxy/tinyproxy.conf -d
