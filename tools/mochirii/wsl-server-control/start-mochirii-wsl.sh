#!/usr/bin/env bash
set -euo pipefail

SERVER_ROOT="/home/xartyzx/projects/FFXI/XI-Server"
RUNTIME_ROOT="/home/xartyzx/projects/FFXI-Runtime"
LOG_ROOT="$RUNTIME_ROOT/logs/server"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/status-mochirii-wsl.sh"

SERVICES=(
  "mochirii-xi-profile.service"
  "mochirii-xi-connect.service"
  "mochirii-xi-search.service"
  "mochirii-xi-world.service"
  "mochirii-xi-map.service"
)

ALL_SERVICES=(
  "mariadb.service"
  "${SERVICES[@]}"
)

PORTS=(3306 51220 51240 54001 54002 54003 55030 55031)

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

cd "$SERVER_ROOT"

for binary in xi_profile xi_connect xi_search xi_world xi_map; do
  if [[ ! -x "$SERVER_ROOT/$binary" ]]; then
    echo "Missing executable: $SERVER_ROOT/$binary" >&2
    echo "Run the native WSL build before starting the server." >&2
    exit 1
  fi
done

CREDS_ROOT="/mnt/c/Github Repo's/FFXI/FFXI Creds"
for credential in profile.cert profile.key; do
  credential_link="$SERVER_ROOT/$credential"
  credential_target="$(realpath -e -- "$credential_link" 2>/dev/null || true)"
  if [[ ! -L "$credential_link" || ! -s "$credential_link" || "$credential_target" != "$CREDS_ROOT/"* ]]; then
    echo "Missing canonical credential link: $credential. Prepare its link to FFXI Creds before starting; no credentials were created." >&2
    exit 1
  fi
done

MYSQL_DEFAULTS=""
STATE_TEMP=""
START_ATTEMPTED=false

cleanup() {
  local result=$?
  trap - EXIT

  if [[ -n "$MYSQL_DEFAULTS" ]]; then
    rm -f "$MYSQL_DEFAULTS"
  fi
  if [[ -n "$STATE_TEMP" ]]; then
    rm -f "$STATE_TEMP"
  fi

  if (( result != 0 )) && [[ "$START_ATTEMPTED" == "true" ]]; then
    echo "Mochirii start failed; stopping the partial start and enforcing disabled autostart." >&2
    local index service
    for (( index=${#ALL_SERVICES[@]}-1; index >= 0; index-- )); do
      service="${ALL_SERVICES[$index]}"
      systemctl stop "$service" >/dev/null || true
      systemctl disable "$service" >/dev/null || true
      systemctl reset-failed "$service" >/dev/null 2>&1 || true
    done
    rm -f "$STATE_FILE"
    "$STATUS_SCRIPT" --expect-stopped-disabled || true
  fi

  exit "$result"
}

trap cleanup EXIT
MYSQL_DEFAULTS="$($SCRIPT_DIR/prepare-mariadb-client-config.sh)"
mkdir -p "$LOG_ROOT" "$SERVER_ROOT/log" "$(dirname "$STATE_FILE")"
mysql_args=(--defaults-extra-file="$MYSQL_DEFAULTS")

enforce_manual_start() {
  local service
  for service in "${ALL_SERVICES[@]}"; do
    systemctl disable "$service" >/dev/null
    if [[ "$(systemctl is-enabled "$service" || true)" != "disabled" ]]; then
      echo "$service is not disabled for autostart." >&2
      return 1
    fi
  done
}

START_ATTEMPTED=true
systemctl daemon-reload
enforce_manual_start

echo "Starting MariaDB..."
systemctl start mariadb.service >/dev/null

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

echo "Stopping any existing Mochirii XI services..."
for service in "${SERVICES[@]}"; do
  systemctl stop "$service" >/dev/null
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
done

echo "Starting Mochirii XI services..."
for service in "${SERVICES[@]}"; do
  systemctl start "$service"
  sleep 1
done

enforce_manual_start

port_is_listening() {
  local port="$1"
  ss -ltnH | awk '{ print $4 }' | grep -Eq "[:.]${port}$"
}

all_ready() {
  local service
  for service in "${ALL_SERVICES[@]}"; do
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
  ss -ltnp | grep -E ':(3306|51220|51240|54001|54002|54003|55030|55031)\b' || true
  exit 1
fi

"$STATUS_SCRIPT" --expect-running-manual
STATE_TEMP="$(mktemp "${STATE_FILE}.XXXXXX")"
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
} > "$STATE_TEMP"
mv -f "$STATE_TEMP" "$STATE_FILE"
STATE_TEMP=""

echo "Mochirii XI server is up."
echo "State: $STATE_FILE"
