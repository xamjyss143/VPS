#!/bin/bash

read -p "Enter Cloudflare DNS Token:" TOKEN
read -p "Enter Cloudflare ZONE ID:" ZONE_ID

# EMAIL=jorjanseenearlbade@gmail.com
# KEY=48f416ac6a55e0ff8525812f3480edbb1ca8f
# Replace with 
#     -H "X-Auth-Email: ${EMAIL}" \
#     -H "X-Auth-Key: ${KEY}" \
# for old API keys
 

curl -s -X GET https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=1000 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" | jq .result[].id |  tr -d '"' | (
  while read id; do
    curl -s -X DELETE https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id} \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json"
  done
  )
