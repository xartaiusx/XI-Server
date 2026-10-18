#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/status-mochirii-wsl.sh"

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

if (( $# > 1 )) || [[ "${1:-}" != "" && "${1:-}" != "--start-db-only" ]]; then
  echo "Usage: open-mariadb-wsl.sh [--start-db-only]" >&2
  exit 2
fi

"$SCRIPT_DIR/prepare-mariadb-client-config.sh" --check
"$STATUS_SCRIPT" --expect-stopped-disabled

START_ATTEMPTED=false
cleanup() {
  local result=$?
  trap - EXIT
  if (( result != 0 )) && [[ "$START_ATTEMPTED" == "true" ]]; then
    systemctl stop mariadb.service >/dev/null || true
    systemctl disable mariadb.service >/dev/null || true
    "$STATUS_SCRIPT" --expect-stopped-disabled || true
  fi
  exit "$result"
}
trap cleanup EXIT

START_ATTEMPTED=true
systemctl disable mariadb.service >/dev/null
systemctl start mariadb.service >/dev/null
for _ in {1..30}; do
  if "$SCRIPT_DIR/prepare-mariadb-client-config.sh" -- mariadb -e "SELECT 1;" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
"$SCRIPT_DIR/prepare-mariadb-client-config.sh" -- mariadb -e "SELECT 1;" >/dev/null
"$STATUS_SCRIPT" --expect-xi-stopped-db-running-manual

if [[ "${1:-}" != "--start-db-only" ]]; then
  "$SCRIPT_DIR/prepare-mariadb-client-config.sh" -- mariadb xidb
fi
