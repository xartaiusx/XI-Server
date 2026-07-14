#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ROOT="/home/xartyzx/projects/FFXI-Runtime"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"

SERVICES=(
  "mariadb.service"
  "mochirii-xi-connect.service"
  "mochirii-xi-search.service"
  "mochirii-xi-world.service"
  "mochirii-xi-map.service"
)

echo "Mochirii WSL service summary"
echo "============================"

for service in "${SERVICES[@]}"; do
  active="$(systemctl is-active "$service" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
  pid="$(systemctl show "$service" -p MainPID --value 2>/dev/null || true)"
  printf '%-30s active=%-10s enabled=%-10s pid=%s\n' "$service" "$active" "$enabled" "$pid"
done

echo
echo "Listening ports"
echo "---------------"
ss -ltnp | grep -E ':(3306|54001|54002|54003|55030|55031)\b' || echo "No Mochirii ports are listening."

if [[ -f "$STATE_FILE" ]]; then
  echo
  echo "Last start state"
  echo "----------------"
  cat "$STATE_FILE"
fi
