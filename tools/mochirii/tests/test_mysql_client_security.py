"""Synthetic-only native-client transport and mutation-preflight regressions."""

import ast
import ctypes
import errno
import fileinput
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import traceback
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, mock_open, patch

import yaml

from tools import mysql_client as client

REPO_ROOT = Path(__file__).resolve().parents[3]
CONNECTION = {
    "host": "synthetic-host",
    "user": "synthetic-user",
    "port": 33307,
    "password": 'synthetic-"pass\\word\nwith\ttab',
}


def load_dbtool(*names, **namespace):
    tree = ast.parse((REPO_ROOT / "tools/dbtool.py").read_text(encoding="utf-8"))
    definitions = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name in names
    ]
    if {node.name for node in definitions} != set(names):
        raise AssertionError("Required definitions missing")
    result = dict(namespace)
    exec(
        compile(
            ast.Module(body=definitions, type_ignores=[]), "synthetic-dbtool", "exec"
        ),
        result,
    )
    return result


class SerializationTests(unittest.TestCase):
    def test_exact_options_and_escaping(self):
        content = client.serialize_options(**CONNECTION)
        self.assertEqual(
            content,
            b'[client]\nhost="synthetic-host"\nport=33307\n'
            b'user="synthetic-user"\npassword="synthetic-\\"pass\\\\word\\nwith\\ttab"\n',
        )

    def test_invalid_fields_and_ports_are_rejected_without_values(self):
        for change in (
            {"password": "\0"},
            {"host": ""},
            {"user": ""},
            {"password": "x" * 4097},
            {"port": True},
            {"port": 0},
            {"port": 65536},
            {"port": "3306"},
        ):
            with self.subTest(change=list(change)), self.assertRaises(
                client.MySQLClientError
            ):
                client.serialize_options(**(CONNECTION | change))

    def test_environment_removes_connection_and_password_inputs(self):
        environment = {
            "PATH": "synthetic-safe",
            "XI_NETWORK_SQL_HOST": "host",
            "XI_NETWORK_SQL_PORT": "port",
            "XI_NETWORK_SQL_LOGIN": "user",
            "XI_NETWORK_SQL_PASSWORD": "pass",
            "MYSQL_PWD": "pass",
            "MARIADB_PWD": "pass",
            "OTHER_PASSWORD": "pass",
        }
        with patch.dict(os.environ, environment, clear=True):
            self.assertEqual(client._child_environment(), {"PATH": "synthetic-safe"})


