#!/bin/bash

# Update package list and install HAProxy
sudo apt update
sudo apt install -y haproxy apache2-utils

# Enable HAProxy to start on boot
sudo systemctl enable haproxy

# Create a password file for basic authentication
echo "xproxy:$(openssl passwd -crypt xproxy)" | sudo tee /etc/haproxy/htpasswd

# Configure HAProxy
cat <<EOL | sudo tee /etc/haproxy/haproxy.cfg
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

frontend http_front
    bind *:3134
    acl AuthRequired http_auth(auth_users)
    http-request auth basic auth_users
    default_backend http_back

backend http_back
    server server1 127.0.0.1:8080 maxconn 200
    server server2 127.0.0.1:8081 maxconn 200

# Define the auth group
userlist auth_users
    user xproxy password xproxy
EOL

# Restart HAProxy to apply the changes
sudo systemctl restart haproxy

# Check status
sudo systemctl status haproxy
