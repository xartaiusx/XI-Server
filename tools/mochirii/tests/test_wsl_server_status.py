from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

STATUS_SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "wsl-server-control"
    / "status-mochirii-wsl.sh"
)

SERVICES = (
    "mariadb.service",
    "mochirii-xi-connect.service",
    "mochirii-xi-search.service",
    "mochirii-xi-world.service",
    "mochirii-xi-map.service",
)

XI_SERVICES = SERVICES[1:]
PORTS = (3306, 54001, 54002, 54003, 55030, 55031)
XI_PORTS = PORTS[1:]


class WslServerStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)

        self.root = Path(self.temporary.name)
        self.runtime_root = self.root / "runtime"
        self.runtime_root.mkdir()
        self.systemctl_state = self.root / "systemctl.tsv"
        self.socket_state = self.root / "sockets.txt"

        self.systemctl = self.root / "mock-systemctl"
        self.systemctl.write_text(
            """#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-}"
service="${2:-}"
row="$(awk -F '\t' -v wanted="$service" '$1 == wanted { print; found = 1 } END { if (!found) exit 1 }' "$MOCK_SYSTEMCTL_STATE")"

case "$command_name" in
  is-active)
    cut -f2 <<<"$row"
    ;;
  is-enabled)
    cut -f3 <<<"$row"
    ;;
  show)
    cut -f4 <<<"$row"
    ;;
  *)
    exit 2
    ;;
esac
""",
            encoding="utf-8",
        )
        self.systemctl.chmod(0o755)

        self.ss = self.root / "mock-ss"
        self.ss.write_text(
            """#!/usr/bin/env bash
set -euo pipefail

if [[ "${MOCK_SS_FAIL:-0}" == "1" ]]; then
  exit 1
fi

cat "$MOCK_SS_STATE"
""",
            encoding="utf-8",
        )
        self.ss.chmod(0o755)

    @staticmethod
    def running_state() -> dict[str, tuple[str, str, int]]:
        return {
            service: ("active", "disabled", 1000 + index)
            for index, service in enumerate(SERVICES)
        }

    @staticmethod
    def stopped_state() -> dict[str, tuple[str, str, int]]:
        return {service: ("inactive", "disabled", 0) for service in SERVICES}

    def run_status(
        self,
        mode: str,
        state: dict[str, tuple[str, str, int]],
        ports: tuple[int, ...] = (),
        *,
        socket_query_fails: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        state_rows = [
            "\t".join((service, active, enabled, str(pid)))
            for service, (active, enabled, pid) in state.items()
        ]
        self.systemctl_state.write_text("\n".join(state_rows) + "\n", encoding="utf-8")

        socket_rows = [
            f'LISTEN 0 128 127.0.0.1:{port} 0.0.0.0:* users:(("mock",pid=1,fd=1))'
            for port in ports
        ]
        self.socket_state.write_text("\n".join(socket_rows) + "\n", encoding="utf-8")

        environment = os.environ.copy()
        environment.update(
            {
                "MOCHIRII_RUNTIME_ROOT": str(self.runtime_root),
                "MOCHIRII_SYSTEMCTL_BIN": str(self.systemctl),
                "MOCHIRII_SS_BIN": str(self.ss),
                "MOCK_SYSTEMCTL_STATE": str(self.systemctl_state),
                "MOCK_SS_STATE": str(self.socket_state),
                "MOCK_SS_FAIL": "1" if socket_query_fails else "0",
            }
        )

        return subprocess.run(
            ["bash", str(STATUS_SCRIPT), mode],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_running_manual_accepts_exact_service_and_port_contract(self) -> None:
        result = self.run_status("--expect-running-manual", self.running_state(), PORTS)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("expectation satisfied", result.stdout)

    def test_running_manual_rejects_autostart_enabled_service(self) -> None:
        state = self.running_state()
        active, _, pid = state["mochirii-xi-map.service"]
        state["mochirii-xi-map.service"] = (active, "enabled", pid)

        result = self.run_status("--expect-running-manual", state, PORTS)

        self.assertEqual(result.returncode, 1)
        self.assertIn("enabled=enabled; expected disabled", result.stderr)

    def test_stopped_disabled_accepts_exact_quiescent_contract(self) -> None:
        result = self.run_status("--expect-stopped-disabled", self.stopped_state())

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("expectation satisfied", result.stdout)

    def test_stopped_disabled_rejects_declared_listener(self) -> None:
        result = self.run_status(
            "--expect-stopped-disabled", self.stopped_state(), (55031,)
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("port 55031 is listening; expected absent", result.stderr)

    def test_development_mode_preserves_only_manual_mariadb(self) -> None:
        state = self.stopped_state()
        state["mariadb.service"] = ("active", "disabled", 1000)

        result = self.run_status(
            "--expect-xi-stopped-db-running-manual",
            state,
            (3306,),
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_development_mode_rejects_xi_service_or_listener(self) -> None:
        state = self.stopped_state()
        state["mariadb.service"] = ("active", "disabled", 1000)
        state[XI_SERVICES[0]] = ("active", "disabled", 1001)

        result = self.run_status(
            "--expect-xi-stopped-db-running-manual",
            state,
            (3306, XI_PORTS[0]),
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("active=active; expected inactive", result.stderr)
        self.assertIn(
            f"port {XI_PORTS[0]} is listening; expected absent", result.stderr
        )

    def test_strict_mode_fails_closed_when_socket_query_fails(self) -> None:
        result = self.run_status(
            "--expect-stopped-disabled",
            self.stopped_state(),
            socket_query_fails=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("unable to query listening sockets", result.stderr)

    def test_unknown_expectation_is_usage_error(self) -> None:
        result = self.run_status("--unknown", self.stopped_state())

        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown status expectation", result.stderr)


if __name__ == "__main__":
    unittest.main()