class TransportTests(unittest.TestCase):
    def test_argument_nul_stops_before_serialization_or_subprocess(self):
        with patch.object(client, "serialize_options") as serialize, patch.object(
            client.subprocess, "run"
        ) as run, self.assertRaises(client.MySQLClientError):
            client.run_mysql("mysql", ["-e", "SELECT\0 1"], **CONNECTION)
        serialize.assert_not_called()
        run.assert_not_called()

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux memfd contract")
    def test_subprocess_contract_and_descriptor_cleanup(self):
        captured = {}

        def run(arguments, **kwargs):
            captured.update(arguments=arguments, kwargs=kwargs)
            fd = kwargs["pass_fds"][0]
            captured["fd"] = fd
            self.assertEqual(stat.S_IMODE(os.fstat(fd).st_mode), 0o600)
            self.assertFalse(os.get_inheritable(fd))
            self.assertEqual(os.read(fd, 20000), client.serialize_options(**CONNECTION))
            return subprocess.CompletedProcess(arguments, 0, "safe result", "")

        with patch.object(sys, "platform", "linux"), patch.object(
            client.subprocess, "run", run
        ):
            result = client.run_mysql("mysql", ["xidb", "-e", "SELECT 1"], **CONNECTION)
        self.assertEqual(result.stdout, "safe result")
        args = captured["arguments"]
        self.assertTrue(args[1].startswith("--defaults-file=/proc/self/fd/"))
        self.assertEqual(args[2:], ["xidb", "-e", "SELECT 1"])
        self.assertNotIn(CONNECTION["host"], str(args))
        self.assertNotIn(CONNECTION["user"], str(args))
        self.assertNotIn(CONNECTION["password"], str(args))
        self.assertEqual(captured["kwargs"]["timeout"], 600)
        with self.assertRaises(OSError):
            os.fstat(captured["fd"])

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux memfd execution")
    def test_actual_inherited_descriptor_is_readable_only_in_child(self):
        # The surrogate accepts MariaDB's first option, never connects to a DB,
        # and returns only synthetic equality/permission/environment booleans.
        program = (
            "import json,os,stat,sys; "
            "p=sys.argv[1].split('=',1)[1]; "
            "f=os.open(p,os.O_RDONLY); b=os.read(f,20000); "
            "print(json.dumps({'valid':b.startswith(b'[client]\\n'),"
            "'private':stat.S_IMODE(os.fstat(f).st_mode)==384,"
            "'password_env':'XI_NETWORK_SQL_PASSWORD' in os.environ})); os.close(f)"
        )
        actual_run = subprocess.run

        def surrogate(arguments, **kwargs):
            return actual_run([sys.executable, "-c", program, *arguments[1:]], **kwargs)

        with patch.object(client.subprocess, "run", surrogate), patch.dict(
            os.environ, {"XI_NETWORK_SQL_PASSWORD": "synthetic-env-password"}
        ):
            result = client.run_mysql(
                "synthetic-client", ["-e", "SELECT 1"], **CONNECTION
            )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            json.loads(result.stdout),
            {"valid": True, "private": True, "password_env": False},
        )

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux memfd contract")
    def test_failures_and_timeouts_are_redacted_and_close_descriptor(self):
        for failure in (
            OSError("synthetic-secret"),
            subprocess.TimeoutExpired(["synthetic-secret"], 1),
            subprocess.CompletedProcess(
                ["mysql"], 8, "synthetic-secret", "synthetic-secret"
            ),
        ):
            captured = []

            def run(arguments, **kwargs):
                captured.extend(kwargs["pass_fds"])
                if isinstance(failure, Exception):
                    raise failure
                return failure

            with self.subTest(kind=type(failure).__name__), patch.object(
                sys, "platform", "linux"
            ), patch.object(client.subprocess, "run", run):
                if isinstance(failure, Exception):
                    with self.assertRaises(client.MySQLClientError) as error:
                        client.run_mysql("mysql", [], **CONNECTION)
                    self.assertNotIn(
                        "synthetic-secret",
                        "".join(traceback.format_exception(error.exception)),
                    )
                else:
                    result = client.run_mysql("mysql", [], **CONNECTION)
                    self.assertEqual(result.returncode, 8)
                    self.assertEqual(result.stdout, "")
                    self.assertNotIn("synthetic-secret", result.stderr)
            with self.assertRaises(OSError):
                os.fstat(captured[0])

    def test_missing_transport_and_invalid_timeout_do_not_launch(self):
        with patch.object(client.subprocess, "run") as run:
            for platform in ("win32", "darwin", "freebsd"):
                with self.subTest(platform=platform), patch.object(
                    sys, "platform", platform
                ), patch.dict(os.environ, {}, clear=True), self.assertRaises(
                    client.MySQLClientError
                ):
                    client.run_mysql("mysql", [], **CONNECTION)
            for timeout in (0, -1, True, float("inf"), 3601):
                with self.subTest(timeout=timeout), self.assertRaises(
                    client.MySQLClientError
                ):
                    client.run_mysql("mysql", [], timeout=timeout, **CONNECTION)
            with patch.object(sys, "platform", "linux"), patch.object(
                client.os, "memfd_create", None, create=True
            ), self.assertRaises(client.MySQLClientError):
                client.run_mysql("mysql", [], **CONNECTION)
            run.assert_not_called()

    @unittest.skipUnless(
        sys.platform in ("win32", "darwin"), "Native existing-file transport"
    )
    def test_native_private_ci_fixture_and_parent_permissions(self):
        path = os.environ.get(client.OPTIONS_FILE_ENV)
        if not path:
            self.skipTest(
                "Public CI fixture is not prepared; no workstation file is read"
            )
        connection = {
            "host": "127.0.0.1",
            "user": "xiadmin",
            "port": 3306,
            "password": "password",
        }

        def run(arguments, **kwargs):
            if arguments[0].endswith("powershell.exe"):
                return actual_run(arguments, **kwargs)
            self.assertEqual(arguments[1], f"--defaults-file={path}")
            self.assertNotIn("pass_fds", kwargs)
            return subprocess.CompletedProcess(
                arguments, 0, "native-private-fixture-pass", ""
            )

        actual_run = subprocess.run
        with patch.object(client.subprocess, "run", run):
            result = client.run_mysql("mysql", ["-e", "SELECT 1"], **connection)
        self.assertEqual(result.stdout, "native-private-fixture-pass")

    @unittest.skipUnless(sys.platform == "win32", "Native Windows DACL rejection")
    def test_native_windows_rejects_inherited_public_temp_directory(self):
        with tempfile.TemporaryDirectory(
            prefix="mysql-public-negative-fixture-"
        ) as root:
            path = Path(root) / "client.cnf"
            path.write_bytes(client.serialize_options(**CONNECTION))
            actual_run = subprocess.run
            with patch.object(
                client.subprocess, "run", wraps=actual_run
            ) as run, self.assertRaises(client.MySQLClientError):
                client.run_mysql("mysql", [], options_file=str(path), **CONNECTION)
            run.assert_called_once()
            executable = Path(run.call_args.args[0][0])
            self.assertTrue(executable.is_absolute())
            self.assertEqual(executable.name, "powershell.exe")

    @unittest.skipUnless(
        sys.platform == "darwin", "Native Darwin extended ACL rejection"
    )
    def test_native_darwin_rejects_extended_acl_on_public_fixture(self):
        with tempfile.TemporaryDirectory(
            prefix="mysql-public-acl-fixture-"
        ) as temporary:
            path = Path(temporary) / "client.cnf"
            path.write_bytes(client.serialize_options(**CONNECTION))
            path.chmod(0o600)
            subprocess.run(
                ["chmod", "+a", "everyone allow read", str(path)],
                check=True,
                capture_output=True,
                timeout=30,
            )
            with patch.object(client.subprocess, "run") as run, self.assertRaises(
                client.MySQLClientError
            ):
                client.run_mysql("mysql", [], options_file=str(path), **CONNECTION)
            run.assert_not_called()


class ExistingOptionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mysql-public-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.root.chmod(0o700)
        self.path = self.root / "client.cnf"
        self.path.write_bytes(client.serialize_options(**CONNECTION))
        self.path.chmod(0o600)

    @unittest.skipUnless(
        sys.platform.startswith("linux"),
        "Actual Linux fd cleanup; not native Darwin ACL proof",
    )
    def test_actual_existing_option_fds_close_reverse_order_on_all_exits(self):
        # Native Linux descriptors exercise both allocation branches; ACLs are mocked.
        native_open, native_close = os.open, os.close
        expected = self.path.read_bytes()
        for platform, outcome in (
            ("darwin", "normal"),
            ("darwin", "validation_failure"),
            ("darwin", "consumer_failure"),
            ("win32", "normal"),
            ("win32", "validation_failure"),
            ("win32", "consumer_failure"),
        ):
            opened, closed = [], []
            expected_count = 2 if platform == "darwin" else 1

            def observed_open(*args, **kwargs):
                fd = native_open(*args, **kwargs)
                opened.append(fd)
                return fd

            def observed_close(fd):
                closed.append(fd)
                native_close(fd)

            with self.subTest(platform=platform, outcome=outcome), patch.object(
                sys, "platform", platform
            ), patch.object(client, "_check_darwin_acl"), patch.object(
                client, "_check_windows_privacy"
            ), patch.object(
                os, "O_BINARY", 0, create=True
            ), patch.object(
                os, "open", observed_open
            ), patch.object(
                os, "close", observed_close
            ):
                if outcome == "validation_failure":
                    with self.assertRaises(client.MySQLClientError):
                        with client._existing_options(
                            str(self.path), b"mismatched-public-fixture"
                        ):
                            self.fail("invalid content reached consumer")
                elif outcome == "consumer_failure":
                    with self.assertRaisesRegex(RuntimeError, "^public-consumer-stop$"):
                        with client._existing_options(str(self.path), expected):
                            raise RuntimeError("public-consumer-stop")
                else:
                    with client._existing_options(str(self.path), expected):
                        self.assertEqual(len(opened), expected_count)
                        for fd in opened:
                            os.fstat(fd)
            self.assertEqual(len(opened), expected_count)
            self.assertEqual(closed, list(reversed(opened)))
            for fd in opened:
                with self.assertRaises(OSError):
                    os.fstat(fd)

    @unittest.skipIf(sys.platform == "win32", "POSIX fixture permission contract")
    def test_owner_only_file_acceptance_and_content_permissions_bounds(self):
        with patch.object(sys, "platform", "darwin"), patch.object(
            client, "_check_darwin_acl"
        ):
            with client._existing_options(
                str(self.path), self.path.read_bytes()
            ) as path:
                self.assertEqual(path, str(self.path))
            for data, mode in (
                (b"[client]\n!include other\n", 0o600),
                (b"", 0o600),
                (b"x" * 16385, 0o600),
                (b"wrong", 0o600),
                (client.serialize_options(**CONNECTION), 0o644),
                (client.serialize_options(**CONNECTION), 0o700),
            ):
                self.path.write_bytes(data)
                self.path.chmod(mode)
                with self.subTest(size=len(data), mode=mode), self.assertRaises(
                    client.MySQLClientError
                ):
                    with client._existing_options(
                        str(self.path), client.serialize_options(**CONNECTION)
                    ):
                        self.fail("invalid option file accepted")

    @unittest.skipIf(sys.platform == "win32", "POSIX fixture permission contract")
    def test_symlink_owner_and_parent_permissions_fail_closed(self):
        alias = self.root / "alias.cnf"
        alias.symlink_to(self.path)
        with patch.object(sys, "platform", "darwin"), patch.object(
            client, "_check_darwin_acl"
        ):
            with self.assertRaises(OSError):
                with client._existing_options(str(alias), self.path.read_bytes()):
                    self.fail("symlink accepted")
            self.root.chmod(0o755)
            with self.assertRaises(client.MySQLClientError):
                with client._existing_options(str(self.path), self.path.read_bytes()):
                    self.fail("public parent accepted")
            self.root.chmod(0o700)
            with patch.object(
                os, "geteuid", return_value=os.geteuid() + 1
            ), self.assertRaises(client.MySQLClientError):
                with client._existing_options(str(self.path), self.path.read_bytes()):
                    self.fail("foreign owner accepted")

    def test_unsupported_platform_and_relative_path_fail_closed(self):
        for path in ("client.cnf", str(self.path)):
            with patch.object(sys, "platform", "freebsd"), self.assertRaises(
                client.MySQLClientError
            ):
                with client._existing_options(path, b"unused"):
                    self.fail("unsupported path accepted")

    def test_darwin_empty_and_absent_acl_contract(self):
        library = SimpleNamespace(
            acl_get_fd_np=Mock(return_value=1),
            acl_get_entry=Mock(return_value=-1),
            acl_valid=Mock(return_value=0),
            acl_free=Mock(),
        )

        def entry(*_):
            ctypes.set_errno(errno.EINVAL)
            return -1

        library.acl_get_entry.side_effect = entry
        with patch.object(ctypes, "CDLL", return_value=library):
            client._check_darwin_acl(123)
            library.acl_free.assert_called_once_with(1)
            library.acl_get_entry.side_effect = None
            library.acl_get_entry.return_value = 0
            with self.assertRaises(client.MySQLClientError):
                client._check_darwin_acl(123)
            for error, accepted in (
                (errno.ENOENT, True),
                (errno.EIO, False),
                (0, False),
            ):

                def absent(*_, error=error):
                    ctypes.set_errno(error)
                    return None

                library.acl_get_fd_np.side_effect = absent
                if accepted:
                    client._check_darwin_acl(123)
                else:
                    with self.assertRaises(client.MySQLClientError):
                        client._check_darwin_acl(123)


