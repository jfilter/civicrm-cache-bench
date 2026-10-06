#!/usr/bin/env bash
# Runs inside the app container: logs in a Standalone user, prints the session cookie as "name=value".
set -euo pipefail
user=$1 pass=$2 jar=$(mktemp)
curl -fsS -c "$jar" -b "$jar" -o /dev/null http://app/civicrm/login
curl -fsS -c "$jar" -b "$jar" -H 'X-Requested-With: XMLHttpRequest' \
  --data-urlencode "params={\"identifier\":\"$user\",\"password\":\"$pass\"}" \
  http://app/civicrm/ajax/api4/User/login >/dev/null
awk '$6 ~ /^SESSCIVISO/ {print $6 "=" $7}' "$jar"
rm -f "$jar"
