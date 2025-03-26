#!/bin/bash
# Configure SSH Daemon to Permit access root remotely via OpenSSH server
# Author: Bonveio <github.com/Bonveio/BonvScripts>

# Check if machine has a sudo package
if [[ ! "$(command -v sudo)" ]]; then
 exit 1
fi

# Set root password to xAm12345
newsshpassh="xAm12345"

# Check if machine throws bad config error
if [[ "$(sudo sshd -T | grep -c "Bad configuration")" -eq 1 ]]; then
 sudo service ssh restart &> /dev/null
 sudo service sshd restart &> /dev/null
 sudo cat <<'eof' > /etc/ssh/sshd_config
Port 22
PermitRootLogin yes
PasswordAuthentication yes
eof
fi

# Checking ssh daemon if PermitRootLogin is not allowed yet
if [[ "$(sudo sshd -T | grep -i "permitrootlogin" | awk '{print $2}')" != "yes" ]]; then
 sudo sed -i '/PermitRootLogin.*/d' /etc/ssh/sshd_config &> /dev/null
 echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

# Checking if PasswordAuthentication is not allowed yet
if [[ "$(sudo sshd -T | grep -i "passwordauthentication" | awk '{print $2}')" != "yes" ]]; then
 sudo sed -i '/PasswordAuthentication.*/d' /etc/ssh/sshd_config &> /dev/null
 echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# Changing root Password
if echo -e "$newsshpassh\n$newsshpassh\n" | sudo passwd root &> /dev/null; then
  echo "Password Change Successfully"
  echo "User: root"
  echo "Password: $newsshpassh"
  echo "Port: 22"
else
  echo "Password Change Failed"
fi

# Restarting OpenSSH Service
if [[ ! "$(command -v systemctl)" ]]; then
 sudo service ssh restart &> /dev/null
 sudo service sshd restart &> /dev/null
else
 sudo systemctl restart ssh &> /dev/null
 sudo systemctl restart sshd &> /dev/null
fi

exit 0
