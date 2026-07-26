from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = (
    Path(__file__).resolve().parents[1] / "portable_restore" / "verify_restore.py"
)
SPEC = importlib.util.spec_from_file_location("verify_restore", MODULE_PATH)
assert SPEC and SPEC.loader
verify = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify
SPEC.loader.exec_module(verify)


class VerifyRestoreTests(unittest.TestCase):
    def test_sensitive_word_in_lua_source_name_is_not_an_artifact(self) -> None:
        with patch.object(
            verify,
            "run_git",
            return_value=[" M scripts/quests/bastok/Cids_Secret.lua"],
        ):
            issues = verify.check_staged_sensitive(Path("."))

        self.assertEqual(issues, [])

    def test_non_source_sensitive_artifacts_still_fail_closed(self) -> None:
        with patch.object(
            verify,
            "run_git",
            return_value=[
                "?? runtime/database-password.cnf",
                "A  runtime/mochirii-token.txt",
                "?? restore/private/mochirii-secret.lua",
            ],
        ):
            issues = verify.check_staged_sensitive(Path("."))

        self.assertEqual(
            issues,
            [
                "review sensitive-looking changed path before commit: "
                "runtime/database-password.cnf",
                "review sensitive-looking changed path before commit: "
                "runtime/mochirii-token.txt",
                "review sensitive-looking changed path before commit: "
                "restore/private/mochirii-secret.lua",
            ],
        )

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
