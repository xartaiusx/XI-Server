"""Synthetic controls only: no real credential, DB, service, or client access."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools import mysql_client as client
from tools.mochirii.tests import test_wsl_server_status as status_tests

PUBLIC_OPTIONS = (
    b'[client]\nhost="127.0.0.1"\nport=3306\n'
    b'user="public-fixture"\npassword="public-fixture-only"\n'
)


@unittest.skipUnless(sys.platform.startswith("linux"), "Canonical Linux controls")
class PrivateSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="mysql-control-public-fixture-"
        )
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "client.cnf"
        self.connection = {
            "host": "127.0.0.1",
            "user": "public-fixture",
            "port": 3306,
            "password": "public-fixture-only",
        }
        self.path.write_bytes(PUBLIC_OPTIONS)
        self.path.chmod(0o600)

    def test_actual_private_source_fd_closes_on_return_and_parse_failure(self):
        native_open, native_close = os.open, os.close
        for outcome in ("normal", "parse_failure"):
            opened, closed = [], []

            def observed_open(*args, **kwargs):
                fd = native_open(*args, **kwargs)
                opened.append(fd)
                return fd

            def observed_close(fd):
                closed.append(fd)
                native_close(fd)

            with self.subTest(outcome=outcome), patch.object(
                os, "open", observed_open
            ), patch.object(os, "close", observed_close):
                if outcome == "parse_failure":
                    with patch.object(
                        client,
                        "_parse_client_options",
                        side_effect=client.MySQLClientError("public-parse-stop"),
                    ), self.assertRaises(client.MySQLClientError):
                        client._read_private_linux_options(str(self.path))
                else:
                    self.assertEqual(
                        client._read_private_linux_options(str(self.path)),
                        self.connection,
                    )
            self.assertEqual(len(opened), 1)
            self.assertEqual(closed, opened)
            with self.assertRaises(OSError):
                os.fstat(opened[0])

    def test_private_source_preflight_never_launches_or_creates_copy(self):
        with patch.object(client.subprocess, "run") as run:
            self.assertEqual(
                client.main(["--credential-file", str(self.path), "--check"]), 0
            )
            run.assert_not_called()
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_source_native_call_uses_anonymous_options_and_preserves_original(self):
        before = self.path.read_bytes()
        captured = []

        def run(arguments, **kwargs):
            captured.extend(kwargs["pass_fds"])
            self.assertEqual(os.read(captured[0], 20000), before)
            self.assertEqual(arguments[2:], ["xidb", "-e", "SELECT 1"])
            self.assertIsNone(kwargs["stdout"])
            return subprocess.CompletedProcess(arguments, 0, None, "")

        with patch.object(client.subprocess, "run", run):
            result = client.main(
                [
                    "--credential-file",
                    str(self.path),
                    "--",
                    "mariadb",
                    "xidb",
                    "-e",
                    "SELECT 1",
                ]
            )
        self.assertEqual(result, 0)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])
        with self.assertRaises(OSError):
            os.fstat(captured[0])

    def test_includes_sections_duplicate_keys_remote_host_and_public_modes_reject(self):
        valid = self.path.read_bytes()
        for content, mode in (
            (valid + b"!include forbidden.cnf\n", 0o600),
            (valid + b"[mysqld]\n", 0o600),
            (valid + b"user=duplicate\n", 0o600),
            (valid.replace(b"127.0.0.1", b"remote.invalid"), 0o600),
            (valid, 0o644),
            (b"x" * 16385, 0o600),
        ):
            self.path.write_bytes(content)
            self.path.chmod(mode)
            with self.subTest(size=len(content), mode=mode), patch.object(
                client.subprocess, "run"
            ) as run, patch("builtins.print"):
                self.assertEqual(
                    client.main(["--credential-file", str(self.path), "--check"]), 1
                )
                run.assert_not_called()

    def test_connection_overrides_and_unreviewed_executables_reject(self):
        for arguments in (
            ["bash"],
            ["mysqldump", "xidb"],
            ["mariadb", "-ppublic"],
            ["mariadb", "--defaults-extra-file=/tmp/other"],
            ["mariadb", "--print-defaults"],
            ["mariadb", "--host=remote"],
            ["mariadb", "--help"],
            ["mariadb", "--hel"],
            ["mariadb", "--verbo"],
            ["mariadb", "--deb"],
            ["mariadb", "--print-def"],
            ["mariadb", "--unknown-option"],
            ["mariadb", "-e", "SELECT\0 1"],
            ["mariadb", "--verbose"],
            ["mariadb", "--debug=d:t:o,debug.log"],
            ["mariadb", "-?"],
            ["mariadb", "-I"],
            ["mariadb", "-vvv"],
        ):
            with self.subTest(arguments=arguments), patch.object(
                client.subprocess, "run"
            ) as run, patch("builtins.print"):
                self.assertEqual(
                    client.main(
                        ["--credential-file", str(self.path), "--", *arguments]
                    ),
                    1,
                )
                run.assert_not_called()

    def test_canonical_acl_failure_prevents_source_open(self):
        with patch.object(
            client,
            "_check_canonical_windows_acl",
            side_effect=client.MySQLClientError("synthetic ACL failure"),
        ), patch.object(os, "open") as opener, self.assertRaises(
            client.MySQLClientError
        ):
            client._read_private_linux_options(client.CANONICAL_CNF)
        opener.assert_not_called()

    def test_quoted_source_round_trip_and_ambiguous_escapes_reject(self):
        connection = self.connection | {"password": 'public-"quoted\\password\nonly'}
        self.assertEqual(
            client._parse_client_options(client.serialize_options(**connection)),
            connection,
        )
        for password in (b'"unterminated', b'"inner"quote"', b'"unknown\\q"'):
            content = b'[client]\nuser="public"\npassword=' + password + b"\n"
            with self.subTest(size=len(password)), self.assertRaises(
                client.MySQLClientError
            ):
                client._parse_client_options(content)

    def test_metadata_gate_is_static_bounded_and_does_not_read_values(self):
        with patch.object(
            client.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0, b"private", b""),
        ) as run:
            client._check_canonical_windows_acl()
        args, kwargs = run.call_args
        command = args[0]
        self.assertEqual(
            command[:3],
            [
                "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
                "-NoProfile",
                "-NonInteractive",
            ],
        )
        self.assertEqual(kwargs["timeout"], 30)
        self.assertIn("Get-Acl -LiteralPath $path", command[-1])
        self.assertNotIn("Get-Content", command[-1])
        self.assertNotIn("ReadAll", command[-1])
        self.assertIn("DiscretionaryAcl", command[-1])


@unittest.skipUnless(sys.platform.startswith("linux"), "Fake Linux service controls")
class CredentialControlLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.fixture = status_tests.WslServerLifecycleTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.calls = self.fixture.root / "native-client-calls.log"
        self.calls.write_text("", encoding="utf-8")
        self.helper_status = self.fixture.root / "helper-status"
        self.helper_status.write_text("0", encoding="utf-8")
        self.fixture.write_executable(
            self.fixture.script_root / "prepare-mariadb-client-config.sh",
            f"""#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> '{self.calls}'
