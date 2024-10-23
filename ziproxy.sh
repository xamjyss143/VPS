#!/bin/bash

# Update package list and install ziproxy
sudo apt update
sudo apt install ziproxy -y

# Install Apache Utils for authentication
sudo apt-get install apache2-utils -y
echo "xproxy" | sudo htpasswd -i -c /etc/ziproxy/passwd xproxy

# Create and configure the ziproxy configuration file
sudo truncate -s 0 /etc/ziproxy/ziproxy.conf

sudo tee -a /etc/ziproxy/ziproxy.conf <<EOF
# Set the listening port
listen_address = 0.0.0.0:7071

# Set the caching and compression options
cache_dir = /var/cache/ziproxy
compress = true

# Enable authentication
auth_type = basic
auth_realm = "Ziproxy Proxy Server"
auth_user_file = /etc/ziproxy/passwd

# Define allowed hosts
allowed_hosts = *

# Log settings
log_file = /var/log/ziproxy.log
log_level = info
EOF

# Create the cache directory
sudo mkdir -p /var/cache/ziproxy
sudo chown www-data:www-data /var/cache/ziproxy

# Restart and enable ziproxy service
sudo systemctl restart ziproxy
sudo systemctl enable ziproxy

# Check the configuration
sudo ziproxy -c /etc/ziproxy/ziproxy.conf -k parse
