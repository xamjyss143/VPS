#!/bin/bash

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt update && sudo apt install -y jq
fi

# Read user input for Cloudflare credentials
read -p "Enter Cloudflare DNS Token: " TOKEN
read -p "Enter Cloudflare ZONE ID: " ZONE_ID

# Fetch DNS records
RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=1000" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json")

# Process each record
FIRST=1
echo "$RECORDS" | jq -c '.result[] | {id: .id, name: .name}' | while read record; do
    ID=$(echo "$record" | jq -r '.id')
    NAME=$(echo "$record" | jq -r '.name')

    # Delete the DNS record
    curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${ID}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" > /dev/null

    # Print results on the same line
    if [[ $FIRST -eq 1 ]]; then
        printf "%s -> DELETED" "$NAME"
        FIRST=0
    else
        printf ", %s -> DELETED" "$NAME"
    fi
done
printf "\n"  # Add a final newline after all deletions
