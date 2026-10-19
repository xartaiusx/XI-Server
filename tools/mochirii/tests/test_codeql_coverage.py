from __future__ import annotations

import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.mochirii.codeql_coverage import (
    COMPILER_ERRORS_METRIC,
    CPP_RECOVERY_PATHS,
    WINDOWS_SECURITY_APIS,
    WINDOWS_SECURITY_METRIC,
    WINDOWS_SECURITY_PATHS,
    analyze_sarif,
    load_sarif,
    repository_path,
    verify_checkout_sha,
)

SHA = "a" * 40
CATEGORY = ".github/workflows/codeql_analysis.yml:analyze/language:cpp"
CRITICAL = "src/map/utils/trustutils.cpp"


def notification(identifier: str, path: str) -> dict:
    return {
        "descriptor": {"id": identifier},
        "level": "none",
        "locations": [
            {
                "physicalLocation": {
                    "artifactLocation": {"uri": path, "uriBaseId": "%SRCROOT%"}
                }
            }
        ],
    }


def sarif() -> dict:
    # Native CodeQL diagnostic IDs, not alert locations or archived source files.
    return {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "CodeQL",
                        "semanticVersion": "2.27.2",
                        "rules": [],
                    }
                },
                "automationDetails": {"id": CATEGORY + "/"},
                "versionControlProvenance": [{"revisionId": SHA}],
                "invocations": [
                    {
                        "executionSuccessful": True,
                        "toolExecutionNotifications": [
                            notification(
                                "cpp/baseline/expected-extracted-files", CRITICAL
                            ),
                            notification(
                                "cpp/diagnostics/successfully-extracted-files", CRITICAL
                            ),
                        ],
                    }
                ],
                "results": [],
                "properties": {
                    "metricResults": [{"ruleId": COMPILER_ERRORS_METRIC, "value": 0}]
                },
            }
        ],
    }


def analyze(data: dict, required: tuple[str, ...] = (CRITICAL,)) -> dict:
    return analyze_sarif(
        data, language="cpp", category=CATEGORY, source_sha=SHA, required_paths=required
    )


def windows_sarif() -> dict:
    data = sarif()
    run = data["runs"][0]
    run["invocations"][0]["toolExecutionNotifications"] = [
        notification(identifier, path)
        for path in WINDOWS_SECURITY_PATHS
        for identifier in (
            "cli/expected-extracted-files/cpp",
            "cpp/diagnostics/successfully-extracted-files",
        )
    ]
    run["properties"]["metricResults"].append(
        {
            "rule": {"id": WINDOWS_SECURITY_METRIC},
            "value": len(WINDOWS_SECURITY_APIS),
        }
    )
    return data


def analyze_windows(data: dict) -> dict:
    return analyze_sarif(
        data,
        language="cpp",
        category=CATEGORY,
        source_sha=SHA,
        require_windows_security=True,
    )


