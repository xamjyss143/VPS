#!/bin/bash
# Bulk Change VPS Root Passwords - Clean Output with Colors

NEW_PASSWORD="xAm12345"

if [[ -z "$1" ]]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"
SUCCESS_FILE="${INPUT_FILE%.txt}-success.txt"
ERROR_FILE="${INPUT_FILE%.txt}-error.txt"

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

COUNT=1
> "$SUCCESS_FILE"
> "$ERROR_FILE"

# Function 1: Enable root login and password authentication
enable_root_login() {
  local IP=$1
  local PORT=$2
  local USER=$3
  local OLD_PASS=$4

  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP
  expect {
      "*password:" { send "$OLD_PASS\r"; exp_continue }
      "*$ " {
          send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\r"
          send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\r"
          send "echo '$OLD_PASS' | sudo -S sed -i 's/^Port /c\Port 22' /etc/ssh/sshd_config || echo 'Port 22' >> /etc/ssh/sshd_config\r"
          send "echo '$OLD_PASS' | sudo -S systemctl restart sshd\r"
          send "echo '$OLD_PASS' | sudo -S echo -e '$NEW_PASSWORD\n$NEW_PASSWORD' | sudo passwd root\r"
          send "exit\r"
      }
  }
  expect eof
EOF
}

# Function 2: Change SSH port to 22 if needed
change_ssh_port() {
  local IP=$1
  local PORT=$2

  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT root@$IP
  expect {
      "*password:" { send "$NEW_PASSWORD\r"; exp_continue }
      "*$ " { send "sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config && systemctl restart sshd\r" }
  }
  expect eof
EOF
}

# Function 3: Ensure root password is set to NEW_PASSWORD (only if different)
enable_root_login2() {
  local IP=$1
  local PORT=$2
  local USER=$3
  local OLD_PASS=$4

  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP
  expect {
      "*password:" { send "$OLD_PASS\r"; exp_continue }
      "*# " {
          send "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\r"
          send "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\r"
          send "sed -i '/^Port /c\Port 22' /etc/ssh/sshd_config || echo 'Port 22' >> /etc/ssh/sshd_config\r"
          send "systemctl restart sshd\r"
          send "echo -e '$NEW_PASSWORD\n$NEW_PASSWORD' | passwd root\r"
          send "exit\r"
      }
  }
  expect eof
EOF
}


while IFS= read -r line || [[ -n "$line" ]]; do
  IP_PORT=$(echo "$line" | cut -d'@' -f1)
  USER_PASS=$(echo "$line" | cut -d'@' -f2)
  IP=$(echo "$IP_PORT" | cut -d':' -f1)
  PORT=$(echo "$IP_PORT" | cut -d':' -f2)
  USER=$(echo "$USER_PASS" | cut -d':' -f1)
  OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)
  NEW_PASSWORD="xAm12345"

if [[ "$USER" != "root" ]]; then
    # echo "Non-root user"
    enable_root_login "$IP" "$PORT" "$USER" "$OLD_PASS"
    USER="root"
    PORT="22"
fi
if [[ "$USER" == "root" ]]; then
    # echo "Confirmed root user"
    enable_root_login2 "$IP" "$PORT" "$USER" "$OLD_PASS"
    USER="root"
    PORT="22"
fi
  # Verify root login
  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP "echo 'Root login confirmed'"
  expect {
      "*password:" { send "$NEW_PASSWORD\r"; exp_continue }
      "*Root login confirmed*" { exit 0 }
  }
  expect eof
EOF

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: $PORT]${NC}"
    echo "$COUNT => SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: $PORT]" >> "$SUCCESS_FILE"
  else
    echo -e "${RED}ERROR: [REASON: Root login failed for $IP]${NC}"
    echo "$COUNT => ERROR: [REASON: Root login failed for $IP]" >> "$ERROR_FILE"
  fi

  ((COUNT++))

done < "$INPUT_FILE"

echo "Process completed. Check $SUCCESS_FILE and $ERROR_FILE for details."
