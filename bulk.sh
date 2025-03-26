#!/bin/bash
# Bulk Change VPS Root Passwords
# Author: ChatGPT

# Define the new root password
NEW_PASSWORD="xAm12345"

# Check if input file is provided
if [[ -z "$1" ]]; then
  echo "Usage: $0 <input_file>"
  echo "Input file format: ip:port@username:oldpassword"
  exit 1
fi

INPUT_FILE="$1"

# Loop through each line in the input file
while IFS= read -r line || [[ -n "$line" ]]; do
  # Parse IP, Port, Username, and Old Password
  IP_PORT=$(echo "$line" | cut -d'@' -f1)
  USER_PASS=$(echo "$line" | cut -d'@' -f2)
  IP=$(echo "$IP_PORT" | cut -d':' -f1)
  PORT=$(echo "$IP_PORT" | cut -d':' -f2)
  USER=$(echo "$USER_PASS" | cut -d':' -f1)
  OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)

  # Change root password using SSH and expect
  /usr/bin/expect <<EOF &> /dev/null
    spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP "echo -e \"$NEW_PASSWORD\\n$NEW_PASSWORD\\n\" | passwd root"
    expect {
        "password:" { send "$OLD_PASS\r" }
        "New password:" { send "$NEW_PASSWORD\r" }
        "Retype new password:" { send "$NEW_PASSWORD\r" }
    }
    expect eof
EOF

  if [[ $? -eq 0 ]]; then
    echo -e "Success!\n\nIP: $IP\nUser: root\nPassword: $NEW_PASSWORD\nPort: $PORT\n"
  else
    echo "Error changing password for $IP"
  fi
done < "$INPUT_FILE"