result="$(cat '{self.helper_status}')"
if [[ "$result" != "0" ]]; then exit "$result"; fi
if [[ "${{1:-}}" == "--check" ]]; then exit 0; fi
[[ "${{1:-}}" == "--" ]] || exit 2
shift
exec "$@"
""",
        )
        source = (status_tests.STATUS_SCRIPT.parent / "open-mariadb-wsl.sh").read_text(
            encoding="utf-8"
        )
        self.fixture.write_executable(
            self.fixture.script_root / "open-mariadb-wsl.sh", source
        )

    def test_start_preflights_before_service_changes_and_never_deletes_source(self):
        self.fixture.prepare_profile_links()
        self.helper_status.write_text("1", encoding="utf-8")
        result = self.fixture.run_control("start-mochirii-wsl.sh")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.fixture.log_path.read_text(), "")
        self.assertTrue(self.fixture.defaults_path.exists())
        self.assertEqual(self.calls.read_text(), "--check\n")

    def test_full_start_uses_wrapper_without_connection_overrides(self):
        self.fixture.prepare_profile_links()
        result = self.fixture.run_control("start-mochirii-wsl.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertTrue(calls.startswith("--check\n"))
        self.assertIn("-- mariadb -e SELECT 1;", calls)
        self.assertNotIn("defaults", calls)
        self.assertNotIn("-h", calls)
        self.assertNotIn("-P", calls)
        self.assertTrue(self.fixture.defaults_path.exists())

    def test_db_only_start_requires_all_xi_off_and_manual_disabled(self):
        result = self.fixture.run_control("open-mariadb-wsl.sh", "--start-db-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.fixture.state_path.read_text())
        self.assertEqual(state["mariadb.service"][:2], ["active", "disabled"])
        for name, values in state.items():
            if name != "mariadb.service":
                self.assertEqual(values, ["inactive", "disabled", 0])
        self.assertNotIn("-- mariadb xidb", self.calls.read_text())
        self.assertTrue(self.fixture.defaults_path.exists())

    def test_db_only_refuses_active_xi_and_rolls_back_failed_disable(self):
        state = status_tests.WslServerStatusTests.stopped_state()
        state["mochirii-xi-map.service"] = ("active", "disabled", 99)
        self.fixture.write_state(state)
        result = self.fixture.run_control("open-mariadb-wsl.sh", "--start-db-only")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("start mariadb.service", self.fixture.log_path.read_text())
        self.fixture.write_state(status_tests.WslServerStatusTests.stopped_state())
        result = self.fixture.run_control(
            "open-mariadb-wsl.sh",
            "--start-db-only",
            fail=("disable", "mariadb.service"),
        )
        self.assertEqual(result.returncode, 1)
        state = json.loads(self.fixture.state_path.read_text())
        self.assertEqual(state["mariadb.service"], ["inactive", "disabled", 0])


if __name__ == "__main__":
    unittest.main()
