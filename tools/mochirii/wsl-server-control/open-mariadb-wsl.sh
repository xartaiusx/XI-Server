#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script as root inside WSL." >&2
  exit 1
fi

MYSQL_DEFAULTS="$($SCRIPT_DIR/prepare-mariadb-client-config.sh)"
trap 'rm -f "$MYSQL_DEFAULTS"' EXIT

systemctl start mariadb.service >/dev/null
systemctl disable mariadb.service >/dev/null 2>&1 || true

mariadb --defaults-extra-file="$MYSQL_DEFAULTS" xidb
