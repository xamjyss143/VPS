#!/bin/bash

# Update and install necessary packages
sudo apt update
sudo apt install -y build-essential wget

# Download and install 3proxy
wget https://3proxy.org/3proxy-0.9.1.tgz
tar -xzf 3proxy-0.9.1.tgz
cd 3proxy-0.9.1
make
sudo make install

# Create configuration directory
sudo mkdir -p /etc/3proxy

# Create the configuration file
cat <<EOL | sudo tee /etc/3proxy/3proxy.cfg
nserver 8.8.8.8
nserver 8.8.4.4
users xproxy:CL:xproxy
auth strong
allow *
proxy -p3128
EOL

# Create systemd service file
cat <<EOL | sudo tee /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy

[Service]
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
sudo systemctl start 3proxy

# Check the status of 3proxy
sudo systemctl status 3proxy
