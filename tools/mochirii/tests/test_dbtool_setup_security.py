"""Synthetic setup ordering without importing settings or connecting to a DB."""

from types import SimpleNamespace
import sys
import unittest
from unittest.mock import Mock

from tools import mysql_client
from tools.mochirii.tests.test_mysql_client_security import load_dbtool


class SetupPreflightTests(unittest.TestCase):
    def namespace(self):
        events = []
        created = {"value": False}

        def inventory(*_args):
            self.assertTrue(created["value"], "Inventory ran before database creation")
            events.append("inventory")

        def create(*_args, **_kwargs):
            self.assertFalse(created["value"], "Database creation was repeated")
            created["value"] = True
            events.append("create")
            return SimpleNamespace(returncode=0)

        namespace = load_dbtool(
            "main",
            "fetch_versions",
            os=SimpleNamespace(path=SimpleNamespace(exists=lambda _path: True)),
            sys=SimpleNamespace(argv=["dbtool.py", "setup", "xidb"], exit=sys.exit),
            MySQLClientError=mysql_client.MySQLClientError,
            mysql_bin="",
            exe="",
            database="xidb",
            host=object(),
            port=33307,
            login=object(),
            password=object(),
            db_ver="",
            express_enabled=False,
            fetch_credentials=Mock(),
            fetch_configs=Mock(),
            repo=SimpleNamespace(
                git=SimpleNamespace(rev_parse=Mock(return_value="abcd")),
                head=SimpleNamespace(object=SimpleNamespace(hexsha="a" * 40)),
            ),
            default_settings={"login": {"CLIENT_VER": "new"}},
            settings={"login": {"CLIENT_VER": "new"}},
            preflight_client_version=Mock(
                side_effect=lambda: events.append("preflight")
            ),
            fetch_files=Mock(side_effect=inventory),
            run_mysql=Mock(side_effect=create),
            fetch_errors=Mock(),
            setup_db=Mock(side_effect=lambda: events.append("setup")),
            connect=Mock(side_effect=AssertionError("Unexpected connection")),
            input=Mock(side_effect=AssertionError("Unexpected prompt")),
            print_red=Mock(),
        )
        return namespace, events, created

    def test_version_only_preflight_does_not_enumerate_or_connect(self):
        namespace, events, _ = self.namespace()
        namespace["fetch_versions"](load_files=False)
        self.assertEqual(events, ["preflight"])
        self.assertEqual(namespace["release_version"], "abcd")
        self.assertEqual(namespace["current_client"], "new")
        namespace["fetch_files"].assert_not_called()
        namespace["connect"].assert_not_called()
        namespace["input"].assert_not_called()

    def test_fresh_setup_creates_once_before_inventory_without_prompt(self):
        namespace, events, _ = self.namespace()
        namespace["main"]()
        self.assertEqual(
            events, ["preflight", "create", "preflight", "inventory", "setup"]
        )
        namespace["run_mysql"].assert_called_once()
        namespace["fetch_files"].assert_called_once_with()
        namespace["setup_db"].assert_called_once_with()
        namespace["connect"].assert_not_called()
        namespace["input"].assert_not_called()

    def test_setup_refusal_precedes_creation_and_inventory(self):
        namespace, _, _ = self.namespace()
        namespace["preflight_client_version"].side_effect = (
            mysql_client.MySQLClientError("blocked")
        )
        with self.assertRaises(SystemExit) as error:
            namespace["main"]()
        self.assertEqual(error.exception.code, 1)
        namespace["run_mysql"].assert_not_called()
        namespace["fetch_files"].assert_not_called()
        namespace["setup_db"].assert_not_called()

    def test_default_version_refresh_retains_inventory_behavior(self):
        namespace, events, created = self.namespace()
        created["value"] = True
        namespace["fetch_versions"]()
        self.assertEqual(events, ["preflight", "inventory"])
        namespace["fetch_files"].assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
