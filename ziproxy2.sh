#!/bin/bash

# Update system package list
sudo apt update && sudo apt upgrade -y

# Install Ziproxy
sudo apt install -y ziproxy

# Check if the configuration file exists, if not create it
CONFIG_FILE="/etc/ziproxy.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    sudo cp /usr/share/doc/ziproxy/ziproxy.conf.gz /etc/ziproxy.conf.gz
    sudo gunzip /etc/ziproxy.conf.gz
fi

# Set port to 6969 in the configuration file
sudo sed -i 's/^port .*/port 6969/' "$CONFIG_FILE"

# Start and enable Ziproxy service
sudo systemctl start ziproxy
sudo systemctl enable ziproxy

# Check if UFW is installed; install it if not
if ! command -v ufw &> /dev/null; then
    sudo apt install -y ufw
    sudo ufw allow 6969/tcp
else
    sudo ufw allow 6969/tcp
fi

# Print the status of Ziproxy
sudo systemctl status ziproxy

# Print success message
echo "Ziproxy installation and configuration completed. It is running on port 6969."
