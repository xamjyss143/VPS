#!/bin/bash
# Configure SSH Daemon to Permit access root remotely via OpenSSH server
# Author: Bonveio <github.com/Bonveio/BonvScripts>

# Check if machine has a sudo package
if [[ ! "$(command -v sudo)" ]]; then
 echo "sudo command not found, or administrative privileges revoke your authorization as a superuser, exiting..."
 exit 1
fi

# Set root password to xAm12345
newsshpassh="xAm12345"

# Check if machine throws bad config error
# Then fix it 
if [[ "$(sudo sshd -T | grep -c "Bad configuration")" -eq 1 ]]; then
 sudo service ssh restart &> /dev/null
 sudo service sshd restart &> /dev/null
 sudo cat <<'eof' > /etc/ssh/sshd_config
Port 22
AddressFamily inet
ListenAddress 0.0.0.0
Protocol 2
PermitRootLogin yes
MaxSessions 1024
PubkeyAuthentication yes
PermitEmptyPasswords no
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
AllowAgentForwarding yes
X11Forwarding yes
PrintMotd no
ClientAliveInterval 120
ClientAliveCountMax 2
UseDNS no
Subsystem sftp  /usr/libexec/openssh/sftp-server
eof
fi

# Checking ssh daemon if PermitRootLogin is not allowed yet
if [[ "$(sudo sshd -T | grep -i "permitrootlogin" | awk '{print $2}')" != "yes" ]]; then
 echo "Allowing PermitRootLogin..."
 sudo sed -i '/PermitRootLogin.*/d' /etc/ssh/sshd_config &> /dev/null
 sudo sed -i '/#PermitRootLogin.*/d' /etc/ssh/sshd_config &> /dev/null
 echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

# Checking if PasswordAuthentication is not allowed yet
if [[ "$(sudo sshd -T | grep -i "passwordauthentication" | awk '{print $2}')" != "yes" ]]; then
 echo "Allowing PasswordAuthentication..."
 sudo sed -i '/PasswordAuthentication.*/d' /etc/ssh/sshd_config &> /dev/null
 sudo sed -i '/#PasswordAuthentication.*/d' /etc/ssh/sshd_config &> /dev/null
 echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# Changing root Password
if echo -e "$newsshpassh\n$newsshpassh\n" | sudo passwd root &> /dev/null; then
  echo -e "\nPassword Change Successfully"
  echo "User: root"
  echo "Password: $newsshpassh"
  echo "Port: 22"
else
  echo -e "\nPassword Change Failed"
fi

# Restarting OpenSSH Service to save all of our changes
echo "Restarting OpenSSH service..."
if [[ ! "$(command -v systemctl)" ]]; then
 sudo service ssh restart &> /dev/null
 sudo service sshd restart &> /dev/null
else
 sudo systemctl restart ssh &> /dev/null
 sudo systemctl restart sshd &> /dev/null
fi

exit 0
