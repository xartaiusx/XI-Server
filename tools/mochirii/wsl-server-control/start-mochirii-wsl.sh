#!/usr/bin/env bash
set -euo pipefail

SERVER_ROOT="/home/xartyzx/projects/FFXI/XI-Server"
RUNTIME_ROOT="/home/xartyzx/projects/FFXI-Runtime"
LOG_ROOT="$RUNTIME_ROOT/logs/server"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SERVICES=(
  "mochirii-xi-connect.service"
  "mochirii-xi-search.service"
  "mochirii-xi-world.service"
  "mochirii-xi-map.service"
)

PORTS=(54001 54002 54003 55030 55031)

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

MYSQL_DEFAULTS="$($SCRIPT_DIR/prepare-mariadb-client-config.sh)"
trap 'rm -f "$MYSQL_DEFAULTS"' EXIT

mkdir -p "$LOG_ROOT" "$SERVER_ROOT/log" "$(dirname "$STATE_FILE")"
cd "$SERVER_ROOT"

for binary in xi_connect xi_search xi_world xi_map; do
  if [[ ! -x "$SERVER_ROOT/$binary" ]]; then
    echo "Missing executable: $SERVER_ROOT/$binary" >&2
    echo "Run the native WSL build before starting the server." >&2
    exit 1
  fi
done

mysql_args=(--defaults-extra-file="$MYSQL_DEFAULTS")

echo "Starting MariaDB..."
systemctl start mariadb.service >/dev/null
systemctl disable mariadb.service >/dev/null 2>&1 || true

for _ in {1..30}; do
  if mariadb "${mysql_args[@]}" -h127.0.0.1 -P3306 -e "SELECT 1;" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

mariadb "${mysql_args[@]}" -h127.0.0.1 -P3306 -e "
UPDATE xidb.zone_settings SET zoneip='127.0.0.1' WHERE zoneip <> '127.0.0.1';
UPDATE xidb.zone_settings SET zoneport=55030 WHERE zoneport <> 55030;
"

systemctl daemon-reload

echo "Stopping any existing Mochirii XI services..."
for service in "${SERVICES[@]}"; do
  systemctl stop "$service" >/dev/null 2>&1 || true
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
done

echo "Starting Mochirii XI services..."
for service in "${SERVICES[@]}"; do
  systemctl start "$service"
  sleep 1
done

port_is_listening() {
  local port="$1"
  ss -ltnH | awk '{ print $4 }' | grep -Eq "[:.]${port}$"
}

all_ready() {
  local service
  for service in "${SERVICES[@]}"; do
    systemctl is-active --quiet "$service" || return 1
  done

  local port
  for port in "${PORTS[@]}"; do
    port_is_listening "$port" || return 1
  done
}

for _ in {1..90}; do
  if all_ready; then
    break
  fi
  sleep 1
done

if ! all_ready; then
  echo "Mochirii XI did not become fully ready. Current status:" >&2
  systemctl --no-pager --full status "${SERVICES[@]}" || true
  ss -ltnp | grep -E ':(3306|54001|54002|54003|55030|55031)\b' || true
  exit 1
fi

{
  echo "{"
  echo "  \"started_at\": \"$(date --iso-8601=seconds)\","
  echo "  \"server_root\": \"$SERVER_ROOT\","
  echo "  \"services\": {"
  for index in "${!SERVICES[@]}"; do
    service="${SERVICES[$index]}"
    pid="$(systemctl show "$service" -p MainPID --value)"
    active="$(systemctl is-active "$service")"
    comma=","
    if [[ "$index" == "$((${#SERVICES[@]} - 1))" ]]; then
      comma=""
    fi
    echo "    \"$service\": { \"active\": \"$active\", \"main_pid\": \"$pid\" }$comma"
  done
  echo "  }"
  echo "}"
} > "$STATE_FILE"

echo "Mochirii XI server is up."
echo "State: $STATE_FILE"
ss -ltnp | grep -E ':(3306|54001|54002|54003|55030|55031)\b' || true
