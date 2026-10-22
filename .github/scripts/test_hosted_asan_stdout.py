"""Synthetic regression for immutable75ef CTRF stdout serialization.

The producer ctrf_types.h::to_json emits stdout, not output. Exercise the actual
observe_once AST with in-memory report data and owned temporary files only.
No helper import, native executable, Git, database, network or runtime evidence.
"""

from pathlib import Path
import ast
import copy
import hashlib
import json
import os
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

TARGET = Path(__file__).with_name("hosted_asan_sql.py")
TREE = ast.parse(TARGET.read_bytes())


def extracted():
    names = {
        "require",
        "sha",
        "unique_object",
        "normalize_context",
        "check_report",
        "measurement",
        "native_command",
        "native_diagnostics",
        "observe_once",
    }
    constants = {"SOURCE", "NONCE", "RECIPE_SHA", "HEADER_SHA", "FILE", "SUITE", "CASE"}
    namespace = {
        "Path": Path,
        "hashlib": hashlib,
        "json": json,
        "os": os,
        "re": re,
        "SimpleNamespace": SimpleNamespace,
    }
    selected = []
    for node in TREE.body:
        if (
            isinstance(node, ast.Assign)
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in constants
        ):
            namespace[node.targets[0].id] = ast.literal_eval(node.value)
        elif isinstance(node, ast.FunctionDef) and node.name in names:
            selected.append(node)
    if {node.name for node in selected} != names:
        raise AssertionError("Public regression helper contract changed.")
    exec(
        compile(
            ast.Module(body=selected, type_ignores=[]), "synthetic_observe_once", "exec"
        ),
        namespace,
    )
    return namespace


