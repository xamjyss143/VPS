#!/bin/bash

# Update the package list
sudo apt update

# Install required packages
sudo apt install -y build-essential libssl-dev wget

# Download and install 3proxy
wget https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz
tar -xvf 0.9.4.tar.gz
cd 3proxy-0.9.4
make -f Makefile.Linux
sudo make install

# Create configuration directory
sudo mkdir /etc/3proxy

# Create the configuration file
cat <<EOL | sudo tee /etc/3proxy/3proxy.cfg
# 3proxy configuration file

# Set the log file
log /var/log/3proxy.log D

# Set DNS servers
nserver 8.8.8.8
nserver 8.8.4.4

# Allow connections from any IP
allow *

# Set authentication
auth strong
users xproxy:CL:xproxy

# Configure proxy
proxy -p8888
EOL

# Create a log directory
sudo mkdir /var/log/3proxy
sudo touch /var/log/3proxy.log

# Set up systemd service
cat <<EOL | sudo tee /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the 3proxy service
sudo systemctl enable 3proxy
sudo systemctl start 3proxy

# Check the status
sudo systemctl status 3proxy
