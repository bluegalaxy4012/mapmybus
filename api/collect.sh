#!/bin/bash

# pentru colectare date, dupa puse in vehicle_jsons

OUTPUT_FILE="data_vehicles.json"

if [ ! -f "$OUTPUT_FILE" ]; then
  echo "[]" > "$OUTPUT_FILE"
fi

while true; do
  CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  RESPONSE=$(curl --silent --request GET \
    --url https://api.tranzy.ai/v1/opendata/vehicles \
    --header 'Accept: application/json' \
    --header 'X-API-KEY: iZfqSdYCq0ZxEsKEkfCRoyiXEsaC19CQ5QV4WMnF' \
    --header 'X-Agency-Id: 2')

  NEW_ENTRY="{\"date\": \"$CURRENT_DATE\", \"data\": $RESPONSE}"

  TMP_FILE=$(mktemp)
  jq ". + [$NEW_ENTRY]" "$OUTPUT_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTPUT_FILE"

  sleep 20
done
