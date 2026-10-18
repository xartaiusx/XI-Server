from __future__ import annotations

import ast
import importlib
import ntpath
import os
from pathlib import Path
import re
import runpy
import socket
import struct
import subprocess
import sys
import traceback
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, call, mock_open, patch

import cbor2

REPO_ROOT = Path(__file__).resolve().parents[3]
util = importlib.import_module("tools.headlessxi.util").util


def source_tree(relative_path: str) -> ast.Module:
    path = REPO_ROOT / relative_path
    return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def load_functions(
    relative_path: str, names: tuple[str, ...], namespace: dict | None = None
) -> dict:
    """Load only pure definitions, never a tool's top-level DB/network setup."""
    definitions = [
        node
        for node in source_tree(relative_path).body
        if isinstance(node, ast.FunctionDef) and node.name in names
    ]
    if {node.name for node in definitions} != set(names):
        raise AssertionError("Expected source functions were not found")
    result = dict(namespace or {})
    module = ast.Module(body=definitions, type_ignores=[])
    exec(compile(module, str(REPO_ROOT / relative_path), "exec"), result)
    return result


class FakeDatabaseError(Exception):
    def __init__(self, errno: int = 1) -> None:
        super().__init__("synthetic database failure")
        self.errno = errno


class LicenseHeaderTests(unittest.TestCase):
    def run_check(self, valid: bool) -> tuple[int, Mock]:
        header = Mock(return_value=valid)
        namespace = load_functions(
            "tools/ci/sanity_checks/detect_license_headers.py",
            ("main",),
            {
                "os": SimpleNamespace(
                    walk=Mock(return_value=[("src", [], ["sample.cpp", "notes.md"])]),
                    path=os.path,
                ),
                "check_header": header,
                "print": Mock(),
            },
        )
        return namespace["main"](), header

    def test_invalid_license_returns_failure(self) -> None:
        result, header = self.run_check(False)
        self.assertEqual(result, 1)
        header.assert_called_once_with(os.path.join("src", "sample.cpp"))

    def test_valid_license_returns_success(self) -> None:
        result, header = self.run_check(True)
        self.assertEqual(result, 0)
        header.assert_called_once()


class AnnouncementTests(unittest.TestCase):
    def test_import_has_no_output_or_messaging_side_effects(self) -> None:
        with patch("zmq.Context") as context, patch("builtins.print") as output:
            runpy.run_path(
                str(REPO_ROOT / "tools/announce.py"), run_name="audit_import"
            )
        context.assert_not_called()
        output.assert_not_called()

    def announcement(self) -> tuple[dict, MagicMock, MagicMock, MagicMock]:
        factory = MagicMock()
        context = factory.return_value.__enter__.return_value
        channel = context.socket.return_value.__enter__.return_value
        namespace = load_functions(
            "tools/announce.py",
            ("build_chat_packet", "send_server_message"),
            {
                "socket": socket,
                "struct": struct,
                "cbor2": cbor2,
                "zmq": SimpleNamespace(
                    Context=factory,
                    DEALER=5,
                    ROUTING_ID=6,
                    IMMEDIATE=7,
                    SNDTIMEO=8,
                    LINGER=9,
                ),
                "print": Mock(),
            },
        )
        return namespace, factory, context, channel

    def test_explicit_send_preserves_endpoint_identity_and_packet(self) -> None:
        namespace, factory, context, channel = self.announcement()
        namespace["send_server_message"]("synthetic announcement")
        context.socket.assert_called_once_with(5)
        channel.connect.assert_called_once_with("tcp://127.0.0.1:54003")
        expected_identity = struct.pack(
            "!Q", struct.unpack("!I", socket.inet_aton("127.0.0.1"))[0] | (54003 << 32)
        )
        self.assertEqual(
            channel.setsockopt.call_args_list,
            [call(7, 1), call(8, 5000), call(9, 1000), call(6, expected_identity)],
        )
        packet = channel.send.call_args.args[0]
        self.assertEqual(packet[0], 12)
        self.assertEqual(
            cbor2.loads(packet[1:]),
            {
                "senderId": 0,
                "senderName": "",
                "message": "synthetic announcement",
                "zoneId": 0,
                "gmLevel": 1,
                "messageType": 6,
                "skipSender": False,
            },
        )
        context.socket.return_value.__exit__.assert_called_once()
        factory.return_value.__exit__.assert_called_once()

    def test_send_failure_propagates_and_closes_owned_resources(self) -> None:
        namespace, factory, context, channel = self.announcement()
        channel.send.side_effect = RuntimeError("synthetic send failure")
        with self.assertRaisesRegex(RuntimeError, "^synthetic send failure$"):
            namespace["send_server_message"]("synthetic announcement")
        context.socket.return_value.__exit__.assert_called_once()
        factory.return_value.__exit__.assert_called_once()


