#!/bin/bash
# Bulk Change VPS Root Passwords - Silent Mode (Only Success/Error Output)

NEW_PASSWORD="xAm12345"

if [[ -z "$1" ]]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"
SUCCESS_FILE="${INPUT_FILE%.txt}-success.txt"
ERROR_FILE="${INPUT_FILE%.txt}-error.txt"

COUNT=1
> "$SUCCESS_FILE"
> "$ERROR_FILE"

while IFS= read -r line || [[ -n "$line" ]]; do
  IP_PORT=$(echo "$line" | cut -d'@' -f1)
  USER_PASS=$(echo "$line" | cut -d'@' -f2)
  IP=$(echo "$IP_PORT" | cut -d':' -f1)
  PORT=$(echo "$IP_PORT" | cut -d':' -f2)
  USER=$(echo "$USER_PASS" | cut -d':' -f1)
  OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)

  # Enable root login & change password
  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP
  expect {
      "*password:" { send "$OLD_PASS\r"; exp_continue }
      "*\$ " {
          send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\r"
          send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\r"
          send "echo '$OLD_PASS' | sudo -S systemctl restart sshd\r"
          send "echo '$OLD_PASS' | sudo -S passwd -u root\r"
          send "echo '$OLD_PASS' | sudo -S su -c \"echo -e '$NEW_PASSWORD\n$NEW_PASSWORD' | passwd root\"\r"
          send "exit\r"
      }
  }
  expect eof
EOF

  USER="root"

  # Verify root login
  /usr/bin/expect <<EOF > /dev/null 2>&1
  spawn ssh -o StrictHostKeyChecking=no -p $PORT root@$IP "echo 'Root login confirmed'"
  expect {
      "*password:" { send "$NEW_PASSWORD\r"; exp_continue }
      "*Root login confirmed*" { exit 0 }
  }
  expect eof
EOF

  if [[ $? -eq 0 ]]; then
    echo "SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: $PORT]"
    echo "$COUNT => SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: $PORT]" >> "$SUCCESS_FILE"
  else
    echo "ERROR: [REASON: Root login failed for $IP]"
    echo "$COUNT => ERROR: [REASON: Root login failed for $IP]" >> "$ERROR_FILE"
  fi

  ((COUNT++))

done < "$INPUT_FILE"
