#!/bin/bash
#updated
# Update package list and install Tinyproxy
sudo apt update
sudo apt install tinyproxy apache2-utils -y

# Create password file for basic authentication with username and password both set to "xproxy"
echo "xproxy:xproxy" | sudo tee /etc/tinyproxy/passwd

# Clear the Tinyproxy configuration file
sudo truncate -s 0 /etc/tinyproxy/tinyproxy.conf

# Configure Tinyproxy
sudo tee /etc/tinyproxy/tinyproxy.conf <<EOF
# Set the listening port
Port 8888

# Allow access from all IPs (change this as needed)
Allow 0.0.0.0/0

# Enable basic authentication
AuthLevel Basic
AuthUser xproxy
AuthPass xproxy  # Password set to "xproxy"

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
