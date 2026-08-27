#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ROOT="/home/xartyzx/projects/FFXI-Runtime"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/status-mochirii-wsl.sh"

SERVICES=(
  "mochirii-xi-map.service"
  "mochirii-xi-world.service"
  "mochirii-xi-search.service"
  "mochirii-xi-connect.service"
)

usage() {
  echo "Usage: stop-mochirii-wsl.sh [--stop-db]" >&2
}

STOP_DB=false
if (( $# > 1 )); then
  usage
  exit 2
elif (( $# == 1 )); then
  if [[ "$1" != "--stop-db" ]]; then
    usage
    exit 2
  fi
  STOP_DB=true
fi

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

for service in "${SERVICES[@]}"; do
  echo "Stopping $service..."
  systemctl disable "$service" >/dev/null
  systemctl stop "$service" >/dev/null
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
done

systemctl disable mariadb.service >/dev/null

rm -f "$STATE_FILE"

if [[ "$STOP_DB" == "true" ]]; then
  echo "Stopping MariaDB..."
  systemctl stop mariadb.service >/dev/null
  systemctl reset-failed mariadb.service >/dev/null 2>&1 || true
  "$STATUS_SCRIPT" --expect-stopped-disabled
else
  echo "MariaDB left in its existing manual-start state for development access."
  if systemctl is-active --quiet mariadb.service; then
    "$STATUS_SCRIPT" --expect-xi-stopped-db-running-manual
  else
    "$STATUS_SCRIPT" --expect-stopped-disabled
  fi
fi

echo "Mochirii XI server stopped."