class NativeCodeQLCoverageTests(unittest.TestCase):
    def test_valid_native_inventory_is_deterministic(self) -> None:
        data = sarif()
        self.assertEqual(analyze(data), analyze(copy.deepcopy(data)))
        report = analyze(data)
        self.assertEqual(report["gate"], "passed")
        self.assertEqual(report["compiler_errors"], 0)
        self.assertEqual(report["expected_files"], 1)
        self.assertEqual(report["extracted_expected_files"], 1)
        self.assertEqual(
            report["files"], [{"path": CRITICAL, "expected": True, "extracted": True}]
        )

    def test_exact_initial_cpp_recovery_set_is_preserved(self) -> None:
        self.assertEqual(len(CPP_RECOVERY_PATHS), 40)
        self.assertEqual(tuple(sorted(set(CPP_RECOVERY_PATHS))), CPP_RECOVERY_PATHS)
        self.assertTrue(all(path.endswith(".cpp") for path in CPP_RECOVERY_PATHS))
        self.assertIn(CRITICAL, CPP_RECOVERY_PATHS)
        self.assertIn("modules/tools/packetcap/packetcap.cpp", CPP_RECOVERY_PATHS)

    def test_native_compiler_error_metric_must_execute_even_when_zero(self) -> None:
        data = sarif()
        del data["runs"][0]["properties"]
        # Rule discovery is not evidence that the native query executed.
        data["runs"][0]["tool"]["driver"]["rules"].append(
            {"id": COMPILER_ERRORS_METRIC}
        )
        for required in ((), (CRITICAL,)):
            with self.subTest(required=required):
                report = analyze(data, required)
                self.assertEqual(report["gate"], "failed")
                self.assertIsNone(report["compiler_errors"])
        data = sarif()
        metrics = data["runs"][0]["properties"]["metricResults"]
        metrics.append(copy.deepcopy(metrics[0]))
        self.assertEqual(analyze(data, ())["gate"], "failed")
        data = windows_sarif()
        data["runs"][0]["properties"]["metricResults"].pop(0)
        report = analyze_windows(data)
        self.assertEqual(report["gate"], "failed")
        self.assertIsNone(report["compiler_errors"])
        self.assertEqual(
            report["windows_private_file"]["observed_api_family_counts"], [8]
        )

    def test_native_compiler_error_metric_requires_nonnegative_integer(self) -> None:
        for value in (True, False, -1, 0.0, "0", float("nan"), float("inf"), None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                data = sarif()
                data["runs"][0]["properties"]["metricResults"][0]["value"] = value
                analyze(data, ())

    def test_nonzero_native_errors_block_both_manual_lanes_but_remain_in_none(
        self,
    ) -> None:
        data = sarif()
        data["runs"][0]["properties"]["metricResults"][0]["value"] = 3
        report = analyze(data, ())
        self.assertEqual(report["gate"], "passed")
        self.assertEqual(report["compiler_errors"], 3)
        self.assertEqual(analyze(data)["gate"], "failed")
        data = windows_sarif()
        data["runs"][0]["properties"]["metricResults"][0]["value"] = 3
        self.assertEqual(analyze_windows(data)["gate"], "failed")

    def test_discretionary_diagnostics_are_not_hidden_by_zero_error_metric(
        self,
    ) -> None:
        data = sarif()
        data["runs"][0]["invocations"][0]["toolExecutionNotifications"].append(
            {
                "descriptor": {"id": "cpp/diagnostics/extraction-warnings"},
                "level": "warning",
                "message": {"text": "Discretionary diagnostic remains reviewable"},
            }
        )
        report = analyze(data)
        self.assertEqual(report["compiler_errors"], 0)
        self.assertEqual(report["diagnostics"][0]["level"], "warning")
        self.assertIn("Discretionary", report["diagnostics"][0]["message"])

    def test_failed_extractor_notifications_block_both_manual_lanes(self) -> None:
        for factory, evaluate in ((sarif, analyze), (windows_sarif, analyze_windows)):
            for prefix in ("cpp", "c"):
                for level in ("none", "note", "warning", "error"):
                    for indexed in (False, True):
                        with self.subTest(
                            lane=evaluate.__name__,
                            prefix=prefix,
                            level=level,
                            indexed=indexed,
                        ):
                            data = factory()
                            run = data["runs"][0]
                            identifier = (
                                f"{prefix}/diagnostics/failed-extractor-invocations"
                            )
                            descriptor = {"id": identifier}
                            if indexed:
                                run["tool"]["driver"]["notifications"] = [
                                    {"id": identifier}
                                ]
                                descriptor = {"index": 0}
                            run["invocations"][0]["toolExecutionNotifications"].append(
                                {"descriptor": descriptor, "level": level}
                            )
                            report = evaluate(data)
                            self.assertEqual(report["compiler_errors"], 0)
                            self.assertEqual(report["gate"], "failed")

    def test_native_extractor_failure_text_cannot_hide_in_truncated_warnings(
        self,
    ) -> None:
        messages = (
            ("Internal error: assertion failed at: declarator.c:3182", True),
            ("INTERNAL ERROR: ASSERTION FAILED AT: declarator.c:3182", True),
            ("Extractor exiting with code 4", True),
            ("Extractor exiting with code -1", True),
            ("Extractor exiting with code 0\nExtractor exiting with code +4", True),
            ("x" * 4096 + "Extractor exiting with code 4", True),
            (
                "x" * 4096 + "Internal error: assertion failed at: declarator.c:3182",
                True,
            ),
            ("Extractor exiting with code 0", False),
            ("Discretionary diagnostic remains reviewable", False),
            ("Ordinary compiler warning about an assertion helper", False),
        )
        for factory, evaluate in ((sarif, analyze), (windows_sarif, analyze_windows)):
            for prefix in ("cpp", "c"):
                for message_index, (message, failed) in enumerate(messages):
                    for indexed in (False, True):
                        with self.subTest(
                            lane=evaluate.__name__,
                            prefix=prefix,
                            message_index=message_index,
                            indexed=indexed,
                        ):
                            data = factory()
                            run = data["runs"][0]
                            identifier = f"{prefix}/diagnostics/extraction-warnings"
                            descriptor = {"id": identifier}
                            if indexed:
                                run["tool"]["driver"]["notifications"] = [
                                    {"id": identifier}
                                ]
                                descriptor = {"index": 0}
                            run["invocations"][0]["toolExecutionNotifications"].append(
                                {
                                    "descriptor": descriptor,
                                    "level": "warning",
                                    "message": {"text": message},
                                }
                            )
                            report = evaluate(data)
                            self.assertEqual(report["compiler_errors"], 0)
                            self.assertEqual(
                                report["gate"], "failed" if failed else "passed"
                            )
                            self.assertEqual(
                                report["failed_extractor_notifications"], int(failed)
                            )

    def test_windows_requires_positive_native_api_metric_not_header_presence(
        self,
    ) -> None:
        data = windows_sarif()
        report = analyze_windows(data)
        self.assertEqual(report["gate"], "passed")
        self.assertEqual(report["expected_files"], len(WINDOWS_SECURITY_PATHS))
        self.assertEqual(report["missing_required_cpp"], [])
        self.assertEqual(
            report["windows_private_file"]["observed_api_family_counts"], [8]
        )
        # Source-file presence alone cannot establish the _WIN32 AST branch.
        data["runs"][0]["properties"]["metricResults"].pop()
        self.assertEqual(analyze_windows(data)["gate"], "failed")

    def test_windows_preserves_unextracted_baseline_and_requires_its_sources(
        self,
    ) -> None:
        data = windows_sarif()
        notes = data["runs"][0]["invocations"][0]["toolExecutionNotifications"]
        notes.append(notification("cli/expected-extracted-files/cpp", CRITICAL))
        report = analyze_windows(data)
        self.assertEqual(report["gate"], "passed")
        self.assertEqual(report["missing_files"], [CRITICAL])
        self.assertEqual(report["expected_files"], len(WINDOWS_SECURITY_PATHS) + 1)
        notes.pop(-2)
        report = analyze_windows(data)
        self.assertEqual(report["gate"], "failed")
        self.assertEqual(
            report["windows_private_file"]["missing_required_sources"],
            [WINDOWS_SECURITY_PATHS[-1]],
        )

    def test_windows_incomplete_duplicate_and_invalid_api_counts_fail(self) -> None:
        for count in range(len(WINDOWS_SECURITY_APIS)):
            with self.subTest(count=count):
                data = windows_sarif()
                data["runs"][0]["properties"]["metricResults"][-1]["value"] = count
                self.assertEqual(analyze_windows(data)["gate"], "failed")
        data = windows_sarif()
        metrics = data["runs"][0]["properties"]["metricResults"]
        metrics.append(copy.deepcopy(metrics[-1]))
        self.assertEqual(analyze_windows(data)["gate"], "failed")
        for value in (True, False, -1, 9, 8.0, "8", float("nan"), None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                data = windows_sarif()
                data["runs"][0]["properties"]["metricResults"][-1]["value"] = value
                analyze_windows(data)

    def test_windows_and_linux_recovery_gates_are_not_conflated(self) -> None:
        self.assertEqual(analyze(sarif())["gate"], "passed")
        for language, required in (("python", ()), ("cpp", CPP_RECOVERY_PATHS)):
            with self.subTest(language=language), self.assertRaises(ValueError):
                analyze_sarif(
                    windows_sarif(),
                    language=language,
                    category=CATEGORY,
                    source_sha=SHA,
                    required_paths=required,
                    require_windows_security=True,
                )

    def test_windows_compiler_and_error_diagnostics_still_fail_closed(self) -> None:
        for source in ("metric", "diagnostic"):
            with self.subTest(source=source):
                data = windows_sarif()
                run = data["runs"][0]
                if source == "metric":
                    run["properties"]["metricResults"].append(
                        {"ruleId": "cpp/telemetry/compiler-errors", "value": 1}
                    )
                else:
                    run["invocations"][0]["toolExecutionNotifications"].append(
                        {
                            "descriptor": {"id": "cpp/diagnostics/extraction-warnings"},
                            "level": "error",
                        }
                    )
                self.assertEqual(analyze_windows(data)["gate"], "failed")

    def test_alert_or_archive_location_does_not_prove_extraction(self) -> None:
        data = sarif()
        data["runs"][0]["invocations"][0]["toolExecutionNotifications"].pop()
        data["runs"][0]["artifacts"] = [{"location": {"uri": CRITICAL}}]
        report = analyze(data)
        self.assertEqual(report["gate"], "failed")
        self.assertEqual(report["missing_required_cpp"], [CRITICAL])

    def test_zero_scan_and_missing_baseline_fail(self) -> None:
        for notes in (
            [],
            [notification("cpp/diagnostics/successfully-extracted-files", CRITICAL)],
        ):
            with self.subTest(notes=notes):
                data = sarif()
                data["runs"][0]["invocations"][0]["toolExecutionNotifications"] = notes
                self.assertEqual(analyze(data)["gate"], "failed")

    def test_failed_or_missing_invocation_is_not_clean(self) -> None:
        for invocations in ([], [{"executionSuccessful": False}]):
            with self.subTest(invocations=invocations), self.assertRaises(ValueError):
                data = sarif()
                data["runs"][0]["invocations"] = invocations
                analyze(data)

    def test_disjoint_or_vendor_only_extraction_is_not_a_first_party_scan(self) -> None:
        for expected, extracted in (
            ("src/a.cpp", "src/b.cpp"),
            ("ext/vendor/a.cpp", "ext/vendor/a.cpp"),
        ):
            with self.subTest(expected=expected, extracted=extracted):
                data = sarif()
                data["runs"][0]["invocations"][0]["toolExecutionNotifications"] = [
                    notification("cli/expected-extracted-files/c", expected),
                    notification(
                        "cpp/diagnostics/successfully-extracted-files", extracted
                    ),
                ]
                self.assertEqual(analyze(data, ())["gate"], "failed")

    def test_diagnostic_descriptor_indices_are_bounded_non_boolean_integers(
        self,
    ) -> None:
        for index in (-1, True, 1, "0", None):
            with self.subTest(index=index), self.assertRaises(ValueError):
                data = sarif()
                run = data["runs"][0]
                run["tool"]["driver"]["notifications"] = [
                    {"id": "cli/expected-extracted-files/c"}
                ]
                run["invocations"][0]["toolExecutionNotifications"][0]["descriptor"] = {
                    "index": index
                }
                analyze(data)

    def test_invalid_diagnostic_level_and_unsupported_component_fail(self) -> None:
        for field in ("level", "component"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                data = sarif()
                run = data["runs"][0]
                note = run["invocations"][0]["toolExecutionNotifications"][0]
                if field == "level":
                    note["level"] = "fatal"
                else:
                    run["tool"]["driver"]["notifications"] = [
                        {"id": "cli/expected-extracted-files/c"}
                    ]
                    note["descriptor"] = {"index": 0, "toolComponent": {"index": 0}}
                analyze(data)

    def test_wrong_source_category_or_tool_fails(self) -> None:
        for field in ("source", "category", "tool"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                data = sarif()
                run = data["runs"][0]
                if field == "source":
                    run["versionControlProvenance"][0]["revisionId"] = "b" * 40
                elif field == "category":
                    run["automationDetails"]["id"] = "/other/"
                else:
                    run["tool"]["driver"]["name"] = "Other tool"
                analyze(data)

    def test_malformed_document_is_rejected(self) -> None:
        for data in (
            None,
            [],
            {},
            {"version": "2.1.0", "runs": []},
            {"version": "2.0.0", "runs": [{}]},
        ):
            with self.subTest(data=data), self.assertRaises(ValueError):
                analyze(data)

    def test_path_traversal_absolute_and_encoded_paths_fail(self) -> None:
        for path in (
            "../outside.cpp",
            "src/%2e%2e/outside.cpp",
            "/tmp/file.cpp",
            "C:/file.cpp",
            "file:///tmp/a.cpp",
            "src\\file.cpp",
            "src/%00file.cpp",
            "src/file.cpp?token=private",
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                repository_path(path)
        self.assertEqual(repository_path("src/a%20b.cpp"), "src/a b.cpp")

    def test_artifact_index_resolves_native_location(self) -> None:
        data = sarif()
        run = data["runs"][0]
        run["artifacts"] = [{"location": {"uri": CRITICAL, "uriBaseId": "%SRCROOT%"}}]
        for note in run["invocations"][0]["toolExecutionNotifications"]:
            note["locations"][0]["physicalLocation"]["artifactLocation"] = {"index": 0}
        self.assertEqual(analyze(data)["gate"], "passed")
        run["artifacts"] = []
        with self.assertRaises(ValueError):
            analyze(data)

    def test_header_gaps_and_vendor_denominators_remain_visible(self) -> None:
        data = sarif()
        notes = data["runs"][0]["invocations"][0]["toolExecutionNotifications"]
        notes.extend(
            [
                notification(
                    "cpp/baseline/expected-extracted-files", "res/mapserver.h"
                ),
                notification(
                    "cpp/baseline/expected-extracted-files", "ext/vendor/file.h"
                ),
            ]
        )
        report = analyze(data)
        self.assertEqual(report["expected_files"], 3)
        self.assertEqual(report["extracted_expected_files"], 1)
        self.assertEqual(report["first_party_expected_files"], 2)
        self.assertEqual(
            report["missing_files"], ["ext/vendor/file.h", "res/mapserver.h"]
        )

    def test_compiler_errors_and_error_diagnostics_block_manual_gate(self) -> None:
        for source in ("metric", "diagnostic"):
            with self.subTest(source=source):
                data = sarif()
                run = data["runs"][0]
                if source == "metric":
                    run["properties"]["metricResults"].append(
                        {"ruleId": "cpp/telemetry/compiler-errors", "value": 3}
                    )
                else:
                    run["invocations"][0]["toolExecutionNotifications"].append(
                        {
                            "descriptor": {"id": "cpp/diagnostics/extraction-warnings"},
                            "level": "error",
                            "message": {"text": "Missing header"},
                        }
                    )
                self.assertEqual(analyze(data)["gate"], "failed")

    def test_quality_warning_is_not_rated_security_low(self) -> None:
        data = sarif()
        run = data["runs"][0]
        run["tool"]["driver"]["rules"] = [
            {"id": "cpp/quality", "defaultConfiguration": {"level": "warning"}}
        ]
        run["tool"]["extensions"] = [
            {
                "rules": [
                    {
                        "id": "cpp/security",
                        "properties": {
                            "security-severity": "9.8",
                            "tags": ["security"],
                        },
                    }
                ]
            }
        ]
        run["results"] = [
            {"ruleId": "cpp/quality"},
            {"rule": {"id": "cpp/security"}, "level": "error"},
        ]
        report = analyze(data)
        by_rule = {item["rule"]: item for item in report["findings"]}
        self.assertEqual(by_rule["cpp/quality"]["kind"], "quality")
        self.assertEqual(by_rule["cpp/quality"]["security_severity"], "unrated")
        self.assertEqual(by_rule["cpp/security"]["security_severity"], "critical")

    def test_unrated_security_and_invalid_numeric_severity_are_not_downgraded(
        self,
    ) -> None:
        data = sarif()
        run = data["runs"][0]
        rule = {"id": "cpp/security", "properties": {"tags": ["security"]}}
        run["tool"]["driver"]["rules"] = [rule]
        run["results"] = [{"ruleId": "cpp/security"}]
        finding = analyze(data)["findings"][0]
        self.assertEqual(
            (finding["kind"], finding["security_severity"]), ("security", "unrated")
        )
        for severity in ("NaN", "Infinity", "invalid", "-1", "11", True, False):
            with self.subTest(severity=severity), self.assertRaises(ValueError):
                rule["properties"]["security-severity"] = severity
                analyze(data)

    def test_full_recovery_requires_every_translation_unit(self) -> None:
        data = sarif()
        notes = data["runs"][0]["invocations"][0]["toolExecutionNotifications"]
        notes[:] = [
            notification(identifier, path)
            for path in CPP_RECOVERY_PATHS
            for identifier in (
                "cpp/baseline/expected-extracted-files",
                "cpp/diagnostics/successfully-extracted-files",
            )
        ]
        self.assertEqual(analyze(data, CPP_RECOVERY_PATHS)["gate"], "passed")
        notes.pop()
        report = analyze(data, CPP_RECOVERY_PATHS)
        self.assertEqual(report["gate"], "failed")
        self.assertEqual(report["missing_required_cpp"], [CPP_RECOVERY_PATHS[-1]])

    def test_python_uses_its_native_diagnostic_prefix(self) -> None:
        data = sarif()
        run = data["runs"][0]
        del run["properties"]
        run["invocations"][0]["toolExecutionNotifications"] = [
            notification("py/baseline/expected-extracted-files", "tools/dbtool.py"),
            notification(
                "py/diagnostics/successfully-extracted-files", "tools/dbtool.py"
            ),
        ]
        report = analyze_sarif(
            data, language="python", category=CATEGORY, source_sha=SHA
        )
        self.assertEqual(report["gate"], "passed")
        self.assertIsNone(report["compiler_errors"])

    def test_modern_cli_baseline_ids_match_the_pinned_action_contract(self) -> None:
        for language, baseline, extracted in (
            ("cpp", "c", "cpp"),
            ("cpp", "cpp", "cpp"),
            ("python", "python", "py"),
        ):
            with self.subTest(language=language):
                data = sarif()
                data["runs"][0]["invocations"][0]["toolExecutionNotifications"] = [
                    notification(f"cli/expected-extracted-files/{baseline}", CRITICAL),
                    notification(
                        f"{extracted}/diagnostics/successfully-extracted-files",
                        CRITICAL,
                    ),
                ]
                report = analyze_sarif(
                    data, language=language, category=CATEGORY, source_sha=SHA
                )
                self.assertEqual(report["gate"], "passed")
                self.assertEqual(report["expected_files"], 1)

    def test_a_different_language_baseline_is_not_coverage(self) -> None:
        data = sarif()
        notes = data["runs"][0]["invocations"][0]["toolExecutionNotifications"]
        notes[0]["descriptor"]["id"] = "cli/expected-extracted-files/python"
        self.assertEqual(analyze(data)["gate"], "failed")

    def test_raw_sarif_may_omit_provenance_but_not_contradict_it(self) -> None:
        data = sarif()
        del data["runs"][0]["versionControlProvenance"]
        self.assertEqual(analyze(data)["gate"], "passed")
        data["runs"][0]["versionControlProvenance"] = []
        with self.assertRaises(ValueError):
            analyze(data)

    def test_checkout_sha_is_verified_independently_of_raw_sarif(self) -> None:
        with patch("tools.mochirii.codeql_coverage.subprocess.run") as execute:
            execute.return_value.stdout = SHA + "\n"
            verify_checkout_sha(SHA)
            self.assertEqual(execute.call_args.args[0], ["git", "rev-parse", "HEAD"])
            self.assertEqual(execute.call_args.kwargs["timeout"], 10)
            execute.return_value.stdout = "b" * 40
            with self.assertRaises(ValueError):
                verify_checkout_sha(SHA)
            with self.assertRaises(ValueError):
                verify_checkout_sha("invalid")

    def test_duplicate_json_and_empty_file_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.sarif"
            for text in ('{"version":"2.1.0","version":"2.0.0"}', "", "not json"):
                with self.subTest(text=text):
                    path.write_text(text)
                    with self.assertRaises(ValueError):
                        load_sarif(path)


if __name__ == "__main__":
    unittest.main()
