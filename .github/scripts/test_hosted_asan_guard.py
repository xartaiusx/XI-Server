"""Source-bound synthetic guard regressions; never import the hosted entrypoint."""

import ast
import io
import json
from pathlib import Path
import re
import signal
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch

TARGET = Path(__file__).with_name("hosted_asan_private.py")


def extracted():
    tree = ast.parse(TARGET.read_bytes())
    nodes = [
        node
        for node in tree.body
        if isinstance(node, ast.Assign)
        or isinstance(node, ast.FunctionDef)
        and node.name in {"require", "unique", "encode", "command_runner", "main"}
    ]
    namespace = {
        "json": json,
        "re": re,
        "signal": signal,
        "Path": Path,
        "SimpleNamespace": SimpleNamespace,
    }
    exec(
        compile(ast.Module(body=nodes, type_ignores=[]), "actual_hosted_guard", "exec"),
        namespace,
    )
    return namespace, tree


class GuardControls(unittest.TestCase):
    def setUp(self):
        self.n, self.tree = extracted()

    def runner(
        self,
        *,
        sizes=(1, 1),
        clocks=(100.0, 101.0),
        polls=(None, 0, 0),
        code=0,
        waits=None,
        kill=None,
        label="apt-install"
    ):
        log = Mock()
        samples = iter(sizes)
        trace = []

        def stat_sample():
            trace.append("stat")
            value = next(samples)
            if isinstance(value, BaseException):
                raise value
            return SimpleNamespace(st_size=value)

        log.stat = Mock(side_effect=stat_sample)
        log.read_bytes = Mock(return_value=b"synthetic")
        evidence = MagicMock()
        evidence.__truediv__.return_value = log
        process = Mock(pid=321)
        process.poll.side_effect = list(polls)
        process.wait.return_value = code
        if waits is not None:
            process.wait.side_effect = waits
        fake_os = SimpleNamespace(
            O_WRONLY=1,
            O_CREAT=2,
            O_EXCL=4,
            O_NOFOLLOW=8,
            open=Mock(return_value=7),
            fdopen=Mock(side_effect=lambda *args: io.BytesIO()),
            killpg=Mock(side_effect=kill),
        )
        clock_values = iter(clocks)

        def clock_sample():
            trace.append("clock")
            value = next(clock_values)
            if isinstance(value, BaseException):
                raise value
            return value

        fake_time = SimpleNamespace(
            monotonic=Mock(side_effect=clock_sample),
            sleep=Mock(side_effect=lambda seconds: trace.append(("sleep", seconds))),
        )
        fake_subprocess = SimpleNamespace(
            Popen=Mock(return_value=process),
            DEVNULL=-3,
            STDOUT=-2,
            TimeoutExpired=subprocess.TimeoutExpired,
        )
        self.n.update(os=fake_os, time=fake_time, subprocess=fake_subprocess)
        run = self.n["command_runner"](SimpleNamespace(evidence=evidence, env={}), 123)

        def invoke(**kwargs):
            return run(
                label,
                ["synthetic-program"],
                cwd=Path("/synthetic"),
                timeout=1200,
                **kwargs
            )

        return SimpleNamespace(
            run=run,
            invoke=invoke,
            log=log,
            process=process,
            os=fake_os,
            time=fake_time,
            subprocess=fake_subprocess,
            trace=trace,
        )

    def witness(self, setup):
        self.assertTrue(setup.run.failure_seen)
        self.assertIsInstance(setup.run.failure, bytes)
        self.assertLessEqual(len(setup.run.failure), 4096)
        result = json.loads(setup.run.failure)
        self.assertEqual(result["run_id"], 123)
        self.assertEqual(result["program"], self.n["PROGRAM"])
        self.assertIs(result["diagnostic_only"], True)
        self.assertIs(result["acceptance"], False)
        self.assertIs(result["available"], True)
        self.assertEqual(result["timeout_seconds"], 1200)
        return result

    def test_exact_limit_and_deadline_boundaries_and_original_sleep(self):
        setup = self.runner(
            sizes=(64 * 1024 * 1024, 64 * 1024 * 1024), clocks=(100.0, 1299.999)
        )
        self.assertEqual(setup.invoke()["returncode"], 0)
        self.assertFalse(setup.run.failure_seen)
        self.assertIsNone(setup.run.failure)
        self.assertEqual(setup.time.monotonic.call_count, 2)
        setup.time.sleep.assert_called_once_with(0.2)
        self.assertEqual(setup.log.stat.call_count, 2)
        self.assertEqual(
            setup.trace, ["clock", "stat", "clock", ("sleep", 0.2), "stat"]
        )
        setup.process.wait.assert_called_once_with(timeout=5)
        setup = self.runner(clocks=(100.0, 1300.0), polls=(None, None))
        with self.assertRaises(RuntimeError):
            setup.invoke()
        value = self.witness(setup)
        self.assertEqual(value["guard"], "poll-check")
        self.assertEqual(value["deadline_seconds"], 1300.0)
        self.assertEqual(value["clock_seconds"], 1300.0)
        self.assertIs(value["size_ok"], True)
        self.assertIs(value["time_ok"], False)
        setup.time.sleep.assert_not_called()

    def test_size_failure_short_circuits_clock_and_retains_exact_sample(self):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,), clocks=(100.0,), polls=(None, None)
        )
        with self.assertRaises(RuntimeError):
            setup.invoke()
        value = self.witness(setup)
        self.assertEqual(value["size_bytes"], 64 * 1024 * 1024 + 1)
        self.assertIs(value["size_ok"], False)
        self.assertEqual(value["time_state"], "not_evaluated")
        self.assertIsNone(value["clock_seconds"])
        self.assertIsNone(value["time_ok"])
        self.assertEqual(setup.time.monotonic.call_count, 1)
        self.assertEqual(setup.log.stat.call_count, 1)
        self.assertEqual(setup.trace, ["clock", "stat"])

    def test_stat_and_clock_exceptions_never_invent_a_check_result(self):
        for options, expected in (
            ({"sizes": (OSError("SECRET-MARKER"),), "clocks": (100.0,)}, "poll-stat"),
            ({"clocks": (100.0, OSError("SECRET-MARKER"))}, "poll-clock"),
        ):
            setup = self.runner(polls=(None, None), **options)
            with self.assertRaises(OSError):
                setup.invoke()
            value = self.witness(setup)
            self.assertEqual(value["guard"], expected)
            self.assertIsNone(value["clock_seconds"])
            self.assertIsNone(value["time_ok"])
            self.assertEqual(
                value["time_state"],
                "not_evaluated" if expected == "poll-stat" else "failed",
            )
            self.assertNotIn("SECRET", json.dumps(value))

    def test_first_witness_survives_cleanup_error_clock_advance_and_log_truncation(
        self,
    ):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,), clocks=(100.0,), polls=(None, None)
        )
        captured = []

        def cleanup_failure(*args):
            captured.append(setup.run.failure)
            setup.log.stat.side_effect = lambda: SimpleNamespace(st_size=0)
            setup.time.monotonic.side_effect = lambda: 999999.0
            raise OSError("SECRET-CLEANUP")

        setup.os.killpg.side_effect = cleanup_failure
        with self.assertRaises(OSError):
            setup.invoke()
        self.assertEqual(setup.run.failure, captured[0])
        self.assertEqual(self.witness(setup)["size_bytes"], 64 * 1024 * 1024 + 1)
        self.assertEqual(setup.log.stat.call_count, 1)
        self.assertEqual(setup.time.monotonic.call_count, 1)

    def test_encode_failure_reserves_slot_before_cleanup_failure_and_stays_unavailable(
        self,
    ):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,),
            clocks=(100.0,),
            polls=(None, None),
            kill=OSError("SECRET-CLEANUP"),
        )
        self.n["encode"] = Mock(side_effect=ValueError("SECRET-ENCODE"))
        with self.assertRaises(OSError):
            setup.invoke()
        self.assertTrue(setup.run.failure_seen)
        self.assertIsNone(setup.run.failure)
        self.n["encode"].assert_called_once()
        setup.os.killpg.assert_called_once_with(321, signal.SIGTERM)

    def test_nonfinite_clock_blocks_witness_without_skipping_cleanup(self):
        setup = self.runner(clocks=(100.0, float("nan")), polls=(None, None))
        with self.assertRaises(ValueError):
            setup.invoke()
        self.assertTrue(setup.run.failure_seen)
        self.assertIsNone(setup.run.failure)
        setup.os.killpg.assert_called_once_with(321, signal.SIGTERM)

    def test_original_term5_kill10_cleanup_is_preserved(self):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,),
            clocks=(100.0,),
            polls=(None, None),
            waits=[subprocess.TimeoutExpired("synthetic", 5), 0],
        )
        with self.assertRaises(RuntimeError):
            setup.invoke()
        self.assertEqual(
            [call.args for call in setup.os.killpg.call_args_list],
            [(321, signal.SIGTERM), (321, signal.SIGKILL)],
        )
        self.assertEqual(
            [call.kwargs for call in setup.process.wait.call_args_list],
            [{"timeout": 5}, {"timeout": 10}],
        )
        self.assertEqual(self.witness(setup)["guard"], "poll-check")

    def test_non_guard_failure_does_not_relabel_prior_successful_decision_samples(self):
        setup = self.runner(polls=(None, 0))
        setup.time.sleep.side_effect = OSError("SECRET-SLEEP")
        with self.assertRaises(OSError):
            setup.invoke()
        value = self.witness(setup)
        self.assertEqual(value["guard"], "sleep")
        for key in (
            "size_bytes",
            "size_ok",
            "clock_seconds",
            "deadline_seconds",
            "time_ok",
            "returncode",
        ):
            self.assertIsNone(value[key])
        self.assertEqual(value["time_state"], "not_evaluated")
        self.assertEqual(setup.log.stat.call_count, 1)
        self.assertEqual(setup.time.monotonic.call_count, 2)

    def test_first_encoded_witness_remains_through_subsequent_successful_command(self):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,), clocks=(100.0,), polls=(None, None)
        )
        with self.assertRaises(RuntimeError):
            setup.invoke()
        first = setup.run.failure
        setup.log.stat.side_effect = lambda: SimpleNamespace(st_size=1)
        setup.time.monotonic.side_effect = lambda: 999999.0
        setup.process.poll.side_effect = (0, 0)
        setup.run(
            "apt-update", ["synthetic-program"], cwd=Path("/synthetic"), timeout=1200
        )
        self.assertEqual(setup.run.failure, first)
        self.assertEqual(json.loads(first)["stage"], "apt-install")

    def test_final_size_capture_and_nonzero_checks_remain_mandatory(self):
        for options, expected, kwargs in (
            (
                {"sizes": (64 * 1024 * 1024 + 1,), "clocks": (100.0,), "polls": (0, 0)},
                "final-size",
                {},
            ),
            (
                {"sizes": (1, 1024 * 1024 + 1), "clocks": (100.0,), "polls": (0, 0)},
                "capture-size",
                {"capture": True},
            ),
            (
                {"sizes": (1,), "clocks": (100.0,), "polls": (7, 7), "code": 7},
                "exit-code",
                {},
            ),
        ):
            setup = self.runner(**options)
            with self.assertRaises(RuntimeError):
                setup.invoke(**kwargs)
            value = self.witness(setup)
            self.assertEqual(value["guard"], expected)
            self.assertEqual(
                value["limit_bytes"],
                1024 * 1024 if expected == "capture-size" else 64 * 1024 * 1024,
            )
        setup = self.runner(sizes=(1, 1024 * 1024), clocks=(100.0,), polls=(0, 0))
        self.assertEqual(setup.invoke(capture=True)["stdout"], b"synthetic")
        setup = self.runner(sizes=(1,), clocks=(100.0,), polls=(7, 7), code=7)
        self.assertEqual(setup.invoke(check=False)["returncode"], 7)
        self.assertFalse(setup.run.failure_seen)

    def test_native_log32mib_and_stage_redaction_and_no_extra_command(self):
        setup = self.runner(
            sizes=(32 * 1024 * 1024 + 1,),
            clocks=(100.0,),
            polls=(None, None),
            label="one-native-observation",
        )
        with self.assertRaises(RuntimeError):
            setup.invoke()
        value = self.witness(setup)
        self.assertEqual(value["limit_bytes"], 32 * 1024 * 1024)
        self.assertEqual(value["stage"], "other")
        setup.subprocess.Popen.assert_called_once()
        self.assertNotIn("one-native-observation", json.dumps(value))
        self.assertEqual(
            set(value),
            {
                "schema",
                "program",
                "run_id",
                "diagnostic_only",
                "acceptance",
                "available",
                "stage",
                "guard",
                "timeout_seconds",
                "limit_bytes",
                "size_bytes",
                "size_ok",
                "deadline_seconds",
                "clock_seconds",
                "time_state",
                "time_ok",
                "returncode",
            },
        )

    def test_invalid_run_id_and_nul_argv_fail_before_spawning(self):
        for value in (True, 0, -1, "123", 10**15):
            with self.assertRaises(RuntimeError):
                self.n["command_runner"](SimpleNamespace(), value)
        setup = self.runner()
        with self.assertRaises(RuntimeError):
            setup.run(
                "apt-install", ["SECRET\0MARKER"], cwd=Path("/synthetic"), timeout=1200
            )
        setup.subprocess.Popen.assert_not_called()

    def main_fixture(
        self, *, unavailable=False, encryption_failure=False, witness=None
    ):
        context = {"source_head": "a" * 40, "run_id": 123}
        written = {}
        output = []

        def private_file(path, content):
            written[path.name] = content

        def run(label, argv, **kwargs):
            if label == "encrypt_evidence" and encryption_failure:
                raise RuntimeError("SECRET-ENCRYPTION")
            return {
                "stdout": (
                    (
                        ("a" * 40 if label == "controller_head" else self.n["PROGRAM"])
                        + "\n"
                    ).encode()
                    if label.endswith("_head")
                    else b""
                )
            }

        run.failure_seen = unavailable or witness is not None
        run.failure = witness
        self.n.update(
            os=SimpleNamespace(
                umask=Mock(),
                environ={
                    "GITHUB_WORKSPACE": "/synthetic",
                    "RUNNER_TEMP": "/synthetic/temp",
                    "GITHUB_OUTPUT": "/synthetic/output",
                },
            ),
            sys=SimpleNamespace(platform="linux"),
            __file__="/synthetic/diagnostic/.github/scripts/hosted_asan_private.py",
            public_context=lambda *args: (context, b"public-synthetic-recipient"),
            child_environment=lambda *args: {},
            command_runner=lambda *args: run,
            private_file=private_file,
            regular=Mock(),
            shutil=SimpleNamespace(which=lambda *args: "pwsh"),
            load_builder=lambda *args: SimpleNamespace(
                stage_and_build=lambda *args: {},
                observe_once=lambda *args: {"passed": True},
            ),
            package_evidence=lambda *args: Path("/synthetic/archive"),
            output_ready=Mock(),
            traceback=SimpleNamespace(format_exc=lambda: "synthetic-private-exception"),
            print=output.append,
        )
        with patch.object(Path, "resolve", lambda path, **kwargs: path), patch.object(
            Path, "mkdir", Mock()
        ):
            result = self.n["main"]()
        return result, written, output

    def test_unavailable_witness_forces_failed_result_but_preserves_finalization(self):
        result, written, _ = self.main_fixture(unavailable=True)
        self.assertEqual(result, 1)
        witness = json.loads(written["outcome.json"])["command_failure"]
        self.assertEqual(
            witness,
            {
                "schema": "hosted-command-guard-failure-v1",
                "program": self.n["PROGRAM"],
                "run_id": 123,
                "diagnostic_only": True,
                "acceptance": False,
                "available": False,
            },
        )
        self.n["output_ready"].assert_called_once()

    def test_encryption_failure_never_sets_output_ready_or_emits_plaintext(self):
        result, written, output = self.main_fixture(encryption_failure=True)
        self.assertEqual(result, 1)
        self.n["output_ready"].assert_not_called()
        self.assertIs(json.loads(output[0])["encrypted_evidence_ready"], False)
        self.assertNotIn("SECRET", "".join(output))
        self.assertNotIn("command_failure", json.loads(written["outcome.json"]))

    def test_encoded_witness_is_copied_once_before_failed_encryption_without_rewrite(
        self,
    ):
        setup = self.runner(
            sizes=(64 * 1024 * 1024 + 1,), clocks=(100.0,), polls=(None, None)
        )
        with self.assertRaises(RuntimeError):
            setup.invoke()
        first = setup.run.failure
        result, written, output = self.main_fixture(
            witness=first, encryption_failure=True
        )
        self.assertEqual(result, 1)
        self.assertEqual(
            json.loads(written["outcome.json"])["command_failure"], json.loads(first)
        )
        self.n["output_ready"].assert_not_called()
        self.assertIs(json.loads(output[0])["encrypted_evidence_ready"], False)


if __name__ == "__main__":
    unittest.main()
