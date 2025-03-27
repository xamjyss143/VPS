#!/bin/bash
# Bulk Change VPS Root Passwords

# Define the new root password
NEW_PASSWORD="xAm12345"

# Check if input file is provided
if [[ -z "$1" ]]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"
SUCCESS_FILE="${INPUT_FILE%.txt}-success.txt"
ERROR_FILE="${INPUT_FILE%.txt}-error.txt"

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

  # Step 1: Enable root login and force password authentication
  if [[ "$USER" != "root" ]]; then
    /usr/bin/expect <<EOF &>/dev/null
    spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP
    expect {
        "*password:" { send "$OLD_PASS\r"; exp_continue }
        "*\$*" {
            send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && "
            send "echo '$OLD_PASS' | sudo -S sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && "
            send "echo '$OLD_PASS' | sudo -S systemctl restart sshd\r"
        }
    }
    expect eof
EOF

    # Step 1.1: Unlock root and change password
    /usr/bin/expect <<EOF &>/dev/null
    spawn ssh -o StrictHostKeyChecking=no -p $PORT $USER@$IP
    expect {
        "*password:" { send "$OLD_PASS\r"; exp_continue }
        "*\$*" {
            send "echo '$OLD_PASS' | sudo -S passwd -u root\r"
            send "echo '$OLD_PASS' | sudo -S chmod 644 /etc/passwd /etc/shadow\r"
            send "echo '$OLD_PASS' | sudo -S su -c \"echo -e '$NEW_PASSWORD\n$NEW_PASSWORD' | passwd root\"\r"
        }
    }
    expect eof
EOF

    USER="root"
  fi

  # Step 2: Change SSH port to 22 if not already 22
  if [[ "$PORT" != "22" ]]; then
    /usr/bin/expect <<EOF &>/dev/null
    spawn ssh -o StrictHostKeyChecking=no -p $PORT root@$IP
    expect {
        "*password:" { send "$NEW_PASSWORD\r"; exp_continue }
        "*\$*" { send "sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config && systemctl restart sshd\r" }
    }
    expect eof
EOF
    PORT="22"
  fi

  # Step 3: Verify root login with new password
  /usr/bin/expect <<EOF &>/dev/null
  spawn ssh -o StrictHostKeyChecking=no -p $PORT root@$IP "echo 'Root login confirmed'"
  expect {
      "*password:" { send "$NEW_PASSWORD\r" }
      "*Root login confirmed*" { exit 0 }
  }
  expect eof
EOF

  if [[ $? -eq 0 ]]; then
    echo "$COUNT => SUCCESS: [IP: $IP], [USER: root], [PASSWORD: $NEW_PASSWORD], [PORT: 22]" >> "$SUCCESS_FILE"
  else
    echo "$COUNT => ERROR: [REASON: Root login failed for $IP]" >> "$ERROR_FILE"
  fi

  ((COUNT++))

done < "$INPUT_FILE"
