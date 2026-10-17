from __future__ import annotations

import json
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
    "mochirii-xi-profile.service",
    "mochirii-xi-connect.service",
    "mochirii-xi-search.service",
    "mochirii-xi-world.service",
    "mochirii-xi-map.service",
)

XI_SERVICES = SERVICES[1:]
PORTS = (3306, 51220, 51240, 54001, 54002, 54003, 55030, 55031)
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
if [[ "$command_name" == "${MOCK_SYSTEMCTL_FAIL_COMMAND:-}" && "$service" == "${MOCK_SYSTEMCTL_FAIL_SERVICE:-}" ]]; then
  echo "${MOCK_SYSTEMCTL_FAIL_OUTPUT:-}"
  exit 4
fi
row="$(awk -F '\t' -v wanted="$service" '$1 == wanted { print; found = 1 } END { if (!found) exit 1 }' "$MOCK_SYSTEMCTL_STATE")"

case "$command_name" in
  is-active)
    active="$(cut -f2 <<<"$row")"
    echo "$active"
    [[ "$active" == "active" ]] || exit 3
    ;;
  is-enabled)
    enabled="$(cut -f3 <<<"$row")"
    echo "$enabled"
    [[ "$enabled" == "enabled" ]] || exit 1
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
        service_query_failure: tuple[str, str, str] = ("", "", ""),
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
                "MOCK_SYSTEMCTL_FAIL_COMMAND": service_query_failure[0],
                "MOCK_SYSTEMCTL_FAIL_SERVICE": service_query_failure[1],
                "MOCK_SYSTEMCTL_FAIL_OUTPUT": service_query_failure[2],
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

    def test_running_manual_rejects_uninstalled_profile_unit(self) -> None:
        state = self.running_state()
        del state["mochirii-xi-profile.service"]

        result = self.run_status("--expect-running-manual", state, PORTS)

        self.assertEqual(result.returncode, 1)
        self.assertIn("mochirii-xi-profile.service active=unknown", result.stderr)

    def test_running_manual_requires_both_profile_listeners(self) -> None:
        for missing_port in (51220, 51240):
            with self.subTest(missing_port=missing_port):
                result = self.run_status(
                    "--expect-running-manual",
                    self.running_state(),
                    tuple(port for port in PORTS if port != missing_port),
                )

                self.assertEqual(result.returncode, 1)
                self.assertIn(
                    f"port {missing_port} is not listening; expected present",
                    result.stderr,
                )

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

    def test_stopped_disabled_rejects_profile_service_or_listeners(self) -> None:
        state = self.stopped_state()
        state["mochirii-xi-profile.service"] = ("active", "disabled", 1001)

        result = self.run_status("--expect-stopped-disabled", state, (51220, 51240))

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "mochirii-xi-profile.service active=active; expected inactive",
            result.stderr,
        )
        for port in (51220, 51240):
            self.assertIn(f"port {port} is listening; expected absent", result.stderr)

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

    def test_strict_modes_reject_enabled_profile_service(self) -> None:
        for mode in (
            "--expect-running-manual",
            "--expect-stopped-disabled",
            "--expect-xi-stopped-db-running-manual",
        ):
            with self.subTest(mode=mode):
                if mode == "--expect-running-manual":
                    state, ports = self.running_state(), PORTS
                else:
                    state, ports = self.stopped_state(), ()
                    if mode == "--expect-xi-stopped-db-running-manual":
                        state["mariadb.service"] = ("active", "disabled", 1000)
                        ports = (3306,)
                active, _, pid = state["mochirii-xi-profile.service"]
                state["mochirii-xi-profile.service"] = (active, "enabled", pid)

                result = self.run_status(mode, state, ports)

                self.assertEqual(result.returncode, 1)
                self.assertIn(
                    "mochirii-xi-profile.service enabled=enabled; expected disabled",
                    result.stderr,
                )

    def test_service_query_failure_cannot_masquerade_as_valid_state(self) -> None:
        for command, output in (
            ("is-active", "active"),
            ("is-enabled", "disabled"),
            ("show", "1001"),
        ):
            with self.subTest(command=command):
                result = self.run_status(
                    "--expect-running-manual",
                    self.running_state(),
                    PORTS,
                    service_query_failure=(
                        command,
                        "mochirii-xi-profile.service",
                        output,
                    ),
                )

                self.assertEqual(result.returncode, 1)
                self.assertIn("mochirii-xi-profile.service", result.stderr)
                self.assertIn("unknown", result.stderr)

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


class WslServerLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.server_root = self.root / "server"
        self.runtime_root = self.root / "runtime"
        self.creds_root = self.root / "fixture-credentials"
        self.bin_root = self.root / "bin"
        self.script_root = self.root / "controls"
        for directory in (
            self.server_root,
            self.runtime_root,
            self.creds_root,
            self.bin_root,
            self.script_root,
        ):
            directory.mkdir()

        self.state_path = self.root / "systemctl.json"
        self.log_path = self.root / "systemctl.log"
        self.write_state(WslServerStatusTests.stopped_state())
        self.log_path.write_text("", encoding="utf-8")
        self.defaults_path = self.root / "fixture-defaults.cnf"
        self.defaults_path.write_text("", encoding="utf-8")
        self.state_file = (
            self.runtime_root / "server-control" / "mochirii-server-state.json"
        )

        for binary in ("xi_profile", "xi_connect", "xi_search", "xi_world", "xi_map"):
            self.write_executable(self.server_root / binary, "#!/bin/sh\nexit 0\n")
        for binary, body in (
            ("id", "#!/bin/sh\necho 0\n"),
            ("sleep", "#!/bin/sh\nexit 0\n"),
            ("mariadb", "#!/bin/sh\nexit 0\n"),
        ):
            self.write_executable(self.bin_root / binary, body)

        self.write_executable(
            self.bin_root / "systemctl",
            """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

command, *arguments = sys.argv[1:]
service = next((argument for argument in arguments if argument.endswith('.service')), '')
state_path = Path(os.environ['MOCK_SYSTEMCTL_STATE'])
state = json.loads(state_path.read_text())
with Path(os.environ['MOCK_SYSTEMCTL_LOG']).open('a') as stream:
    stream.write(' '.join(sys.argv[1:]) + '\\n')
if command == os.environ.get('MOCK_FAIL_COMMAND') and service == os.environ.get('MOCK_FAIL_SERVICE'):
    sys.exit(1)
if command in ('daemon-reload', 'reset-failed'):
    sys.exit(0)
if service not in state:
    sys.exit(4)
active, enabled, pid = state[service]
if command == 'is-active':
    if '--quiet' not in arguments:
        print(active)
    sys.exit(0 if active == 'active' else 3)
if command == 'is-enabled':
    print(enabled)
    sys.exit(0 if enabled == 'enabled' else 1)
if command == 'show':
    print(pid)
    sys.exit(0)
if command == 'disable':
    enabled = 'disabled'
elif command == 'start':
    active, pid = 'active', 1000 + list(state).index(service)
elif command == 'stop':
    active, pid = 'inactive', 0
else:
    sys.exit(2)
state[service] = [active, enabled, pid]
state_path.write_text(json.dumps(state))
""",
        )
        self.write_executable(
            self.bin_root / "ss",
            """#!/usr/bin/env python3
import json
import os
from pathlib import Path

state = json.loads(Path(os.environ['MOCK_SYSTEMCTL_STATE']).read_text())
ports = {
    'mariadb.service': (3306,),
    'mochirii-xi-profile.service': (51220, 51240),
    'mochirii-xi-connect.service': (54001, 54002),
    'mochirii-xi-search.service': (54003,),
    'mochirii-xi-world.service': (55031,),
    'mochirii-xi-map.service': (55030,),
}
for service, listeners in ports.items():
    if state[service][0] == 'active':
        for port in listeners:
            print(f'LISTEN 0 128 127.0.0.1:{port} 0.0.0.0:*')
""",
        )

        for filename in (
            "start-mochirii-wsl.sh",
            "stop-mochirii-wsl.sh",
            "status-mochirii-wsl.sh",
        ):
            source = (STATUS_SCRIPT.parent / filename).read_text(encoding="utf-8")
            source = (
                source.replace(
                    "/home/xartyzx/projects/FFXI/XI-Server", str(self.server_root)
                )
                .replace("/home/xartyzx/projects/FFXI-Runtime", str(self.runtime_root))
                .replace("/mnt/c/Github Repo's/FFXI/FFXI Creds", str(self.creds_root))
            )
            self.write_executable(self.script_root / filename, source)
        self.write_executable(
            self.script_root / "prepare-mariadb-client-config.sh",
            f"#!/bin/sh\nprintf '%s\\n' '{self.defaults_path}'\n",
        )

    @staticmethod
    def write_executable(path: Path, content: str) -> None:
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def write_state(self, state: dict[str, tuple[str, str, int]]) -> None:
        self.state_path.write_text(json.dumps(state), encoding="utf-8")

    def prepare_profile_links(self) -> None:
        for filename in ("profile.cert", "profile.key"):
            fixture = self.creds_root / filename
            fixture.write_text("non-credential test fixture\n", encoding="utf-8")
            (self.server_root / filename).symlink_to(fixture)

    def run_control(
        self, filename: str, *arguments: str, fail: tuple[str, str] = ("", "")
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin_root}:{environment['PATH']}",
                "MOCHIRII_RUNTIME_ROOT": str(self.runtime_root),
                "MOCHIRII_SYSTEMCTL_BIN": str(self.bin_root / "systemctl"),
                "MOCHIRII_SS_BIN": str(self.bin_root / "ss"),
                "MOCK_SYSTEMCTL_STATE": str(self.state_path),
                "MOCK_SYSTEMCTL_LOG": str(self.log_path),
                "MOCK_FAIL_COMMAND": fail[0],
                "MOCK_FAIL_SERVICE": fail[1],
            }
        )
        return subprocess.run(
            ["bash", str(self.script_root / filename), *arguments],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=20,
        )

    def test_start_rejects_missing_profile_links_before_service_changes(self) -> None:
        result = self.run_control("start-mochirii-wsl.sh")

        self.assertEqual(result.returncode, 1)
        self.assertIn("Missing canonical credential link: profile.cert", result.stderr)
        self.assertEqual(self.log_path.read_text(), "")
        self.assertFalse(self.state_file.exists())

    def test_start_rejects_profile_links_outside_canonical_credentials(self) -> None:
        self.prepare_profile_links()
        (self.server_root / "profile.key").unlink()
        external_fixture = self.root / "outside-profile.key"
        external_fixture.write_text("non-credential test fixture\n", encoding="utf-8")
        (self.server_root / "profile.key").symlink_to(external_fixture)

        result = self.run_control("start-mochirii-wsl.sh")

        self.assertEqual(result.returncode, 1)
        self.assertIn("Missing canonical credential link: profile.key", result.stderr)
        self.assertEqual(self.log_path.read_text(), "")

    def test_start_publishes_state_only_with_all_six_manual_services(self) -> None:
        self.prepare_profile_links()

        result = self.run_control("start-mochirii-wsl.sh")

        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state_path.read_text())
        for active, enabled, pid in state.values():
            self.assertEqual((active, enabled), ("active", "disabled"))
            self.assertGreater(pid, 0)
        published = json.loads(self.state_file.read_text())
        self.assertEqual(set(published["services"]), set(XI_SERVICES))
        self.assertFalse(self.defaults_path.exists())

    def test_partial_start_rolls_back_profile_and_all_other_services(self) -> None:
        self.prepare_profile_links()

        result = self.run_control(
            "start-mochirii-wsl.sh", fail=("start", "mochirii-xi-map.service")
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("stopping the partial start", result.stderr)
        state = json.loads(self.state_path.read_text())
        self.assertEqual(
            state,
            {
                service: list(value)
                for service, value in WslServerStatusTests.stopped_state().items()
            },
        )
        self.assertFalse(self.state_file.exists())
        self.assertNotIn("Mochirii XI server is up.", result.stdout)
        self.assertFalse(self.defaults_path.exists())

    def test_full_stop_continues_after_individual_service_failure(self) -> None:
        self.write_state(WslServerStatusTests.running_state())
        self.state_file.parent.mkdir()
        self.state_file.write_text("{}\n", encoding="utf-8")

        result = self.run_control(
            "stop-mochirii-wsl.sh",
            "--stop-db",
            fail=("stop", "mochirii-xi-map.service"),
        )

        self.assertEqual(result.returncode, 1)
        calls = self.log_path.read_text()
        for service in SERVICES:
            self.assertIn(f"stop {service}\n", calls)
        state = json.loads(self.state_path.read_text())
        self.assertEqual(
            state["mochirii-xi-profile.service"], ["inactive", "disabled", 0]
        )
        self.assertEqual(state["mariadb.service"], ["inactive", "disabled", 0])
        self.assertTrue(self.state_file.exists())
        self.assertNotIn("Mochirii XI server stopped.", result.stdout)

    def test_developer_stop_includes_profile_and_preserves_manual_database(
        self,
    ) -> None:
        self.write_state(WslServerStatusTests.running_state())

        result = self.run_control("stop-mochirii-wsl.sh")

        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state_path.read_text())
        for service in XI_SERVICES:
            self.assertEqual(state[service], ["inactive", "disabled", 0])
        self.assertEqual(state["mariadb.service"], ["active", "disabled", 1000])


if __name__ == "__main__":
    unittest.main()
