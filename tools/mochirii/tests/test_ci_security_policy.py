from __future__ import annotations

import unittest
from pathlib import Path

import yaml


class CodeScanningCoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[3]
        self.workflow = yaml.safe_load(
            (self.repo / ".github" / "workflows" / "codeql_analysis.yml").read_text()
        )

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

    def test_none_breadth_and_distinct_manual_category_are_retained(self) -> None:
        job = self.workflow["jobs"]["analyze"]
        entries = job["strategy"]["matrix"]["include"]
        self.assertEqual(
            {(entry["language"], entry["build-mode"]) for entry in entries},
            {("cpp", "none"), ("cpp", "manual"), ("python", "none")},
        )
        expected_categories = {
            ".github/workflows/codeql_analysis.yml:analyze/build-mode:none/language:cpp",
            ".github/workflows/codeql_analysis.yml:analyze/build-mode:none/language:python",
            ".github/workflows/codeql_analysis.yml:analyze/language:cpp",
            ".github/workflows/codeql_analysis.yml:analyze/language:python",
        }
        self.assertEqual({entry["category"] for entry in entries}, expected_categories)
        self.assertEqual(len(entries), 4)
        for entry in entries:
            if entry["language"] == "cpp":
                self.assertEqual(entry["runner"], "ubuntu-26.04")
            if entry["build-mode"] == "manual":
                self.assertTrue(entry["category"].endswith(":analyze/language:cpp"))
            if entry.get("legacy"):
                self.assertEqual(entry["language"], "python")
                self.assertTrue(entry["category"].endswith(":analyze/language:python"))
        self.assertEqual(
            job["name"],
            "Analyze (${{ matrix.language }}, ${{ matrix.build-mode }})${{ matrix.legacy && ' legacy' || '' }}",
        )
        self.assertEqual(job["env"]["CODEQL_ACTION_FILE_COVERAGE_ON_PRS"], "true")

    def test_traced_build_is_complete_uncached_and_unprivileged(self) -> None:
        job = self.workflow["jobs"]["analyze"]
        steps = {step.get("name"): step for step in job["steps"]}
        self.assertIs(
            steps["Checkout repository"]["with"]["persist-credentials"], False
        )
        configure = steps["Configure C++ extraction context"]["run"]
        for flag in (
            "--fresh",
            "-DPCH_ENABLE=OFF",
            "-DCACHE_BINARY:FILEPATH=",
            "-DCMAKE_CXX_COMPILER_LAUNCHER:STRING=",
            "tools/packetcap",
        ):
            self.assertIn(flag, configure)
        self.assertIn("g++-15", steps["Install Dependencies"]["run"])
        build = steps["Trace all server targets and modules"]["run"]
        self.assertIn(
            "--target xi_connect xi_map xi_profile xi_search xi_world xi_test", build
        )
        self.assertNotIn(
            "pull_request_target", self.workflow.get("on", self.workflow.get(True, {}))
        )
        self.assertEqual(
            job["permissions"],
            {"actions": "read", "contents": "read", "security-events": "write"},
        )

    def test_raw_evidence_is_retained_before_filter_even_on_gate_failure(self) -> None:
        steps = self.workflow["jobs"]["analyze"]["steps"]
        names = [step.get("name") for step in steps]
        self.assertLess(
            names.index("Check raw coverage and diagnostics"),
            names.index("Filter SARIF"),
        )
        self.assertLess(
            names.index("Preserve raw SARIF and coverage evidence"),
            names.index("Filter SARIF"),
        )
        upload = steps[names.index("Preserve raw SARIF and coverage evidence")]
        self.assertEqual(upload["if"], "always()")
        self.assertEqual(
            upload["uses"],
            "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9",
        )
        self.assertIn("${{ github.sha }}", upload["with"]["name"])
        self.assertIn("${{ matrix.legacy && 'legacy_' || '' }}", upload["with"]["name"])
        self.assertEqual(upload["with"]["if-no-files-found"], "error")
        self.assertIn(
            "--require-cpp-recovery",
            steps[names.index("Check raw coverage and diagnostics")]["run"],
        )


if __name__ == "__main__":
    unittest.main()
