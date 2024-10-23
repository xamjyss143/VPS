#!/bin/bash

# Update and install dependencies
sudo apt update && sudo apt install -y build-essential git

# Clone the 3proxy repository
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy

# Build 3proxy
make -f Makefile.Linux

# Install the binary
sudo cp 3proxy /usr/local/bin/

# Create configuration directory
sudo mkdir /etc/3proxy

# Create a basic configuration file
sudo bash -c 'cat <<EOF > /etc/3proxy/3proxy.cfg
# Basic 3proxy configuration
nserver 8.8.8.8
nserver 8.8.4.4
log /var/log/3proxy.log D
logfile /var/log/3proxy.log
# Authentication
auth strong
users xproxy:xproxy
# Allow access
allow *
# Define the proxy
proxy -p3128
EOF'

# Create a PID file
sudo touch /run/3proxy.pid
sudo chown $(whoami) /run/3proxy.pid

# Create a systemd service
sudo bash -c 'cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF'

# Reload systemd and start 3proxy
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
sudo systemctl start 3proxy

# Check status
systemctl status 3proxy
