from __future__ import annotations

import importlib
import unittest

from jinja2 import DictLoader

ENV = importlib.import_module("tools.codegen.common").ENV


class CodeGenerationEscapingTests(unittest.TestCase):
    def test_named_code_templates_preserve_source_characters(self) -> None:
        for name in ("enum.h.j2", "enum.lua.j2"):
            with self.subTest(name=name):
                environment = ENV.overlay(loader=DictLoader({name: "{{ value }}"}))
                self.assertEqual(
                    environment.get_template(name).render(value="A<B>&C"), "A<B>&C"
                )

    def test_html_xml_and_anonymous_templates_escape(self) -> None:
        for name in ("audit.html", "audit.xml"):
            with self.subTest(name=name):
                environment = ENV.overlay(loader=DictLoader({name: "{{ value }}"}))
                self.assertEqual(
                    environment.get_template(name).render(value="<x>&"),
                    "&lt;x&gt;&amp;",
                )
        self.assertEqual(
            ENV.from_string("{{ value }}").render(value="<x>&"), "&lt;x&gt;&amp;"
        )


if __name__ == "__main__":
    unittest.main()