class SettingsReadTests(unittest.TestCase):
    def settings(
        self, opener: Mock, optional_exists: bool = False, path_module=os.path
    ) -> dict:
        default_file = path_module.normpath("/synthetic/settings/default/network.lua")
        path = SimpleNamespace(
            exists=lambda name: name == default_file or optional_exists,
            isfile=lambda name: name == default_file,
            join=path_module.join,
            sep=path_module.sep,
        )
        return load_functions(
            "tools/dbtool.py",
            ("populate_settings",),
            {
                "os": SimpleNamespace(
                    path=path,
                    sep=path_module.sep,
                    listdir=Mock(side_effect=[["network.lua"], ["optional.lua"]]),
                ),
                "from_server_path": lambda value: path_module.normpath(
                    f"/synthetic/{value}"
                ),
                "open": opener,
                "print_red": Mock(),
                "print": Mock(),
            },
        )

    def test_valid_settings_preserve_values_and_skip_optional_files(self) -> None:
        opener = mock_open(read_data="OPTION = 'a=b', -- comment\n-- DISABLED = 'no'\n")
        settings, defaults = self.settings(opener)["populate_settings"]()
        self.assertEqual(settings, {"network": {"OPTION": "a=b"}})
        self.assertEqual(defaults, settings)
        self.assertEqual(opener.call_count, 2)

    def test_existing_optional_directories_are_skipped(self) -> None:
        opener = mock_open(read_data="OPTION = 'value'\n")
        settings, defaults = self.settings(opener, optional_exists=True)[
            "populate_settings"
        ]()
        self.assertEqual(settings, {"network": {"OPTION": "value"}})
        self.assertEqual(defaults, settings)
        self.assertEqual(opener.call_count, 2)

    def test_windows_settings_paths_keep_the_same_filename_keys(self) -> None:
        opener = mock_open(read_data="OPTION = 'value'\n")
        settings, defaults = self.settings(opener, path_module=ntpath)[
            "populate_settings"
        ]()
        self.assertEqual(settings, {"network": {"OPTION": "value"}})
        self.assertEqual(defaults, settings)

    def test_read_failure_stops_before_database_action_without_leaking_values(
        self,
    ) -> None:
        private_value = "synthetic-private-settings-value"
        opener = Mock(side_effect=OSError(private_value))
        database_action = Mock()
        namespace = self.settings(opener)
        with self.assertRaisesRegex(
            RuntimeError, "^Error fetching settings\\.$"
        ) as error:
            namespace["populate_settings"]()
            database_action()
        database_action.assert_not_called()
        self.assertTrue(error.exception.__suppress_context__)
        self.assertNotIn(
            private_value, "".join(traceback.format_exception(error.exception))
        )

    def test_decoding_failure_is_also_sanitized_and_fatal(self) -> None:
        opener = Mock(
            side_effect=UnicodeDecodeError("utf-8", b"\xff", 0, 1, "synthetic")
        )
        with self.assertRaisesRegex(RuntimeError, "^Error fetching settings\\.$"):
            self.settings(opener)["populate_settings"]()

    def test_process_interrupts_are_not_wrapped(self) -> None:
        for error in (KeyboardInterrupt(), SystemExit(7)):
            with self.subTest(exception=type(error).__name__):
                with self.assertRaises(type(error)):
                    self.settings(Mock(side_effect=error))["populate_settings"]()


