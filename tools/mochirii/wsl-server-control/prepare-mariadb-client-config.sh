#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SOURCE="/mnt/c/Github Repo's/FFXI/FFXI Creds/Server/mariadb-client.cnf"
SOURCE="${MOCHIRII_MARIADB_CREDENTIAL_FILE:-$DEFAULT_SOURCE}"
TARGET_DIR="/run/mochirii"
TARGET="$TARGET_DIR/mariadb-client-$$.cnf"

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this helper as root inside WSL." >&2
  exit 1
fi

if [[ ! -r "$SOURCE" ]]; then
  echo "Mochirii MariaDB credential file is unavailable." >&2
  exit 1
fi

install -d -m 700 -o root -g root "$TARGET_DIR"
install -m 600 -o root -g root "$SOURCE" "$TARGET"
printf '%s\n' "$TARGET"
