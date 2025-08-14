#!/usr/bin/env bash
set -euo pipefail
CONF="${HOME:-/home/phoenix}/.phoenix/phoenix.conf"
TS="$(date -u +%Y%m%d%H%M%S)"
BACKUP="${CONF}.bak.${TS}"

[ -f "$CONF" ] || { echo "ERROR: No existe $CONF"; exit 1; }

cp "$CONF" "$BACKUP"

gen() {
  # 36 bytes -> 48 chars base64 aprox; filtra no alfanum
  openssl rand -base64 48 | tr -cd 'A-Za-z0-9' | cut -c1-48
}

NEW_FULL="$(gen)"
NEW_LIMITED="$(gen)"

grep -q '^http-password=' "$CONF" \
  && sed -i "s/^http-password=.*/http-password=${NEW_FULL}/" "$CONF" \
  || echo "http-password=${NEW_FULL}" >> "$CONF"

grep -q '^http-password-limited-access=' "$CONF" \
  && sed -i "s/^http-password-limited-access=.*/http-password-limited-access=${NEW_LIMITED}/" "$CONF" \
  || echo "http-password-limited-access=${NEW_LIMITED}" >> "$CONF"

echo "Passwords rotados."
echo "Backup: $BACKUP"
echo "http-password=${NEW_FULL}"
echo "http-password-limited-access=${NEW_LIMITED}"
echo "Reinicia: docker restart phoenixd"