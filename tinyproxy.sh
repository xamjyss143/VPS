#!/bin/bash

# Update package list and install Tinyproxy
sudo apt update
sudo apt install tinyproxy apache2-utils -y

# Create password file for basic authentication
echo "xproxy" | sudo htpasswd -i -c /etc/tinyproxy/passwd xproxy

# Configure Tinyproxy
sudo tee /etc/tinyproxy/tinyproxy.conf <<EOF
# Set the listening port
Port 8888

# Allow access from all IPs (change this as needed)
Allow 0.0.0.0/0

# Enable basic authentication
BasicAuth xproxy $(cat /etc/tinyproxy/passwd | grep xproxy | cut -d ':' -f 2)

# Log settings
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
EOF

# Create the log directory
sudo mkdir -p /var/log/tinyproxy
sudo chown tinyproxy:tinyproxy /var/log/tinyproxy

# Restart and enable Tinyproxy service
sudo systemctl restart tinyproxy
sudo systemctl enable tinyproxy

# Check the Tinyproxy status
sudo systemctl status tinyproxy
