from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = (
    Path(__file__).resolve().parents[1] / "portable_restore" / "verify_restore.py"
)
SPEC = importlib.util.spec_from_file_location("verify_restore", MODULE_PATH)
assert SPEC and SPEC.loader
verify = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify
SPEC.loader.exec_module(verify)


class VerifyRestoreTests(unittest.TestCase):
    def test_client_graphics_cross_check_requires_source_of_truth(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            manifests = repo / "restore" / "manifests"
            manifests.mkdir(parents=True)
            (manifests / "client-graphics-gates.manifest.json").write_text(
                "{}\n", encoding="utf-8"
            )
            (manifests / "mods.manifest.json").write_text("{}\n", encoding="utf-8")

            issues = verify.check_client_graphics_manifest(repo)
            self.assertTrue(
                any("source-of-truth.manifest.json" in issue for issue in issues)
            )

            (manifests / "source-of-truth.manifest.json").write_text(
                "not json\n", encoding="utf-8"
            )
            issues = verify.check_client_graphics_manifest(repo)
            self.assertTrue(any("could not load" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
