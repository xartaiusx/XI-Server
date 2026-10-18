from __future__ import annotations

import importlib
import socket
import ssl
import unittest
from unittest.mock import patch

HXIClient = importlib.import_module("tools.headlessxi.hxiclient").HXIClient


class HeadlessClientTLSPolicyTests(unittest.TestCase):
    def context_for(self, server: str) -> ssl.SSLContext:
        client = HXIClient.__new__(HXIClient)
        client.server = server
        with (
            patch("tools.headlessxi.hxiclient.socket.socket") as socket_factory,
            patch.object(
                ssl.SSLContext,
                "wrap_socket",
                side_effect=RuntimeError("stop-before-network"),
            ) as wrap_socket,
            patch("builtins.print"),
            self.assertRaisesRegex(RuntimeError, "^stop-before-network$"),
        ):
            client.login()
        socket_factory.assert_called_once_with(socket.AF_INET, socket.SOCK_STREAM)
        wrap_socket.assert_called_once_with(
            socket_factory.return_value, server_hostname=server
        )
        socket_factory.return_value.connect.assert_not_called()
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

    def test_direct_connection_cannot_keep_an_older_protocol(self) -> None:
        client = HXIClient.__new__(HXIClient)
        client.server = "example.invalid"
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.maximum_version = ssl.TLSVersion.TLSv1_2
        with (
            patch("tools.headlessxi.hxiclient.socket.socket") as socket_factory,
            patch.object(
                ssl.SSLContext,
                "wrap_socket",
                side_effect=RuntimeError("stop-before-network"),
            ),
            patch("builtins.print"),
            self.assertRaisesRegex(RuntimeError, "^stop-before-network$"),
        ):
            client.login_connect(context)
        self.assertEqual(context.minimum_version, ssl.TLSVersion.TLSv1_3)
        self.assertEqual(context.maximum_version, ssl.TLSVersion.TLSv1_3)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)
        socket_factory.return_value.connect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