class DatabaseToolTests(unittest.TestCase):
    def test_preflight_git_check_uses_devnull_without_opening_a_file(self) -> None:
        calls = [
            node
            for node in ast.walk(source_tree("tools/dbtool.py"))
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "subprocess"
            and node.func.attr == "call"
        ]
        outputs = [
            keyword.value
            for call in calls
            for keyword in call.keywords
            if keyword.arg == "stdout"
        ]
        self.assertTrue(
            any(
                isinstance(value, ast.Attribute)
                and isinstance(value.value, ast.Name)
                and value.value.id == "subprocess"
                and value.attr == "DEVNULL"
                for value in outputs
            )
        )
        self.assertFalse(any(isinstance(value, ast.Call) for value in outputs))

    def trigger_order(self, files: list[str]) -> list[str]:
        function = next(
            node
            for node in source_tree("tools/dbtool.py").body
            if isinstance(node, ast.FunctionDef) and node.name == "fetch_files"
        )
        start = next(
            index
            for index, node in enumerate(function.body)
            if isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name) and target.id == "triggers"
                for target in node.targets
            )
        )
        statements = function.body[start : start + 2]
        self.assertIsInstance(statements[1], ast.If)
        namespace = {
            "import_files": list(files),
            "from_server_path": lambda value: f"/synthetic/{value}",
        }
        exec(
            compile(
                ast.Module(body=statements, type_ignores=[]), "trigger-order", "exec"
            ),
            namespace,
        )
        return namespace["import_files"]

    def test_optional_trigger_file_absence_preserves_order(self) -> None:
        files = ["/synthetic/sql/a.sql", "/synthetic/sql/z.sql"]
        self.assertEqual(self.trigger_order(files), files)

    def test_present_trigger_file_is_imported_last(self) -> None:
        trigger = "/synthetic/sql/triggers.sql"
        files = [trigger, "/synthetic/sql/a.sql", "/synthetic/sql/z.sql"]
        self.assertEqual(self.trigger_order(files), files[1:] + [trigger])

    def connection(self, errno: int) -> dict:
        mariadb = SimpleNamespace(
            connect=Mock(side_effect=FakeDatabaseError(errno)),
            Error=FakeDatabaseError,
            constants=SimpleNamespace(
                ERR=SimpleNamespace(ER_ACCESS_DENIED_ERROR=1045, ER_BAD_DB_ERROR=1049)
            ),
        )
        return load_functions(
            "tools/dbtool.py",
            ("connect",),
            {
                "mariadb": mariadb,
                "host": "127.0.0.1",
                "login": "synthetic",
                "password": "synthetic",
                "database": "synthetic",
                "port": 1,
                "print_red": Mock(),
                "input": Mock(return_value="n"),
                "sys": sys,
            },
        )

    def test_database_connection_errors_exit_unsuccessfully(self) -> None:
        for errno in (1045, 9999):
            with self.subTest(errno=errno), self.assertRaises(SystemExit) as error:
                self.connection(errno)["connect"]()
            self.assertEqual(error.exception.code, 1)

    def test_declining_database_creation_remains_a_clean_cancellation(self) -> None:
        with self.assertRaises(SystemExit) as error:
            self.connection(1049)["connect"]()
        self.assertEqual(error.exception.code, 0)

    def test_normal_close_preserves_success_and_closes_connection(self) -> None:
        database, cursor = Mock(), Mock()
        namespace = load_functions(
            "tools/dbtool.py",
            ("close",),
            {
                "db": database,
                "cur": cursor,
                "time": SimpleNamespace(sleep=Mock()),
                "sys": sys,
                "print": Mock(),
            },
        )
        with self.assertRaises(SystemExit) as error:
            namespace["close"]()
        self.assertEqual(error.exception.code, 0)
        cursor.close.assert_called_once()
        database.close.assert_called_once()


class FormatterProbeTests(unittest.TestCase):
    def probe(self, outcomes: list) -> tuple[dict, Mock]:
        runner = Mock(side_effect=outcomes)
        namespace = load_functions(
            "tools/run_clang_format.py",
            ("find_clang_format",),
            {
                "shutil": SimpleNamespace(which=lambda value: value),
                "os": SimpleNamespace(path=SimpleNamespace(isfile=lambda value: True)),
                "subprocess": SimpleNamespace(
                    run=runner, SubprocessError=subprocess.SubprocessError
                ),
                "sys": sys,
                "print": Mock(),
            },
        )
        return namespace, runner

    def test_expected_probe_failures_try_the_next_candidate(self) -> None:
        failures = [
            OSError("synthetic"),
            subprocess.TimeoutExpired("synthetic", 5),
            UnicodeDecodeError("utf-8", b"\xff", 0, 1, "synthetic"),
        ]
        for failure in failures:
            with self.subTest(exception=type(failure).__name__):
                namespace, runner = self.probe(
                    [
                        failure,
                        SimpleNamespace(
                            returncode=0, stdout="clang-format version 22.1.8"
                        ),
                    ]
                )
                self.assertEqual(
                    namespace["find_clang_format"](), "/usr/bin/clang-format-22"
                )
                self.assertEqual(runner.call_count, 2)

    def test_interrupts_and_process_exits_propagate_immediately(self) -> None:
        for failure in (KeyboardInterrupt(), SystemExit(7)):
            with self.subTest(exception=type(failure).__name__):
                namespace, runner = self.probe([failure])
                with self.assertRaises(type(failure)):
                    namespace["find_clang_format"]()
                runner.assert_called_once()