class SourceExportBoundaryTests(unittest.TestCase):
    def setUp(self):
        tree = ast.parse((REPO_ROOT / "tools/dbtool.py").read_text(encoding="utf-8"))
        assignment = next(
            node
            for node in tree.body
            if isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name) and target.id == "player_data"
                for target in node.targets
            )
        )
        self.protected = ast.literal_eval(assignment.value)
        self.cursor = Mock()
        self.source_path = Mock(return_value="/synthetic/sql/public_fixture.sql")
        self.namespace = load_dbtool(
            "update_sql_from_db",
            "dump_table",
            "check_protected",
            os=os,
            re=re,
            player_data=self.protected,
            cur=self.cursor,
            from_server_path=self.source_path,
            MySQLClientError=client.MySQLClientError,
            print_green=Mock(),
            print_red=Mock(),
            input=Mock(),
            mariadb=SimpleNamespace(
                constants=SimpleNamespace(FIELD_TYPE=SimpleNamespace(FLOAT=4))
            ),
        )

    def test_every_actual_protected_table_and_case_variant_rejects_before_access(self):
        with patch("builtins.open") as opener:
            for filename in self.protected:
                for table in (filename[:-4], filename[:-4].upper()):
                    with self.subTest(table=table), self.assertRaises(
                        client.MySQLClientError
                    ):
                        self.namespace["dump_table"](table, True)
            opener.assert_not_called()
        self.cursor.execute.assert_not_called()
        self.cursor.fetchall.assert_not_called()
        self.source_path.assert_not_called()
        self.namespace["print_green"].assert_not_called()

    def test_runtime_schema_inventory_remains_in_central_protection_list(self):
        expected = {
            path.name
            for path in (REPO_ROOT / "sql").glob("*.sql")
            if path.name.startswith(("accounts", "audit_", "char_"))
            or path.name == "chars.sql"
        }
        self.assertTrue(expected)
        self.assertLessEqual(expected, set(self.protected))
        self.assertNotIn("fishing_zone.sql", self.protected)

    def test_missing_protected_tables_keep_existing_first_setup_import_path(self):
        self.cursor.fetchall.return_value = []
        self.namespace.update(
            database="public_fixture", import_protected=[], express_enabled=False
        )
        self.namespace["check_protected"]()
        self.assertEqual(self.source_path.call_count, len(self.protected))
        self.assertEqual(len(self.namespace["import_protected"]), len(self.protected))
        self.assertTrue(self.namespace["express_enabled"])
        query = self.cursor.execute.call_args.args[0]
        for table in (
            "accounts_parties",
            "accounts_sessions",
            "accounts_trust_tokens",
            "audit_chat",
            "audit_gm",
            "char_recast",
        ):
            self.assertIn("'" + table + "'", query)
        self.cursor.fetchall.return_value = [
            (filename[:-4],) for filename in self.protected
        ]
        self.namespace["express_enabled"] = False
        self.source_path.reset_mock()
        self.namespace["check_protected"]()
        self.assertEqual(self.namespace["import_protected"], [])
        self.assertFalse(self.namespace["express_enabled"])
        self.source_path.assert_not_called()

    def test_invalid_names_and_triggers_reject_before_source_or_cursor_access(self):
        for table in (
            None,
            7,
            [],
            "",
            "0table",
            "a" * 65,
            "../accounts",
            r"..\accounts",
            "abilities.sql",
            "abilities; DROP TABLE accounts",
            "`abilities`",
            "abilities --",
            "abilities\n",
            "abilities\0",
            "triggers",
            "TRIGGERS",
        ):
            with self.subTest(table=table), patch(
                "builtins.open"
            ) as opener, self.assertRaises(client.MySQLClientError):
                self.namespace["update_sql_from_db"](table)
            opener.assert_not_called()
        self.cursor.execute.assert_not_called()
        self.source_path.assert_not_called()

    def test_unknown_directory_and_symlink_sources_reject_before_open_or_query(self):
        for linked, regular in ((False, False), (True, True), (True, False)):
            with self.subTest(linked=linked, regular=regular), patch.object(
                os.path, "islink", return_value=linked
            ), patch.object(os.path, "isfile", return_value=regular), patch(
                "builtins.open"
            ) as opener, self.assertRaises(
                client.MySQLClientError
            ):
                self.namespace["update_sql_from_db"]("public_fixture")
            opener.assert_not_called()
        self.cursor.execute.assert_not_called()

    def test_non_table_or_mismatched_table_source_never_queries_or_writes(self):
        for source in (
            "CREATE VIEW public_fixture AS SELECT 1;\n",
            "-- not a table\n",
            "CREATE TABLE `other_table` (`id` int);\n",
        ):
            opener = mock_open(read_data=source)
            with self.subTest(source=source), patch.object(
                os.path, "islink", return_value=False
            ), patch.object(os.path, "isfile", return_value=True), patch(
                "builtins.open", opener
            ), self.assertRaises(
                client.MySQLClientError
            ):
                self.namespace["update_sql_from_db"]("public_fixture")
            self.assertEqual(opener.call_count, 1)
            self.assertEqual(opener.call_args.args[1], "r")
            opener().writelines.assert_not_called()
        self.cursor.execute.assert_not_called()

    @unittest.skipIf(sys.platform == "win32", "POSIX-owned symlink fixture")
    def test_actual_source_symlink_rejects_without_reading_target(self):
        with tempfile.TemporaryDirectory(
            prefix="mysql-public-link-fixture-"
        ) as temporary:
            root = Path(temporary)
            target = root / "public-target.sql"
            target.write_text(
                "CREATE TABLE public_fixture (`id` int);\n", encoding="utf-8"
            )
            link = root / "public_fixture.sql"
            link.symlink_to(target)
            self.source_path.return_value = str(link)
            with patch("builtins.open") as opener, self.assertRaises(
                client.MySQLClientError
            ):
                self.namespace["update_sql_from_db"]("public_fixture")
            opener.assert_not_called()
        self.cursor.execute.assert_not_called()

    def test_public_static_fixture_preserves_values_null_binary_float_and_comments(
        self,
    ):
        source = (
            "-- public static fixture\n"
            "CREATE TABLE `public_fixture` (`id` int);\n"
            "INSERT INTO `public_fixture` VALUES (1,'old',0x00,'',NULL,0.000);  -- keep\n"
        )
        self.cursor.fetchall.return_value = [
            (7, "O'Reilly", b"\x01\xff", b"", None, 1.25)
        ]
        self.cursor.description = [(None, 0, None, None, None, 0)] * 5 + [
            (None, 4, None, None, None, 3)
        ]
        with tempfile.TemporaryDirectory(
            prefix="mysql-public-export-fixture-"
        ) as temporary:
            path = Path(temporary) / "public_fixture.sql"
            path.write_text(source, encoding="utf-8")
            self.source_path.return_value = str(path)
            self.namespace["update_sql_from_db"]("public_fixture")
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                "-- public static fixture\n"
                "CREATE TABLE `public_fixture` (`id` int);\n"
                "INSERT INTO `public_fixture` VALUES (7,'O\\'Reilly',0x01FF,'',NULL,1.250);  -- keep\n",
            )
        self.cursor.execute.assert_called_once_with("SELECT * FROM public_fixture;")
        self.cursor.fetchall.assert_called_once_with()

    def test_cursor_error_is_redacted_and_never_writes_source(self):
        self.cursor.execute.side_effect = RuntimeError("synthetic-private-row-value")
        opener = mock_open(read_data="CREATE TABLE public_fixture (`id` int);\n")
        with patch.object(os.path, "islink", return_value=False), patch.object(
            os.path, "isfile", return_value=True
        ), patch("builtins.open", opener), self.assertRaises(
            client.MySQLClientError
        ) as error:
            self.namespace["update_sql_from_db"]("public_fixture")
        self.assertNotIn(
            "synthetic-private-row-value",
            "".join(traceback.format_exception(error.exception)),
        )
        self.assertEqual(opener.call_count, 1)
        opener().writelines.assert_not_called()


