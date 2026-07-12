#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
runtime_root="${MOCHIRII_RUNTIME_ROOT:-/mnt/c/Github Repo's/FFXI/Runtime}"
mariadb_bin="${MOCHIRII_MARIADB_BIN:-/mnt/c/Program Files/MariaDB 12.3/bin}"
mariadb_defaults="${MOCHIRII_MARIADB_DEFAULTS:-C:\\Program Files\\MariaDB 12.3\\data\\my.ini}"
database_name="${MOCHIRII_DB_NAME:-xidb}"
database_user="${MOCHIRII_DB_USER:-root}"
database_password="${MOCHIRII_DB_PASSWORD:-root}"
skip_database=0
skip_windower=0

usage() {
  cat <<'USAGE'
Usage: capture_windows_from_wsl.sh [options]

Options:
  --skip-database       Do not capture encrypted xidb dump.
  --skip-windower       Do not capture encrypted Windower golden-state bundle.
  --database-password P Override local MariaDB password. Default: MOCHIRII_DB_PASSWORD or root.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-database) skip_database=1; shift ;;
    --skip-windower) skip_windower=1; shift ;;
    --database-password) database_password="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

artifact_dir="$runtime_root/portable-restore/artifacts"
secret_dir="$runtime_root/secrets"
log_dir="$runtime_root/logs/portable-restore"
mkdir -p "$artifact_dir" "$secret_dir" "$log_dir"

need_commands=(openssl gzip tar powershell.exe)
for cmd in "${need_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

test_port_3306() {
  powershell.exe -NoProfile -Command '$client=New-Object System.Net.Sockets.TcpClient; try { $iar=$client.BeginConnect("127.0.0.1",3306,$null,$null); if($iar.AsyncWaitHandle.WaitOne(500,$false)){ $client.EndConnect($iar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $client.Dispose() }' >/dev/null 2>&1
}

start_mariadb_if_needed() {
  if test_port_3306; then
    return 1
  fi

  powershell.exe -NoProfile -Command "Start-Process -FilePath 'C:\\Program Files\\MariaDB 12.3\\bin\\mariadbd.exe' -ArgumentList '--defaults-file=\"$mariadb_defaults\"' -RedirectStandardOutput 'C:\\Users\\xtyty\\Documents\\FFXI-Runtime\\logs\\portable-restore\\mariadb-capture.stdout.log' -RedirectStandardError 'C:\\Users\\xtyty\\Documents\\FFXI-Runtime\\logs\\portable-restore\\mariadb-capture.stderr.log' -WindowStyle Minimized" >/dev/null

  for _ in $(seq 1 45); do
    if test_port_3306; then
      return 0
    fi
    sleep 1
  done

  echo "MariaDB did not start on 127.0.0.1:3306." >&2
  exit 1
}

write_json_manifest() {
  local path="$1"
  local kind="$2"
  local artifact="$3"
  local pass_file="$4"
  python3 - "$path" "$kind" "$artifact" "$pass_file" <<'PY'
from pathlib import Path
import datetime as dt
import hashlib
import json
import sys

path = Path(sys.argv[1])
kind = sys.argv[2]
artifact = Path(sys.argv[3])
pass_file = Path(sys.argv[4])
h = hashlib.sha256()
with artifact.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        h.update(chunk)

data = {
    "capturedAt": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    "kind": kind,
    "artifact": artifact.name,
    "bytes": artifact.stat().st_size,
    "sha256": h.hexdigest(),
    "passphrasePath": "C:/Users/xtyty/Documents/FFXI-Runtime/secrets/" + pass_file.name,
    "plaintextCommitted": False,
}
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

stamp="$(date +%Y%m%d-%H%M%S)"
started_mariadb=0

if (( ! skip_database )); then
  if start_mariadb_if_needed; then
    started_mariadb=1
  fi

  pass_file="$secret_dir/mochirii-restore-db-$stamp.passphrase.txt"
  openssl rand -base64 48 > "$pass_file"
  chmod 600 "$pass_file" || true
  artifact="$artifact_dir/xidb-twills-$stamp.sql.gz.enc"

  "$mariadb_bin/mariadb-dump.exe" \
    "-u$database_user" "--password=$database_password" -h127.0.0.1 -P3306 \
    --databases "$database_name" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --default-character-set=utf8mb4 \
    --add-drop-database \
    --add-drop-table \
    --add-drop-trigger \
    2> "$log_dir/mariadb-dump-$stamp.stderr.log" \
    | gzip -9 \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass "file:$pass_file" -out "$artifact"

  sha256sum "$artifact" > "$artifact.sha256"
  write_json_manifest "$artifact.manifest.json" "database" "$artifact" "$pass_file"
fi

if (( ! skip_windower )); then
  golden_root="$runtime_root/windower-golden-state"
  [[ -d "$golden_root" ]] || {
    echo "Missing Windower golden state: $golden_root" >&2
    exit 1
  }

  pass_file="$secret_dir/mochirii-restore-windower-$stamp.passphrase.txt"
  openssl rand -base64 48 > "$pass_file"
  chmod 600 "$pass_file" || true
  artifact="$artifact_dir/windower-golden-state-$stamp.tar.gz.enc"
  tar -C "$runtime_root" -czf - windower-golden-state \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass "file:$pass_file" -out "$artifact"
  sha256sum "$artifact" > "$artifact.sha256"
  write_json_manifest "$artifact.manifest.json" "windower-golden-state" "$artifact" "$pass_file"
fi

if (( started_mariadb )); then
  "$mariadb_bin/mysqladmin.exe" "-u$database_user" "--password=$database_password" -h127.0.0.1 -P3306 shutdown >/dev/null 2>&1 || true
fi

echo "Portable restore capture complete: $artifact_dir"
