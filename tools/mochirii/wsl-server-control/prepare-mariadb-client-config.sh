#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SOURCE="/mnt/c/Github Repo's/FFXI/FFXI Creds/Server/mariadb-client.cnf"
SOURCE="${MOCHIRII_MARIADB_CREDENTIAL_FILE:-$DEFAULT_SOURCE}"
SERVER_ROOT="/home/xartyzx/projects/FFXI/XI-Server"

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this helper as root inside WSL." >&2
  exit 1
fi

# This historical helper name is retained, but it never creates a credential
# copy or returns a path. Each native call owns one anonymous private memfd.
exec python3 "$SERVER_ROOT/tools/mysql_client.py" --credential-file "$SOURCE" "$@"
