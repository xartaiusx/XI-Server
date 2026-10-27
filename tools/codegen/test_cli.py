from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import cli


class CodegenOutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.enums = self.source / "data" / "enums"
        self.enums.mkdir(parents=True)
        (self.enums / "test_choice.yaml").write_text(
            "meta:\n  cpp:\n    class: TestChoice\n  lua:\n    table: xi.testChoice\n"
            "values:\n  first: 1\n  second: 2\n", encoding="utf-8"
        )
        self.build = self.root / "build"
        for name, value in (("ROOT", self.source), ("ENUMS_DIR", self.enums),
                            ("ZONES_DIR", self.source / "data" / "zones")):
            patcher = patch.object(cli, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_codegen(self, *arguments):
        with patch("sys.argv", ["codegen", str(self.build), *map(str, arguments)]):
            cli.main()

    def test_isolated_outputs_leave_source_untouched(self):
        before = {path.relative_to(self.source): path.read_bytes()
                  for path in self.source.rglob("*") if path.is_file()}
        lua = self.root / "private" / "enums"
        schemas = self.root / "private" / "schemas"
        with patch.object(cli, "validate_data_yamls") as validate:
            self.run_codegen("--lua-enum-output-dir", lua,
                             "--schema-output-dir", schemas, "--validate")
        validate.assert_called_once_with(schemas.resolve())
        self.assertIn(b"FIRST", (lua / "test_choice.codegen.lua").read_bytes())
        header = self.build / "generated" / "data" / "enums" / "test_choice.h"
        self.assertIn(b"TestChoice", header.read_bytes())
        after = {path.relative_to(self.source): path.read_bytes()
                 for path in self.source.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_destination_change_with_fresh_stamp_regenerates_same_bytes(self):
        first = self.root / "first"
        second = self.root / "second"
        self.run_codegen("--lua-enum-output-dir", first)
        expected = (first / "test_choice.codegen.lua").read_bytes()
        with patch.object(cli, "enum_inputs_newer_than", return_value=False):
            self.run_codegen("--lua-enum-output-dir", second)
        self.assertEqual((second / "test_choice.codegen.lua").read_bytes(), expected)

    def test_validation_runs_even_when_render_is_current(self):
        self.run_codegen()
        with patch.object(cli, "enum_inputs_newer_than", return_value=False), \
                patch.object(cli, "emit_pure_enum") as render, \
                patch.object(cli, "validate_data_yamls") as validate:
            self.run_codegen("--validate")
        render.assert_not_called()
        validate.assert_called_once_with((self.source / "data" / "schemas").resolve())

    def test_default_output_remains_source_enum_directory(self):
        # argparse defaults are evaluated by main(), after the test ROOT is set.
        self.run_codegen()
        self.assertTrue((self.source / "scripts" / "enum" / "test_choice.codegen.lua").is_file())


if __name__ == "__main__":
    unittest.main()
