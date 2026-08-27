#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ROOT="${MOCHIRII_RUNTIME_ROOT:-/home/xartyzx/projects/FFXI-Runtime}"
STATE_FILE="$RUNTIME_ROOT/server-control/mochirii-server-state.json"
SYSTEMCTL_BIN="${MOCHIRII_SYSTEMCTL_BIN:-systemctl}"
SS_BIN="${MOCHIRII_SS_BIN:-ss}"

SERVICES=(
  "mariadb.service"
  "mochirii-xi-connect.service"
  "mochirii-xi-search.service"
  "mochirii-xi-world.service"
  "mochirii-xi-map.service"
)

XI_SERVICES=(
  "mochirii-xi-connect.service"
  "mochirii-xi-search.service"
  "mochirii-xi-world.service"
  "mochirii-xi-map.service"
)

PORTS=(3306 54001 54002 54003 55030 55031)
XI_PORTS=(54001 54002 54003 55030 55031)

usage() {
  cat <<'EOF'
Usage: status-mochirii-wsl.sh [expectation]

Expectations:
  --expect-running-manual               All Mochirii services are active,
                                        disabled for autostart, have live PIDs,
                                        and own every declared listener.
  --expect-stopped-disabled             All Mochirii services are inactive,
                                        disabled for autostart, have PID 0,
                                        and own no declared listener.
  --expect-xi-stopped-db-running-manual XI services are stopped and disabled;
                                        MariaDB remains active but disabled.

With no expectation, print the current state without enforcing one.
EOF
}

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

MODE="${1:-summary}"
case "$MODE" in
  summary | --expect-running-manual | --expect-stopped-disabled | --expect-xi-stopped-db-running-manual)
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown status expectation: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac

declare -A SERVICE_ACTIVE=()
declare -A SERVICE_ENABLED=()
declare -A SERVICE_PID=()

for service in "${SERVICES[@]}"; do
  active="$("$SYSTEMCTL_BIN" is-active "$service" 2>/dev/null || true)"
  enabled="$("$SYSTEMCTL_BIN" is-enabled "$service" 2>/dev/null || true)"
  pid="$("$SYSTEMCTL_BIN" show "$service" -p MainPID --value 2>/dev/null || true)"

  SERVICE_ACTIVE["$service"]="${active:-unknown}"
  SERVICE_ENABLED["$service"]="${enabled:-unknown}"
  SERVICE_PID["$service"]="${pid:-unknown}"
done

SS_AVAILABLE=true
if ! LISTENING_LINES="$("$SS_BIN" -ltnp 2>/dev/null)"; then
  SS_AVAILABLE=false
  LISTENING_LINES=""
fi

mapfile -t LISTENING_ENDPOINTS < <(
  printf '%s\n' "$LISTENING_LINES" |
    awk 'NF >= 4 && $1 != "State" { print $4 }'
)

port_is_listening() {
  local port="$1"
  local endpoint

  for endpoint in "${LISTENING_ENDPOINTS[@]}"; do
    if [[ "$endpoint" =~ [:\.]${port}$ ]]; then
      return 0
    fi
  done

  return 1
}

echo "Mochirii WSL service summary"
echo "============================"

for service in "${SERVICES[@]}"; do
  printf '%-30s active=%-10s enabled=%-10s pid=%s\n' \
    "$service" \
    "${SERVICE_ACTIVE[$service]}" \
    "${SERVICE_ENABLED[$service]}" \
    "${SERVICE_PID[$service]}"
done

echo
echo "Listening ports"
echo "---------------"

MATCHING_LINES="$(
  printf '%s\n' "$LISTENING_LINES" |
    grep -E ':(3306|54001|54002|54003|55030|55031)\b' || true
)"

if [[ -n "$MATCHING_LINES" ]]; then
  printf '%s\n' "$MATCHING_LINES"
else
  echo "No Mochirii ports are listening."
fi

if [[ -f "$STATE_FILE" ]]; then
  echo
  echo "Last start state"
  echo "----------------"
  cat "$STATE_FILE"
fi

if [[ "$MODE" == "summary" ]]; then
  if [[ "$SS_AVAILABLE" != "true" ]]; then
    echo "Warning: unable to query listening sockets with $SS_BIN." >&2
  fi
  exit 0
fi

ERROR_COUNT=0

record_error() {
  echo "Expectation mismatch: $*" >&2
  ERROR_COUNT=$((ERROR_COUNT + 1))
}

expect_service() {
  local service="$1"
  local expected_active="$2"
  local expected_pid="$3"
  local actual_active="${SERVICE_ACTIVE[$service]}"
  local actual_enabled="${SERVICE_ENABLED[$service]}"
  local actual_pid="${SERVICE_PID[$service]}"

  if [[ "$actual_active" != "$expected_active" ]]; then
    record_error "$service active=$actual_active; expected $expected_active"
  fi

  if [[ "$actual_enabled" != "disabled" ]]; then
    record_error "$service enabled=$actual_enabled; expected disabled"
  fi

  case "$expected_pid" in
    positive)
      if [[ ! "$actual_pid" =~ ^[0-9]+$ ]] || (( 10#$actual_pid <= 0 )); then
        record_error "$service pid=$actual_pid; expected a positive PID"
      fi
      ;;
    zero)
      if [[ "$actual_pid" != "0" ]]; then
        record_error "$service pid=$actual_pid; expected 0"
      fi
      ;;
    *)
      echo "Internal status error: unknown PID expectation $expected_pid" >&2
      exit 2
      ;;
  esac
}

expect_port() {
  local port="$1"
  local expectation="$2"

  if [[ "$expectation" == "present" ]] && ! port_is_listening "$port"; then
    record_error "port $port is not listening; expected present"
  elif [[ "$expectation" == "absent" ]] && port_is_listening "$port"; then
    record_error "port $port is listening; expected absent"
  fi
}

if [[ "$SS_AVAILABLE" != "true" ]]; then
  record_error "unable to query listening sockets with $SS_BIN"
fi

case "$MODE" in
  --expect-running-manual)
    for service in "${SERVICES[@]}"; do
      expect_service "$service" active positive
    done
    for port in "${PORTS[@]}"; do
      expect_port "$port" present
    done
    ;;
  --expect-stopped-disabled)
    for service in "${SERVICES[@]}"; do
      expect_service "$service" inactive zero
    done
    for port in "${PORTS[@]}"; do
      expect_port "$port" absent
    done
    ;;
  --expect-xi-stopped-db-running-manual)
    expect_service "mariadb.service" active positive
    for service in "${XI_SERVICES[@]}"; do
      expect_service "$service" inactive zero
    done
    expect_port 3306 present
    for port in "${XI_PORTS[@]}"; do
      expect_port "$port" absent
    done
    ;;
esac

if (( ERROR_COUNT > 0 )); then
  echo "Mochirii status expectation failed with $ERROR_COUNT mismatch(es)." >&2
  exit 1
fi

echo
echo "Mochirii status expectation satisfied: $MODE"