class MutationPreflightTests(unittest.TestCase):
    def namespace(self, root, auto_update=False):
        return load_dbtool(
            "preflight_client_version",
            "write_version",
            "update_db",
            "run_all_migrations",
            "setup_db",
            "backup_db",
            "fetch_configs",
            "fetch_versions",
            os=os,
            sys=sys,
            re=re,
            fileinput=fileinput,
            yaml=yaml,
            MySQLClientError=client.MySQLClientError,
            auto_update_client=auto_update,
            current_client="old",
            release_client="new",
            release_version="abcd",
            db_ver="old",
            from_server_path=lambda path: str(root / path),
            from_dbtool_path=lambda path: str(root / path),
            write_configs=Mock(),
            fetch_files=Mock(),
            import_file=Mock(),
            print_green=Mock(),
            print_red=Mock(),
            input=Mock(return_value="y"),
            auto_backup=0,
            express_enabled=False,
            import_protected=[],
            import_files=[],
            migrations=[],
            time=SimpleNamespace(sleep=Mock()),
        )

    @unittest.skipIf(sys.platform == "win32", "Portable symlink fixture requires POSIX")
    def test_false_flag_preserves_symlink_and_target_without_prompt(self):
        with tempfile.TemporaryDirectory(prefix="mysql-version-fixture-") as temporary:
            root = Path(temporary)
            (root / "settings").mkdir()
            target = root / "public-login-fixture.lua"
            content = '    CLIENT_VER = "old",\n'
            target.write_text(content, encoding="utf-8")
            link = root / "settings/login.lua"
            link.symlink_to(target)
            namespace = self.namespace(root)
            namespace["fetch_versions"] = Mock()
            namespace["write_version"]()
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.read_text(encoding="utf-8"), content)
            namespace["input"].assert_not_called()

    @unittest.skipIf(sys.platform == "win32", "Portable symlink fixture requires POSIX")
    def test_linked_client_update_fails_before_any_mutation(self):
        with tempfile.TemporaryDirectory(prefix="mysql-version-fixture-") as temporary:
            root = Path(temporary)
            (root / "settings").mkdir()
            (root / "settings/login.lua").symlink_to(
                root / "missing-public-fixture.lua"
            )
            for function in (
                "update_db",
                "run_all_migrations",
                "setup_db",
                "write_version",
            ):
                namespace = self.namespace(root, auto_update=True)
                with self.subTest(function=function), self.assertRaises(
                    client.MySQLClientError
                ):
                    (
                        namespace[function](True)
                        if function != "setup_db"
                        else namespace[function]()
                    )
                namespace["import_file"].assert_not_called()
                namespace["fetch_files"].assert_not_called()
                namespace["write_configs"].assert_not_called()

    def test_plaintext_backup_never_creates_or_launches(self):
        namespace = load_dbtool(
            "backup_db",
            input=Mock(return_value="y"),
            MySQLClientError=client.MySQLClientError,
        )
        with patch("builtins.open") as opener, patch.object(
            subprocess, "run"
        ) as run, self.assertRaises(client.MySQLClientError):
            namespace["backup_db"](True)
        opener.assert_not_called()
        run.assert_not_called()

    def test_yaml_false_remains_false_and_quoted_false_fails_closed(self):
        for value, accepted in (
            (False, True),
            ("false", False),
            (0, False),
            (None, False),
        ):
            namespace = self.namespace(Path("/synthetic"), auto_update=True)
            with patch.object(os.path, "exists", return_value=True), patch(
                "builtins.open", mock_open()
            ), patch.object(
                yaml, "full_load", return_value=[{"auto_update_client": value}]
            ):
                if accepted:
                    namespace["fetch_configs"]()
                    self.assertIs(namespace["auto_update_client"], False)
                else:
                    with self.assertRaises(SystemExit) as error:
                        namespace["fetch_configs"]()
                    self.assertEqual(error.exception.code, 1)

    def test_fetch_versions_preflights_before_fetch_files_or_connection(self):
        namespace = self.namespace(Path("/synthetic"))
        namespace.update(
            repo=SimpleNamespace(
                git=SimpleNamespace(rev_parse=Mock(return_value="abcd")),
                head=SimpleNamespace(object=SimpleNamespace(hexsha="synthetic")),
            ),
            default_settings={"login": {"CLIENT_VER": "new"}},
            settings={"login": {"CLIENT_VER": "old"}},
            preflight_client_version=Mock(
                side_effect=client.MySQLClientError("blocked")
            ),
        )
        with self.assertRaises(client.MySQLClientError):
            namespace["fetch_versions"]()
        namespace["fetch_files"].assert_not_called()


if __name__ == "__main__":
    unittest.main()
