#!/bin/sh
set -e

API_KEYS_FILE="${API_KEYS_FILE:-/run/secrets/api_keys}"
API_KEYS_MAP_FILE="${API_KEYS_MAP_FILE:-/etc/nginx/api_keys.map}"

[ -z "$UPSTREAM" ] && echo "Error: UPSTREAM is required" >&2 && exit 1

if [ ! -f "$API_KEYS_FILE" ]; then
  echo "Error: API keys file not found at $API_KEYS_FILE" >&2
  exit 1
fi

echo "Generating API key map from $API_KEYS_FILE..."

> "$API_KEYS_MAP_FILE"
chmod 600 "$API_KEYS_MAP_FILE"
COUNT=0

while IFS= read -r key || [ -n "$key" ]; do
  [ -z "$key" ] && continue
  echo "$key" | grep -q "^#" && continue
  key=$(printf '%s' "$key" | tr -d '\r')
  [ -z "$key" ] && continue
  escaped_key=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/[][^.$*+?{}|()]/\\&/g')
  printf '%s\n' "~^[Bb][Ee][Aa][Rr][Ee][Rr]\\s+${escaped_key}\$    1;" >> "$API_KEYS_MAP_FILE"
  COUNT=$((COUNT + 1))
done < "$API_KEYS_FILE"

[ "$COUNT" -eq 0 ] && echo "Error: No API keys loaded from $API_KEYS_FILE" >&2 && exit 1

echo "Loaded $COUNT API key(s)"