#!/bin/bash

# Update system package list and upgrade packages
sudo apt update && sudo apt upgrade -y

# Install Ziproxy
sudo apt install -y ziproxy

# Configure Ziproxy to use port 8080
CONFIG_FILE="/etc/ziproxy.conf"

# Backup the original configuration file
sudo cp $CONFIG_FILE $CONFIG_FILE.bak

# Set port to 8080 in the configuration file
sudo sed -i 's/^port .*/port 8080/' $CONFIG_FILE

# Allow connections from all hosts (optional, adjust as needed)
sudo sed -i 's/^allowed_hosts .*/allowed_hosts 0.0.0.0\/0/' $CONFIG_FILE

# Start and enable Ziproxy service
sudo systemctl start ziproxy
sudo systemctl enable ziproxy

# Allow port 8080 through the firewall (if UFW is enabled)
sudo ufw allow 8080/tcp

# Print success message
echo "Ziproxy installation and configuration completed. It is running on port 8080."
