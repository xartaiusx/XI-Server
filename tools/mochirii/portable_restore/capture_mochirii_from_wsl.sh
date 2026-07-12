#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
runtime_root="${MOCHIRII_RUNTIME_ROOT:-/home/xartyzx/projects/FFXI-Runtime}"
windows_runtime_root="${MOCHIRII_WINDOWS_RUNTIME_ROOT:-}"
credential_root="${MOCHIRII_CREDENTIAL_ROOT:-}"
[[ -n "$windows_runtime_root" ]] || windows_runtime_root="/mnt/c/Github Repo's/FFXI/Runtime"
[[ -n "$credential_root" ]] || credential_root="/mnt/c/Github Repo's/FFXI/FFXI Creds"
mariadb_cnf="${MOCHIRII_MARIADB_CNF:-$credential_root/Server/mariadb-client.cnf}"
database_name="${MOCHIRII_DB_NAME:-xidb}"
skip_database=0
skip_windower=0
started_mariadb=0

usage() {
  cat <<'USAGE'
Usage: capture_mochirii_from_wsl.sh [options]

Options:
  --skip-database  Do not capture the encrypted xidb dump.
  --skip-windower  Do not capture the encrypted Windower golden-state bundle.
  -h, --help       Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-database) skip_database=1; shift ;;
    --skip-windower) skip_windower=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

artifact_dir="$runtime_root/portable-restore/artifacts"
secret_dir="$credential_root/Runtime"
log_dir="$runtime_root/logs/portable-restore"
mkdir -p "$artifact_dir" "$secret_dir" "$log_dir"

need_commands=(gzip mariadb mariadb-dump openssl python3 sha256sum tar)
for cmd in "${need_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

if (( ! skip_database )) && [[ ! -r "$mariadb_cnf" ]]; then
  echo "Missing canonical MariaDB client config: $mariadb_cnf" >&2
  exit 1
fi

run_systemctl() {
  if [[ "$(id -u)" == "0" ]]; then
    systemctl "$@"
  else
    sudo -n systemctl "$@"
  fi
}

stop_started_mariadb() {
  if (( started_mariadb )); then
    run_systemctl stop mariadb.service >/dev/null 2>&1 || true
  fi
}
trap stop_started_mariadb EXIT

ensure_mariadb() {
  if systemctl is-active --quiet mariadb.service; then
    return
  fi

  run_systemctl start mariadb.service
  run_systemctl disable mariadb.service >/dev/null 2>&1 || true
  started_mariadb=1

  for _ in {1..45}; do
    if mariadb --defaults-extra-file="$mariadb_cnf" -h127.0.0.1 -P3306 -e "SELECT 1;" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  echo "MariaDB did not become ready on 127.0.0.1:3306." >&2
  exit 1
}

write_json_manifest() {
  local path="$1"
  local kind="$2"
  local artifact="$3"
  local pass_file="$4"

  python3 - "$path" "$kind" "$artifact" "$pass_file" "$repo_root" <<'PY'
from pathlib import Path
import datetime as dt
import hashlib
import json
import sys

path = Path(sys.argv[1])
kind = sys.argv[2]
artifact = Path(sys.argv[3])
pass_file = Path(sys.argv[4])
repo_root = Path(sys.argv[5])

digest = hashlib.sha256()
with artifact.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)

data = {
    "capturedAt": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    "kind": kind,
    "artifact": artifact.name,
    "artifactPath": str(artifact),
    "bytes": artifact.stat().st_size,
    "sha256": digest.hexdigest(),
    "passphrasePath": (
        "C:/Github Repo's/FFXI/FFXI Creds/Runtime/" + pass_file.name
    ),
    "repoRoot": str(repo_root),
    "plaintextCommitted": False,
}
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

stamp="$(date +%Y%m%d-%H%M%S)"

if (( ! skip_database )); then
  ensure_mariadb

  pass_file="$secret_dir/mochirii-restore-db-$stamp.passphrase.txt"
  openssl rand -base64 48 > "$pass_file"
  chmod 600 "$pass_file" 2>/dev/null || true
  artifact="$artifact_dir/xidb-twills-$stamp.sql.gz.enc"

  mariadb-dump \
    --defaults-extra-file="$mariadb_cnf" \
    -h127.0.0.1 \
    -P3306 \
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
    | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 \
        -pass "file:$pass_file" -out "$artifact"

  sha256sum "$artifact" > "$artifact.sha256"
  write_json_manifest "$artifact.manifest.json" "database" "$artifact" "$pass_file"
fi

if (( ! skip_windower )); then
  golden_root="$windows_runtime_root/windower-golden-state"
  [[ -d "$golden_root" ]] || {
    echo "Missing canonical Windower golden state: $golden_root" >&2
    exit 1
  }

  pass_file="$secret_dir/mochirii-restore-windower-$stamp.passphrase.txt"
  openssl rand -base64 48 > "$pass_file"
  chmod 600 "$pass_file" 2>/dev/null || true
  artifact="$artifact_dir/windower-golden-state-$stamp.tar.gz.enc"

  tar -C "$windows_runtime_root" -czf - windower-golden-state \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 \
        -pass "file:$pass_file" -out "$artifact"

  sha256sum "$artifact" > "$artifact.sha256"
  write_json_manifest "$artifact.manifest.json" "windower-golden-state" "$artifact" "$pass_file"
fi

echo "Portable restore capture complete: $artifact_dir"
