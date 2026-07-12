#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ROOT="/home/xartyzx/projects/FFXI-Runtime"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"

SERVICES=(
  "mochirii-xi-map.service"
  "mochirii-xi-world.service"
  "mochirii-xi-search.service"
  "mochirii-xi-connect.service"
)

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

for service in "${SERVICES[@]}"; do
  if systemctl list-unit-files "$service" >/dev/null 2>&1; then
    echo "Stopping $service..."
    systemctl stop "$service" >/dev/null 2>&1 || true
    systemctl reset-failed "$service" >/dev/null 2>&1 || true
  fi
done

rm -f "$STATE_FILE"

if [[ "${1:-}" == "--stop-db" ]]; then
  echo "Stopping MariaDB..."
  systemctl stop mariadb.service >/dev/null 2>&1 || true
else
  echo "MariaDB left running for development access."
fi

echo "Mochirii XI server stopped."
ss -ltnp | grep -E ':(3306|54001|54002|54003|55030|55031)\b' || true
