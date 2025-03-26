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

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Loop through each line in the input file
while IFS= read -r line || [[ -n "$line" ]]; do
  # Parse IP, Port, Username, and Old Password
  IP_PORT=$(echo "$line" | cut -d'@' -f1)
  USER_PASS=$(echo "$line" | cut -d'@' -f2)
  IP=$(echo "$IP_PORT" | cut -d':' -f1)
  PORT=$(echo "$IP_PORT" | cut -d':' -f2)
  USER=$(echo "$USER_PASS" | cut -d':' -f1)
  OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)

  # Always use port 22
  PORT="22"

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
    echo -e "${GREEN}SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: $PORT]${NC}"
  else
    echo -e "${RED}ERROR: [REASON: Password change failed for $IP]${NC}"
  fi

done < "$INPUT_FILE"