class StdoutObserveControls(unittest.TestCase):
    def setUp(self):
        self.ns = extracted()

    def report(self):
        return {
            "results": {
                "summary": {
                    "tests": 1,
                    "passed": 1,
                    "skipped": 19,
                    "failed": 0,
                    "flaky": 0,
                    "pending": 0,
                    "other": 0,
                },
                "tests": [
                    {
                        "name": self.ns["CASE"],
                        "suite": self.ns["SUITE"],
                        "filePath": self.ns["FILE"],
                        "status": "passed",
                        "flaky": False,
                        "retries": 0,
                        "retryAttempts": [],
                    }
                ],
            }
        }

    def line(self):
        record = {
            "diagnostic_only": True,
            "acceptance": False,
            "query_tag": "load_job_points_first",
            "thread_id": 1,
            "closed": 1,
            "resource_valid": 1,
            "phase_mask": 7,
            "raw_query_bracket_ns": 100,
            "execute_ns": 30,
            "schema_ns": 20,
            "fetch_ns": 40,
            "rows": 1,
            "rows_recorded": 1,
            "user_cpu_ns": 0,
            "system_cpu_ns": 0,
            "voluntary_switches": 0,
            "involuntary_switches": 0,
            "phase_clock_samples": 6,
            "resource_samples": 2,
        }
        return b"MOCHI_SQL_TIMING_V1 " + json.dumps(record).encode() + b"\n"

    def invoke(self, field, *, present=True, legacy=False):
        ns = extracted()
        report = self.report()
        case = report["results"]["tests"][0]
        if present:
            case["stdout"] = field
        if legacy:
            case["output"] = ["legacy field must not substitute for stdout"]
        recipe = {
            "source": ns["SOURCE"],
            "nonce": ns["NONCE"],
            "passed": True,
            "acceptance": False,
            "recipe_sha256": ns["RECIPE_SHA"],
            "header_sha256": ns["HEADER_SHA"],
            "native_proof": {"synthetic": True},
            "database_before": {"synthetic": True},
        }
        console = b"All tests passed (1 assertion in 103 test cases)\n" + self.line()
        writes, runs, frozen = [], [], []
        with tempfile.TemporaryDirectory(dir=TARGET.parent) as temporary:
            base = Path(temporary)
            evidence = base / "evidence"
            evidence.mkdir(mode=0o700)
            ctx = {
                "work": base,
                "evidence": evidence,
                "program": base / "program",
                "controller": base / "diagnostic",
                "env": {"PATH": "/synthetic"},
                "source": ns["SOURCE"],
                "nonce": ns["NONCE"],
                "request_nonce": ns["NONCE"],
                "expected_cpp": 103,
                "expected_executed": 1,
                "expected_filtered": 19,
            }
            ns["validate_context"] = lambda value: None
            ns["verify_frozen"] = lambda *args: frozen.append(args[2])
            ns["database_identity"] = lambda *args: {"synthetic": True}
            ns["evidence_budget"] = lambda *args, **kwargs: {"files": 1, "bytes": 1}
            ns["file_sha"] = lambda path: "0" * 64
            ns["native_env"] = lambda value: {}
            ns["write_json"] = lambda path, value: writes.append(
                (path.name, copy.deepcopy(value))
            )

            def read_file(path, **kwargs):
                values = {
                    "build.receipt.json": json.dumps(recipe).encode(),
                    "one-native-observation.log": console,
                    "report.ctrf.json": json.dumps(report).encode(),
                    "native.log": b"native fixture ready\n",
                }
                return values[path.name]

            ns["read_file"] = read_file

            def run(value, command, label, argv, **kwargs):
                self.assertTrue(
                    any(name == "observation.started.json" for name, _ in writes)
                )
                self.assertEqual(argv, ns["native_command"](value))
                self.assertEqual(label, "one-native-observation")
                runs.append(label)
                (evidence / "native.log").write_bytes(b"native fixture ready\n")
                return {
                    "returncode": 0,
                    "log": evidence / "one-native-observation.log",
                    "stdout": b"",
                }

            ns["run"] = run
            with mock.patch.object(
                Path, "resolve", lambda value: value
            ), mock.patch.dict(os.environ, {"GITHUB_RUN_ID": "1"}):
                outcome = ns["observe_once"](ctx, None)
        self.assertEqual(runs, ["one-native-observation"])
        self.assertEqual(frozen, ["pre-observation", "final-native"])
        self.assertTrue(all(outcome["postflight"].values()))
        self.assertEqual(outcome["native_attempts"], 1)
        self.assertEqual(outcome["native_retries"], 0)
        self.assertFalse(outcome["acceptance"])
        return outcome

    def test_actual_observe_accepts_producer_stdout_without_legacy_output_and_empty_list(
        self,
    ):
        for field in (["[01:02:03][INFO][test:1] ready"], []):
            with self.subTest(empty=not field):
                outcome = self.invoke(field)
                self.assertTrue(outcome["passed"])
                self.assertEqual(
                    (
                        outcome["cpp_cases"],
                        outcome["lua_executed"],
                        outcome["lua_filtered"],
                    ),
                    (103, 1, 19),
                )
                self.assertEqual(
                    outcome["diagnostics"]["unexpected_errors_or_warnings"], 0
                )

    def test_actual_observe_missing_stdout_never_falls_back_to_legacy_output(self):
        for legacy in (False, True):
            outcome = self.invoke(None, present=False, legacy=legacy)
            self.assertFalse(outcome["passed"])
            self.assertEqual(outcome["failure_type"], "KeyError")

    def test_actual_observe_rejects_null_scalar_object_and_mixed_stdout(self):
        for field in (None, "text", True, 1, 1.5, {}, ["valid", 1], [None]):
            with self.subTest(shape=type(field).__name__):
                outcome = self.invoke(field)
                self.assertFalse(outcome["passed"])
                self.assertEqual(outcome["failure_type"], "RuntimeError")

    def test_stdout_seam_preserves_exact_reviewed_sql_warning_boundaries(self):
        function = next(
            node
            for node in TREE.body
            if isinstance(node, ast.FunctionDef) and node.name == "native_diagnostics"
        )
        target = ast.literal_eval(
            next(
                node.value
                for node in function.body
                if isinstance(node, ast.Assign) and node.targets[0].id == "target"
            )
        )
        for duration, accepted in (
            (100, False),
            (101, True),
            (250, True),
            (251, False),
        ):
            outcome = self.invoke(
                [
                    "[01:02:03][WARN][operator():76] SQL query took "
                    + str(duration)
                    + "ms: "
                    + target
                ]
            )
            self.assertEqual(outcome["passed"], accepted)
            if accepted:
                self.assertEqual(
                    len(outcome["diagnostics"]["observed_target_sql_warning_records"]),
                    1,
                )
                self.assertFalse(outcome["diagnostics"]["warning_is_acceptance"])

    def test_stdout_seam_rejects_errors_wrong_emitter_query_and_unexpected_warning(
        self,
    ):
        for line in (
            "[01:02:03][ERROR][operator():76] invalid",
            "[01:02:03][WARN][other():76] invalid",
            "[01:02:03][WARN][operator():76] SQL query took 101ms: SELECT wrong",
            "WARNING: unexpected",
        ):
            outcome = self.invoke([line])
            self.assertFalse(outcome["passed"])
            self.assertEqual(outcome["failure_type"], "RuntimeError")


if __name__ == "__main__":
    unittest.main()
