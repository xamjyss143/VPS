#!/bin/bash
# Bulk Change VPS Root Passwords with Counter and Retry Logic
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
SUCCESS_FILE="${INPUT_FILE%.txt}-success.txt"
ERROR_FILE="${INPUT_FILE%.txt}-error.txt"

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize counter
COUNT=1

# Empty success and error files
> "$SUCCESS_FILE"
> "$ERROR_FILE"

# Loop through each line in the input file
while IFS= read -r line || [[ -n "$line" ]]; do
  # Parse IP, Port, Username, and Old Password
  IP_PORT=$(echo "$line" | cut -d'@' -f1)
  USER_PASS=$(echo "$line" | cut -d'@' -f2)
  IP=$(echo "$IP_PORT" | cut -d':' -f1)
  PORT=$(echo "$IP_PORT" | cut -d':' -f2)
  USER=$(echo "$USER_PASS" | cut -d':' -f1)
  OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)

  # Access root if user is not root and enable root login
  if [[ "$USER" != "root" ]]; then
    /usr/bin/expect <<EOF &> /dev/null
      spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
      expect "*password:"
      send "$OLD_PASS\r"
      expect eof
EOF
    USER="root"
  fi

  # Change port to 22 if not 22
  if [[ "$PORT" != "22" ]]; then
    /usr/bin/expect <<EOF &> /dev/null
      spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP "sudo sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
      expect "*password:"
      send "$OLD_PASS\r"
      expect eof
EOF
    PORT="22"
  fi

  # Retry logic (max 3 attempts)
  ATTEMPTS=0
  SUCCESS=false
  while [[ $ATTEMPTS -lt 3 ]]; do
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
      SUCCESS=true
      break
    fi
    ((ATTEMPTS++))
    sleep 2 # Wait before retrying
  done

  if [[ "$SUCCESS" == true ]]; then
    echo -e "${GREEN}$COUNT => SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: 22]${NC}"
    echo "$COUNT => SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: 22]" >> "$SUCCESS_FILE"
  else
    echo -e "${RED}$COUNT => ERROR: [REASON: Password change failed for $IP after 3 attempts]${NC}"
    echo "$COUNT => ERROR: [REASON: Password change failed for $IP after 3 attempts]" >> "$ERROR_FILE"
  fi

  # Increment counter
  ((COUNT++))

done < "$INPUT_FILE"
