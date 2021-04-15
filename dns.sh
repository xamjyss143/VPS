#!/bin/bash

TOKEN="JbRNImY7MXitMT71COXQYcbxNRDHYdVpUwhiQxAh"
ZONE_ID=c8e0815cc99e3c6a91b317ba958a3dbf

# EMAIL=jorjanseenearlbade@gmail.com
# KEY=48f416ac6a55e0ff8525812f3480edbb1ca8f
# Replace with 
#     -H "X-Auth-Email: ${EMAIL}" \
#     -H "X-Auth-Key: ${KEY}" \
# for old API keys
 

curl -s -X GET https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=500 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" | jq .result[].id |  tr -d '"' | (
  while read id; do
    curl -s -X DELETE https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${id} \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json"
  done
  )
