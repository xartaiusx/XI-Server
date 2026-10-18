from __future__ import annotations

import unittest
from pathlib import Path

import yaml

from tools.mochirii.codeql_coverage import (
    COMPILER_ERRORS_METRIC,
    WINDOWS_SECURITY_APIS,
    WINDOWS_SECURITY_METRIC,
)


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
            ".github/workflows/codeql_analysis.yml:analyze/build-mode:manual/language:cpp/platform:windows-security",
        }
        self.assertEqual({entry["category"] for entry in entries}, expected_categories)
        self.assertEqual(len(entries), 5)
        for entry in entries:
            if entry.get("windows_security"):
                self.assertEqual(entry["runner"], "windows-2025")
                self.assertEqual(
                    (entry["language"], entry["build-mode"]), ("cpp", "manual")
                )
            elif entry["language"] == "cpp":
                self.assertEqual(entry["runner"], "ubuntu-26.04")
            if entry["build-mode"] == "manual" and not entry.get("windows_security"):
                self.assertTrue(entry["category"].endswith(":analyze/language:cpp"))
            if entry.get("legacy"):
                self.assertEqual(entry["language"], "python")
                self.assertTrue(entry["category"].endswith(":analyze/language:python"))
        self.assertEqual(
            job["name"],
            "Analyze (${{ matrix.language }}, ${{ matrix.build-mode }})${{ matrix.legacy && ' legacy' || '' }}${{ matrix.windows_security && ' Windows security' || '' }}",
        )
        self.assertEqual(job["env"]["CODEQL_ACTION_FILE_COVERAGE_ON_PRS"], "true")

    def test_windows_lane_is_focused_uncached_and_extends_full_queries(self) -> None:
        job = self.workflow["jobs"]["analyze"]
        steps = {step.get("name"): step for step in job["steps"]}
        self.assertEqual(job["defaults"]["run"]["shell"], "bash")
        self.assertEqual(
            steps["Setup MSVC"]["uses"],
            "TheMrMilchmann/setup-msvc-dev@368ef7d1ee4d1171b31d4a7f67f4d954f903f5a9",
        )
        self.assertEqual(steps["Setup MSVC"]["with"], {"arch": "x64"})
        configure = steps["Configure Windows security extraction context"]["run"]
        for flag in (
            "--fresh",
            "-DPCH_ENABLE=OFF",
            "-DCACHE_BINARY:FILEPATH=",
            "-DCMAKE_CXX_COMPILER_LAUNCHER:STRING=",
            "-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded",
        ):
            self.assertIn(flag, configure)
        self.assertIn("--target enum_codegen --parallel 4", configure)
        self.assertNotIn("data_schema_generate", configure)
        self.assertEqual(
            steps["Trace Windows TLS and private-file targets"]["run"].strip(),
            "cmake --build build --target xi_connect xi_profile --parallel 4",
        )
        self.assertIn(
            "!matrix.windows_security",
            steps["Trace all server targets and modules"]["if"],
        )
        self.assertEqual(
            steps["Initialize CodeQL"]["with"]["queries"],
            "${{ matrix.language == 'cpp' && '+./.github/codeql/security-coverage' || '' }}",
        )
        self.assertIn(
            "--require-windows-security",
            steps["Check raw coverage and diagnostics"]["run"],
        )
        self.assertIn(
            "matrix.windows_security && '--require-windows-security'",
            steps["Check raw coverage and diagnostics"]["run"],
        )
        self.assertTrue(
            all("sccache" not in step.get("uses", "") for step in job["steps"])
        )

    def test_windows_metric_queries_native_calls_not_file_presence(self) -> None:
        pack_root = self.repo / ".github/codeql/security-coverage"
        manifest = yaml.safe_load((pack_root / "qlpack.yml").read_text())
        self.assertEqual(manifest["name"], "mochirii/security-coverage")
        self.assertEqual(manifest["dependencies"], {"codeql/cpp-all": "12.2.0"})
        query = (pack_root / "WindowsPrivateFileCalls.ql").read_text()
        self.assertIn("@kind metric", query)
        self.assertIn(f"@id {WINDOWS_SECURITY_METRIC}", query)
        self.assertIn("select count(string api |", query)
        self.assertIn(
            'hasQualifiedName("certificateHelpers", "openExclusivePrivateFile")', query
        )
        self.assertIn('getRelativePath() = "src/common/cert_helpers.h"', query)
        self.assertIn("call.getTarget().getName() = api", query)
        self.assertEqual(len(WINDOWS_SECURITY_APIS), 8)
        for name in WINDOWS_SECURITY_APIS:
            self.assertEqual(query.count(f'"{name}"'), 1)

    def test_shared_compiler_metric_includes_native_error_and_fatal_classes(
        self,
    ) -> None:
        query = (
            self.repo / ".github/codeql/security-coverage/CompilerErrorsTotal.ql"
        ).read_text()
        self.assertIn("@kind metric", query)
        self.assertIn(f"@id {COMPILER_ERRORS_METRIC}", query)
        self.assertIn("select count(Diagnostic diagnostic |", query)
        self.assertIn(
            "diagnostic instanceof CompilerError or diagnostic instanceof CompilerCatastrophe",
            query,
        )
        self.assertNotIn("CompilerDiscretionaryError", query)

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
        self.assertIn("--target enum_codegen --parallel 4", configure)
        self.assertNotIn("data_schema_generate", configure)
        schema = steps["Build traced schema context"]
        self.assertEqual(schema["if"], "matrix.build-mode == 'manual'")
        self.assertIn("--target data_schema_generate --parallel 4", schema["run"])
        names = [step.get("name") for step in job["steps"]]
        self.assertLess(names.index("Initialize CodeQL"), names.index(schema["name"]))
        for trace in (
            "Trace all server targets and modules",
            "Trace Windows TLS and private-file targets",
        ):
            self.assertLess(names.index(schema["name"]), names.index(trace))
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
        self.assertIn(
            "${{ matrix.windows_security && 'windows-security_' || '' }}",
            upload["with"]["name"],
        )
        self.assertEqual(upload["with"]["if-no-files-found"], "error")
        self.assertIn(
            "--require-cpp-recovery",
            steps[names.index("Check raw coverage and diagnostics")]["run"],
        )


if __name__ == "__main__":
    unittest.main()