class BinaryCopyTests(unittest.TestCase):
    def test_binary_offsets_remain_unchanged(self) -> None:
        destination = bytearray(b"........")
        util.memcpy(b"abcdef", 2, destination, 3, 2)
        self.assertEqual(destination, bytearray(b"...cd..."))

    def test_conversion_does_not_swallow_interrupts(self) -> None:
        with patch.object(util, "to_bytes", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                util.memcpy(b"abc", 0, bytearray(3), 0, 3)


class MigrationBoundaryTests(unittest.TestCase):
    migrations = (
        "007_extend_mission_log",
        "008_mission_blob_extra",
        "009_cop_mission_ids",
    )

    def migration(
        self, name: str, conversion=None
    ) -> tuple[dict, Mock, Mock, MagicMock]:
        cursor, database = Mock(), Mock()
        blob = bytearray(
            1050 if name.startswith("009") else 990 if name.startswith("008") else 930
        )
        blob[:] = bytes(index % 256 for index in range(len(blob)))
        blob[420:422] = (1).to_bytes(2, "little")
        cursor.fetchall.return_value = [(42,)]
        cursor.fetchone.return_value = (bytes(blob),)
        error_file = mock_open()
        namespace = {
            "cur": cursor,
            "mariadb": SimpleNamespace(Error=FakeDatabaseError),
            "open": error_file,
            "print": Mock(),
        }
        path = f"tools/migrations/{name}.py"
        if name.startswith("009"):
            namespace["mission_map"] = ast.literal_eval(
                next(
                    node.value
                    for node in source_tree(path).body
                    if isinstance(node, ast.Assign)
                )
            )
        if conversion is not None:
            namespace["bytearray"] = Mock(side_effect=conversion)
        return (
            load_functions(path, ("migrate",), namespace),
            cursor,
            database,
            error_file,
        )

    def test_existing_blob_transformations_and_commit_boundaries_are_preserved(
        self,
    ) -> None:
        for name in self.migrations:
            with self.subTest(migration=name):
                namespace, cursor, database, error_file = self.migration(name)
                namespace["migrate"](cursor, database)
                updates = [
                    call
                    for call in cursor.execute.call_args_list
                    if call.args[0].startswith("UPDATE chars SET missions")
                ]
                self.assertEqual(len(updates), 1)
                blob, charid = updates[0].args[1]
                original = cursor.fetchone.return_value[0]
                self.assertEqual(charid, 42)
                self.assertEqual(len(blob), 990 if name.startswith("007") else 1050)
                if name.startswith("007"):
                    expected = original + bytes(60)
                elif name.startswith("008"):
                    expected = b"".join(
                        original[offset : offset + 2]
                        + bytes(4)
                        + original[offset + 2 : offset + 66]
                        for offset in range(0, 990, 66)
                    )
                else:
                    expected = (
                        original[:420] + (110).to_bytes(2, "little") + original[422:]
                    )
                self.assertEqual(blob, expected)
                self.assertEqual(database.commit.call_count, 2)
                error_file().write.assert_not_called()

    def test_control_interrupts_do_not_commit_or_become_row_errors(self) -> None:
        for name in self.migrations:
            for failure in (KeyboardInterrupt(), SystemExit(7)):
                with self.subTest(migration=name, exception=type(failure).__name__):
                    namespace, cursor, database, error_file = self.migration(
                        name, failure
                    )
                    with self.assertRaises(type(failure)):
                        namespace["migrate"](cursor, database)
                    database.commit.assert_not_called()
                    error_file().write.assert_not_called()

    def test_malformed_rows_keep_existing_sanitized_error_handling(self) -> None:
        for name in self.migrations:
            with self.subTest(migration=name):
                namespace, cursor, database, error_file = self.migration(
                    name, ValueError("synthetic-private-blob")
                )
                namespace["migrate"](cursor, database)
                self.assertEqual(database.commit.call_count, 1)
                error_file().write.assert_called_once()
                self.assertNotIn(
                    "synthetic-private-blob", error_file().write.call_args.args[0]
                )


class StartupFailureTests(unittest.TestCase):
    def setup(self, failure: BaseException | None = None) -> tuple[dict, Mock]:
        cursor, database = Mock(), Mock()
        if failure is not None:
            cursor.execute.side_effect = failure
        namespace = load_functions(
            "tools/ci/startup_checks.py",
            ("setup_test_character",),
            {
                "cur": cursor,
                "db": database,
                "mariadb": SimpleNamespace(Error=FakeDatabaseError),
                "print": Mock(),
            },
        )
        return namespace, database

    def test_database_error_is_reported_without_success_commit(self) -> None:
        namespace, database = self.setup(FakeDatabaseError())
        self.assertEqual(namespace["setup_test_character"](), -1)
        database.commit.assert_not_called()

    def test_successful_setup_keeps_its_single_commit(self) -> None:
        namespace, database = self.setup()
        self.assertEqual(namespace["setup_test_character"](), 0)
        database.commit.assert_called_once()

    def test_interrupts_are_not_converted_to_database_errors(self) -> None:
        for failure in (KeyboardInterrupt(), SystemExit(7)):
            with self.subTest(exception=type(failure).__name__):
                namespace, database = self.setup(failure)
                with self.assertRaises(type(failure)):
                    namespace["setup_test_character"]()
                database.commit.assert_not_called()


class ChangelogAndTypeTests(unittest.TestCase):
    def test_real_name_filter_is_preserved_and_idempotent(self) -> None:
        namespace = load_functions(
            "tools/generate_changelog.py", ("is_real_name", "remove_real_names")
        )
        authors = {"Jane Doe", "xartaiusx", "someone"}
        namespace["remove_real_names"](authors)
        namespace["remove_real_names"](authors)
        self.assertEqual(authors, {"xartaiusx", "someone"})

    def test_supported_types_and_explicit_unknown_fallback(self) -> None:
        namespace = load_functions(
            "tools/ci/generate_spec_file.py", ("cpp_type_to_lua_type",)
        )
        expected = {
            "uint8": "number",
            "std::string": "string",
            "std::vector<uint8>": "table",
            "std::vector<std::vector<std::vector<uint8>>>": "table",
            "unsupported": None,
        }
        for source, result in expected.items():
            with self.subTest(source=source):
                self.assertEqual(namespace["cpp_type_to_lua_type"](source), result)

    def test_automatic_commit_message_rejection_contract_is_unchanged(self) -> None:
        rule = next(
            node
            for node in ast.walk(source_tree("tools/ci/sanity_checks/git.py"))
            if isinstance(node, ast.If)
            and isinstance(node.test, ast.Call)
            and isinstance(node.test.func, ast.Attribute)
            and node.test.func.attr == "search"
            and node.test.args
            and isinstance(node.test.args[0], ast.Constant)
            and node.test.args[0].value == r"^update [^ ]*\.[a-z]{1,3}$"
        )
        for title, rejected in (
            ("Update sample.lua", True),
            ("update notes.md", True),
            ("Update server behavior", False),
            ("update notes.long", False),
        ):
            with self.subTest(title=title):
                output = Mock()
                namespace = {
                    "re": re,
                    "line": title,
                    "hash": "synthetic",
                    "lines": [title],
                    "print_error": output,
                }
                exec(
                    compile(
                        ast.Module(body=[rule], type_ignores=[]), "commit-rule", "exec"
                    ),
                    namespace,
                )
                self.assertEqual(output.call_count, int(rejected))

    def test_interactive_exit_aliases_are_not_used_by_owned_tools(self) -> None:
        files = (
            "tools/dbtool.py",
            "tools/bom_checker.py",
            "tools/headlessxi/hxiclient.py",
            "tools/ci/lua_lang_server.py",
            "tools/ci/generate_spec_file.py",
        )
        for relative_path in files:
            with self.subTest(path=relative_path):
                aliases = [
                    node
                    for node in ast.walk(source_tree(relative_path))
                    if isinstance(node, ast.Call)
                    and isinstance(node.func, ast.Name)
                    and node.func.id in {"exit", "quit"}
                ]
                self.assertEqual(aliases, [])


if __name__ == "__main__":
    unittest.main()
