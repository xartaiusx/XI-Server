from __future__ import annotations

import unittest
from pathlib import Path

import yaml


class CodeScanningCoverageTests(unittest.TestCase):
    def test_core_and_tooling_findings_are_not_filtered(self) -> None:
        repo = Path(__file__).resolve().parents[3]
        workflow = yaml.safe_load(
            (repo / ".github" / "workflows" / "codeql_analysis.yml").read_text()
        )
        filter_step = next(
            step
            for step in workflow["jobs"]["analyze"]["steps"]
            if step.get("name") == "Filter SARIF"
        )
        self.assertEqual(
            filter_step["with"]["patterns"].splitlines(), ["-ext/**/*", "-build/**/*"]
        )
        config = yaml.safe_load(
            (repo / ".github" / "codeql" / "codeql-config.yml").read_text()
        )
        self.assertEqual(set(config["paths-ignore"]), {"ext/**", "build/**"})
        self.assertEqual(
            {query["uses"] for query in config["queries"]},
            {"security-extended", "security-and-quality"},
        )


if __name__ == "__main__":
    unittest.main()
