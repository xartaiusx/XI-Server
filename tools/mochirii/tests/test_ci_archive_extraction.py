from __future__ import annotations

import ast
import io
import os
import tarfile
import tempfile
import unittest
from pathlib import Path


class LanguageServerArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = (
            Path(__file__).resolve().parents[3] / "tools" / "ci" / "lua_lang_server.py"
        )
        calls = [
            node
            for node in ast.walk(ast.parse(source.read_text()))
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "tar_ref"
            and node.func.attr == "extractall"
        ]
        if len(calls) != 1:
            raise AssertionError("Expected one native TAR extraction call")
        cls.extraction_options = {
            keyword.arg: ast.literal_eval(keyword.value)
            for keyword in calls[0].keywords
        }

    def test_native_call_explicitly_uses_the_data_filter(self) -> None:
        self.assertEqual(self.extraction_options, {"filter": "data"})

    def extract_member(self, member: tarfile.TarInfo, destination: Path) -> None:
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w") as archive:
            content = b"fixture" if member.isfile() else b""
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))
        buffer.seek(0)
        with tarfile.open(fileobj=buffer, mode="r") as archive:
            archive.extractall(destination, **self.extraction_options)

    def test_regular_release_member_extracts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "release"
            member = tarfile.TarInfo("bin/lua-language-server")
            member.mode = 0o755
            self.extract_member(member, destination)
            self.assertEqual(
                (destination / "bin/lua-language-server").read_bytes(), b"fixture"
            )
            if os.name == "posix":
                self.assertEqual(
                    (destination / "bin/lua-language-server").stat().st_mode & 0o777,
                    0o755,
                )

    def test_parent_traversal_is_rejected_without_writing_outside(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(tarfile.OutsideDestinationError):
                self.extract_member(tarfile.TarInfo("../escape"), root / "release")
            self.assertFalse((root / "escape").exists())

    def test_external_links_are_rejected_without_writing_outside(self) -> None:
        for link_type in (tarfile.SYMTYPE, tarfile.LNKTYPE):
            with self.subTest(
                link_type=link_type
            ), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                member = tarfile.TarInfo("link")
                member.type = link_type
                member.linkname = "../escape"
                with self.assertRaises(tarfile.LinkOutsideDestinationError):
                    self.extract_member(member, root / "release")
                self.assertFalse((root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
