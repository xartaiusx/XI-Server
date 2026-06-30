#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
db_artifact=""
db_pass_file=""
windower_artifact=""
windower_pass_file=""
db_name="${MOCHIRII_DB_NAME:-xidb}"
db_user="${MOCHIRII_DB_USER:-xi}"
db_password="${MOCHIRII_DB_PASSWORD:-change-me}"
install_deps=0
start_server=0

usage() {
  cat <<'USAGE'
Usage: restore_garuda.sh --db-artifact FILE --db-pass-file FILE [options]

Options:
  --windower-artifact FILE       Optional encrypted Windower golden-state bundle.
  --windower-pass-file FILE      Passphrase file for the Windower bundle.
  --db-name NAME                 Default: xidb.
  --db-user USER                 Default: xi.
  --db-password PASSWORD         Default: MOCHIRII_DB_PASSWORD or change-me.
  --install-deps                 Install Arch/Garuda packages with sudo pacman.
  --start-server                 Start xi_connect, xi_search, xi_world, and xi_map after build.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-artifact) db_artifact="$2"; shift 2 ;;
    --db-pass-file) db_pass_file="$2"; shift 2 ;;
    --windower-artifact) windower_artifact="$2"; shift 2 ;;
    --windower-pass-file) windower_pass_file="$2"; shift 2 ;;
    --db-name) db_name="$2"; shift 2 ;;
    --db-user) db_user="$2"; shift 2 ;;
    --db-password) db_password="$2"; shift 2 ;;
    --install-deps) install_deps=1; shift ;;
    --start-server) start_server=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$db_artifact" || -z "$db_pass_file" ]]; then
  usage >&2
  exit 2
fi

required_commands=(git python cmake ninja openssl gzip mariadb mariadb-dump)
missing=()
for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if (( ${#missing[@]} )); then
  echo "Missing commands: ${missing[*]}" >&2
  if (( install_deps )); then
    sudo pacman -S --needed git python python-pip base-devel cmake ninja luajit zeromq openssl zlib mariadb mariadb-libs binutils
  else
    echo "Install Arch/Garuda dependencies or rerun with --install-deps." >&2
    exit 1
  fi
fi

if ! systemctl is-active --quiet mariadb; then
  if [[ ! -d /var/lib/mysql/mysql ]]; then
    sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
  fi
  sudo systemctl enable --now mariadb
fi

sql_escape() {
  printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/''/g"
}

db_name_sql="${db_name//\`/\`\`}"
db_user_sql="$(sql_escape "$db_user")"
db_password_sql="$(sql_escape "$db_password")"

sudo mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`$db_name_sql\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$db_user_sql'@'localhost' IDENTIFIED BY '$db_password_sql';
CREATE USER IF NOT EXISTS '$db_user_sql'@'127.0.0.1' IDENTIFIED BY '$db_password_sql';
GRANT ALL PRIVILEGES ON \`$db_name_sql\`.* TO '$db_user_sql'@'localhost';
GRANT ALL PRIVILEGES ON \`$db_name_sql\`.* TO '$db_user_sql'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass "file:$db_pass_file" -in "$db_artifact" \
  | gzip -dc \
  | sudo mariadb

if [[ ! -f "$repo_root/settings/network.lua" ]]; then
  cp "$repo_root/restore/templates/network.lua.example" "$repo_root/settings/network.lua"
  python - "$repo_root/settings/network.lua" "$db_user" "$db_password" "$db_name" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace('"xi"', repr(sys.argv[2]).replace("'", '"'))
text = text.replace('"change-me"', repr(sys.argv[3]).replace("'", '"'))
text = text.replace('"xidb"', repr(sys.argv[4]).replace("'", '"'))
  path.write_text(text, encoding="utf-8")
PY
fi

if [[ ! -d "$repo_root/.venv" ]]; then
  python -m venv "$repo_root/.venv"
fi
source "$repo_root/.venv/bin/activate"
python -m pip install -r "$repo_root/tools/requirements.txt"
python "$repo_root/tools/dbtool.py" update full
python "$repo_root/tools/dbtool.py" update full

cmake --preset default
cmake --build --preset default --parallel 6

if [[ -n "$windower_artifact" ]]; then
  if [[ -z "$windower_pass_file" ]]; then
    echo "--windower-pass-file is required with --windower-artifact" >&2
    exit 2
  fi
  mkdir -p "${MOCHIRII_RUNTIME_ROOT:-$HOME/FFXI-Runtime}"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass "file:$windower_pass_file" -in "$windower_artifact" \
    | tar -xzf - -C "${MOCHIRII_RUNTIME_ROOT:-$HOME/FFXI-Runtime}"
fi

if (( start_server )); then
  mkdir -p "$repo_root/log"
  "$repo_root/xi_connect" --log log/connect-server.log &
  "$repo_root/xi_search" --log log/search-server.log &
  "$repo_root/xi_world" --log log/world-server.log &
  "$repo_root/xi_map" --log log/map-server-54230.log --ip 127.0.0.1 --port 54230 &
fi

python "$repo_root/tools/mochirii/portable_restore/verify_restore.py" --repo-root "$repo_root" --check-manifests
