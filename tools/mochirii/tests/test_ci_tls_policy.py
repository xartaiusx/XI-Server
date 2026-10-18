from __future__ import annotations

import importlib
import ssl
import unittest
from unittest.mock import Mock, patch

HXIClient = importlib.import_module("tools.headlessxi.hxiclient").HXIClient


class HeadlessClientTLSPolicyTests(unittest.TestCase):
    def context_for(self, server: str) -> ssl.SSLContext:
        client = HXIClient.__new__(HXIClient)
        client.server = server
        client.login_connect = Mock(side_effect=RuntimeError("stop-before-network"))
        with self.assertRaisesRegex(RuntimeError, "^stop-before-network$"):
            client.login()
        client.login_connect.assert_called_once_with(client.ssl_context)
        return client.ssl_context

    def test_remote_targets_require_certificate_and_hostname_verification(self) -> None:
        for server in (
            "example.invalid",
            "192.0.2.1",
            "localhost.example.invalid",
            "127.0.0.1.example.invalid",
        ):
            with self.subTest(server=server):
                context = self.context_for(server)
                self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
                self.assertTrue(context.check_hostname)

    def test_loopback_development_remains_supported(self) -> None:
        for server in ("localhost", "127.0.0.1", "::1"):
            with self.subTest(server=server):
                context = self.context_for(server)
                self.assertEqual(context.verify_mode, ssl.CERT_NONE)
                self.assertFalse(context.check_hostname)

    def test_protocol_is_tls13_only_before_network_access(self) -> None:
        context = self.context_for("example.invalid")
        self.assertEqual(context.protocol, ssl.PROTOCOL_TLS_CLIENT)
        self.assertEqual(context.minimum_version, ssl.TLSVersion.TLSv1_3)
        self.assertEqual(context.maximum_version, ssl.TLSVersion.TLSv1_3)

    def test_secure_factory_context_is_not_replaced(self) -> None:
        expected = ssl.create_default_context()
        with patch(
            "tools.headlessxi.hxiclient.ssl.create_default_context",
            return_value=expected,
        ) as factory:
            self.assertIs(self.context_for("example.invalid"), expected)
        factory.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
