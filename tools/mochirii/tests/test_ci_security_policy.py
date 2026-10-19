from __future__ import annotations

import ast
import hashlib
import io
import json
import re
import subprocess
import sys
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main, mock, skipUnless

import yaml

from tools.mochirii.codeql_coverage import (
    COMPILER_ERRORS_METRIC,
    WINDOWS_SECURITY_APIS,
    WINDOWS_SECURITY_METRIC,
)


class CodeScanningCoverageTests(TestCase):
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
                self.assertEqual(entry["runner"], "windows-2022")
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
        native_regressions = steps["Verify native Windows command-policy regressions"]
        self.assertEqual(native_regressions["if"], "matrix.windows_security")
        self.assertIn(
            "result.testsRun != 2 or result.skipped", native_regressions["run"]
        )
        self.assertIn(
            "test_native_windows_command_parser_contract", native_regressions["run"]
        )
        self.assertIn(
            "test_windows_cmake_context_rejects_wrong_compiler_or_standard",
            native_regressions["run"],
        )
        self.assertIn("pyyaml", steps["Install Windows codegen dependencies"]["run"])
        self.assertEqual(
            steps["Setup MSVC"]["uses"],
            "TheMrMilchmann/setup-msvc-dev@368ef7d1ee4d1171b31d4a7f67f4d954f903f5a9",
        )
        self.assertEqual(
            steps["Setup MSVC"]["with"],
            {
                "arch": "x64",
                "vs-path": r"C:\Program Files\Microsoft Visual Studio\2022\Enterprise",
                "toolset": "14.44",
                "sdk": "10.0.26100.0",
            },
        )
        configure = steps["Configure Windows security extraction context"]["run"]
        for flag in (
            "--fresh",
            "-DPCH_ENABLE=OFF",
            "-DCACHE_BINARY:FILEPATH=",
            "-DCMAKE_CXX_COMPILER_LAUNCHER:STRING=",
            "-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded",
            '-DCMAKE_C_COMPILER:FILEPATH="$MOCHIRII_WINDOWS_CL"',
            '-DCMAKE_CXX_COMPILER:FILEPATH="$MOCHIRII_WINDOWS_CL"',
            "-DCMAKE_CXX_FLAGS_INIT:STRING=/Zc:__cplusplus",
            '-DCMAKE_PROJECT_server_INCLUDE:FILEPATH="$GITHUB_WORKSPACE/.github/codeql/windows-msvc-cxx23.cmake"',
            "-DWARNINGS_AS_ERRORS=ON",
        ):
            self.assertIn(flag, configure)
        self.assertNotIn("cmake --build", configure)
        self.assertNotIn("data_schema_generate", configure)
        context = steps["Verify Windows security CMake context"]["run"]
        self.assertIn(
            "PY\ncmake --build build --target enum_codegen --parallel 4", context
        )
        names = [step.get("name") for step in job["steps"]]
        for before, after in (
            ("Setup MSVC", "Verify Windows security toolchain"),
            (
                "Verify Windows security toolchain",
                "Configure Windows security extraction context",
            ),
            (
                "Configure Windows security extraction context",
                "Verify Windows security CMake context",
            ),
            ("Verify Windows security CMake context", "Initialize CodeQL"),
        ):
            self.assertLess(names.index(before), names.index(after))
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

    def _inline_script(self, name: str) -> str:
        step = next(
            step
            for step in self.workflow["jobs"]["analyze"]["steps"]
            if step.get("name") == name
        )
        self.assertEqual(step["if"], "matrix.windows_security")
        return step["run"].split("python - <<'PY'\n", 1)[1].split("\nPY", 1)[0]

    def test_windows_toolchain_preflight_rejects_fallbacks(self) -> None:
        script = self._inline_script("Verify Windows security toolchain")
        environment = {
            "VSINSTALLDIR": "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/",
            "VCToolsVersion": "14.44.35207",
            "WindowsSDKVersion": "10.0.26100.0\\",
        }
        output = "Microsoft (R) C/C++ Optimizing Compiler Version 19.44.35207 for x64\n"
        cases = (
            ({}, output, True, True),
            ({}, output, False, False),
            (
                {
                    "VSINSTALLDIR": "C:/Program Files/Microsoft Visual Studio/18/Enterprise"
                },
                output,
                True,
                False,
            ),
            ({"VCToolsVersion": "14.51.36231"}, output, True, False),
            ({"WindowsSDKVersion": "10.0.22621.0\\"}, output, True, False),
            ({"WindowsSDKVersion": ""}, output, True, False),
            ({}, output.replace("19.44", "19.51"), True, False),
            ({}, output + output.replace("19.44", "19.51"), True, False),
            ({}, output.replace("x64", "ARM64"), True, False),
            ({}, output + output.replace("x64", "x86"), True, False),
            ({}, "clang version 20.1.8\n", True, False),
            ({"CL": "/std:c++latest"}, output, True, False),
            ({"_CL_": "/WX-"}, output, True, False),
            (
                {},
                output + "command line warning D9002: ignoring unknown option\n",
                True,
                False,
            ),
            (
                {},
                output + "command line warning D9025: overriding option\n",
                True,
                False,
            ),
            ({}, output + "x" * 32768, True, False),
        )
        with TemporaryDirectory() as temporary:
            environment["GITHUB_ENV"] = str(Path(temporary) / "environment")
            self._check_msvc_preflight_cases(script, environment, cases)

    def _check_msvc_preflight_cases(self, script, environment, cases) -> None:
        compiler = "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe"
        for changed, version, exists, accepted in cases:
            with self.subTest(
                changed=changed, exists=exists, accepted=accepted
            ), mock.patch.dict(
                "os.environ", environment | changed, clear=True
            ), mock.patch(
                "pathlib.Path.is_file", return_value=exists
            ), mock.patch(
                "subprocess.run",
                return_value=mock.Mock(stdout=version, stderr=""),
            ) as run, redirect_stdout(
                io.StringIO()
            ):
                if accepted:
                    exec(compile(script, "<toolchain-preflight>", "exec"), {})
                    self.assertEqual(run.call_args.kwargs["timeout"], 15)
                    self.assertTrue(run.call_args.kwargs["check"])
                    run.assert_called_once()
                    arguments = run.call_args.args[0]
                    self.assertEqual(arguments[0], str(Path(compiler)))
                    self.assertEqual(
                        arguments[1:-1],
                        [
                            "/Bv",
                            "/Zs",
                            "/TP",
                            "/std:c++23preview",
                            "/permissive-",
                            "/Zc:__cplusplus",
                            "/W4",
                            "/WX",
                        ],
                    )
                    self.assertFalse(Path(arguments[-1]).exists())
                    self.assertEqual(
                        Path(environment["GITHUB_ENV"]).read_text(),
                        f"MOCHIRII_WINDOWS_CL={compiler}\n",
                    )
                else:
                    with self.assertRaises(SystemExit):
                        exec(compile(script, "<toolchain-preflight>", "exec"), {})

    @skipUnless(sys.platform == "win32", "Actual Windows command-line API contract")
    def test_windows_cmake_context_rejects_wrong_compiler_or_standard(self) -> None:
        script = self._inline_script("Verify Windows security CMake context")
        values = {
            "COMPILER_ID": "MSVC",
            "COMPILER_VERSION": "19.44.35207",
            "COMPILER_FRONTEND_VARIANT": "MSVC",
            "SIMULATE_ID": "",
        }
        compiler = "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe"
        native = ["/W4", "/WX", "/permissive-", "/Zc:__cplusplus", "/std:c++23preview"]
        cases = (
            ({}, native, "src", True),
            ({}, ["/W3", *native], "src", True),
            (
                {"COMPILER": "C:/other/clang-cl.exe"},
                native,
                "src",
                False,
            ),
            ({"COMPILER_ID": "Clang"}, native, "src", False),
            ({"COMPILER_VERSION": "19.51.36260"}, native, "src", False),
            ({"COMPILER_FRONTEND_VARIANT": "GNU"}, native, "src", False),
            ({"SIMULATE_ID": "MSVC"}, native, "src", False),
            ({"SIMULATE_ID": "GNU"}, native, "src", False),
            ({"TARGET": "ARM64"}, native, "src", False),
            ({"TARGET": None}, native, "src", False),
            ({"C_VERSION": "19.44.35219"}, native, "src", False),
            ({}, native[:-1] + ["/std:c++20"], "src", False),
            ({}, native[:-1] + ["-clang:-std=c++23"], "src", False),
            ({}, native[:-1] + ["-std:c++latest"], "src", False),
            ({}, native[:-1] + ["-std=c++26"], "src", False),
            ({}, [], "src", False),
            ({}, native + ["-clang:-std=c++23"], "src", False),
            ({}, native + ["-std=c++23"], "src", False),
            ({}, native + ["/std:c++latest"], "src", False),
            ({}, native[1:], "src", False),
            ({}, [native[0], *native[2:]], "src", False),
            ({}, native + ["/WX-"], "src", False),
            ({}, native + ['/W"X-"'], "src", False),
            ({}, native + ['/per"missive"'], "src", False),
            ({}, native + ['/st"d":c++20'], "src", False),
            ({}, native + ["/W0"], "src", False),
            ({}, native + ["/W3"], "src", False),
            ({}, ["/W2", *native], "src", False),
            ({}, ["/W3", "/W3", *native], "src", False),
            ({}, [arg for arg in native if arg != "/Zc:__cplusplus"], "src", False),
            ({}, native + ["/Zc:__cplusplus"], "src", True),
            ({}, native + ["-Zc:__cplusplus"], "src", True),
            ({}, native + ['"/Zc:__cplusplus"'], "src", True),
            ({}, native + ['"/IC:/Program Files/Headers"'], "src", True),
            ({}, native + ["/IC:/O'Connor/Headers"], "src", True),
            ({}, native + ["/Zc:__cplusplus-"], "src", False),
            ({}, native + ["/Zc:twoPhase-"], "src", False),
            ({}, native + ["/Zc:preprocessor,twoPhase-"], "src", False),
            ({}, native + ["/Zc:twoPhase-,preprocessor"], "src", False),
            ({}, ["-Zc:preprocessor,twoPhase-", *native], "src", False),
            ({}, native + ['"/Zc:preprocessor,"twoPhase-'], "src", False),
            ({}, native + ["/permissive"], "src", False),
            ({}, [arg for arg in native if arg != "/permissive-"], "src", False),
            ({}, native + ["/U__STDC__"], "src", False),
            ({}, native + ["-U", "__STDC__"], "src", False),
            ({}, native + ["-D__STDC__=0"], "src", False),
            ({}, native + ["/D__cplusplus=202302L"], "src", False),
            ({}, native + ['"-D_MSVC_LANG=202302L"'], "src", False),
            ({}, native + ["-D_MSC_VER=1944"], "src", False),
            ({}, native + ["/D_MSC_FULL_VER=194435207"], "src", False),
            ({}, native + ["/D_M_X64=100"], "src", False),
            ({}, native + ["-D__clang_major__=20"], "src", False),
            ({}, native + ["-D__cpp_lib_expected=202202L"], "src", False),
            ({}, native + ["-D", "_MSC_VER=1944"], "src", False),
            ({"FLAGS": ""}, native, "src", False),
            (
                {"FLAGS": '/GR /EHsc /Zc:__cplusplus "/IC:/Program Files/Headers"'},
                native,
                "src",
                True,
            ),
            (
                {"FLAGS": "/GR /EHsc /Zc:__cplusplus /IC:/O'Connor/Headers"},
                native,
                "src",
                True,
            ),
            (
                {"FLAGS": "/Zc:__cplusplus /Zc:__cplusplus"},
                native,
                "src",
                False,
            ),
            ({"FLAGS": "/Zc:__cplusplus /D__cplusplus=202302L"}, native, "src", False),
            ({"DEPENDENCY": True}, native, "src", False),
            (
                {
                    "DEPENDENCY": True,
                    "DEPENDENCY_FLAGS": [
                        "/Zc:__cplusplus",
                        "/std:c++14",
                        "/Zc:__cplusplus",
                        '"/IC:/Program Files/Headers"',
                        "/IC:/O'Connor/Headers",
                    ],
                },
                native,
                "src",
                True,
            ),
            (
                {
                    "DEPENDENCY": True,
                    "DEPENDENCY_COMPILER": "C:/other/cl.exe",
                    "DEPENDENCY_FLAGS": ["/Zc:__cplusplus"],
                },
                native,
                "src",
                False,
            ),
            (
                {
                    "DEPENDENCY": True,
                    "DEPENDENCY_FLAGS": ["/Zc:__cplusplus", "/D__cplusplus=202302L"],
                },
                native,
                "src",
                False,
            ),
            ({}, native, "ext", False),
        )
        invalid_reporting = (
            "/Zc:__cplusplus-",
            "-Zc:__cplusplus-",
            "/zc:__cplusplus-",
            "-ZC:__cplusplus-",
            "/zc:__cplusplus",
            "/Zc:__CPLUSPLUS",
            "/Zc:__cplusplus=1",
            "/Zc:__cplusplus+",
            "/Zc:preprocessor,__cplusplus-",
            "/Zc:__cplusplus-,preprocessor",
            "/Zc:preprocessor,__cplusplus",
            '/Zc:__cplus"plus"-',
            '/Z"c":__cplusplus-',
            '/Zc:"__cplusplus-"',
            '"/Zc:"__cplusplus-',
            '"-Zc:"__cplusplus-',
            '"/Z"c:__cplusplus-',
            '"/"Zc:__cplusplus-',
            '""/Zc:__cplusplus-',
            '"/Zc:preprocessor,"__cplusplus-',
            '"/Zc:pre"processor,__cplusplus-',
            "/I 'a /Zc:__cplusplus- /I b'",
            "/I 'a -Zc:__cplusplus- /I b'",
            r'/I "a\" " /Zc:__cplusplus- /I "b"',
            "@uninspected.rsp",
            "/link /WX-",
            '/D__cplus"plus"=202302L',
        )
        cases += tuple(
            ({}, arguments, "src", False)
            for flag in invalid_reporting
            for arguments in ([flag, *native], [*native, flag])
        )
        cases += tuple(
            (
                {"DEPENDENCY": True, "DEPENDENCY_FLAGS": arguments},
                native,
                "src",
                False,
            )
            for flag in invalid_reporting
            for arguments in ([flag, "/Zc:__cplusplus"], ["/Zc:__cplusplus", flag])
        )
        cases += tuple(
            ({"FLAGS": f"/Zc:__cplusplus {flag}"}, native, "src", False)
            for flag in invalid_reporting
        )
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root / "build"
            compiler_context = build / "CMakeFiles/3.31.6"
            compiler_context.mkdir(parents=True)
            for changed, standards, folder, accepted in cases:
                with self.subTest(changed=changed, standards=standards, folder=folder):
                    for language in ("C", "CXX"):
                        (
                            compiler_context / f"CMake{language}Compiler.cmake"
                        ).write_text(
                            "\n".join(
                                f'set(CMAKE_{language}_{key} "{value}")'
                                for key, value in (
                                    {"COMPILER": compiler}
                                    | values
                                    | changed
                                    | (
                                        {"COMPILER_VERSION": changed["C_VERSION"]}
                                        if language == "C" and "C_VERSION" in changed
                                        else {}
                                    )
                                ).items()
                                if key
                                not in {
                                    "TARGET",
                                    "FLAGS",
                                    "DEPENDENCY",
                                    "DEPENDENCY_FLAGS",
                                    "DEPENDENCY_COMPILER",
                                    "C_VERSION",
                                }
                            )
                            + (
                                f'\nset(MSVC_{language}_ARCHITECTURE_ID {changed.get("TARGET", "x64")})'
                                if changed.get("TARGET", "x64") is not None
                                else ""
                            )
                        )
                    (build / "CMakeCache.txt").write_text(
                        f"CMAKE_CXX_FLAGS:STRING={changed.get('FLAGS', '/GR /EHsc /Zc:__cplusplus')}\n"
                    )
                    (build / "compile_commands.json").write_text(
                        json.dumps(
                            [
                                {
                                    "file": str(root / folder / "sample.cpp"),
                                    "command": f'"{compiler}" ' + " ".join(standards),
                                }
                            ]
                            + (
                                [
                                    {
                                        "file": str(build / "_deps/library.cpp"),
                                        "command": f'"{changed.get("DEPENDENCY_COMPILER", compiler)}" '
                                        + " ".join(
                                            changed.get(
                                                "DEPENDENCY_FLAGS",
                                                ["/std:c++23preview"],
                                            )
                                        ),
                                    }
                                ]
                                if changed.get("DEPENDENCY")
                                else []
                            )
                        )
                    )
                    processes = []

                    def start(arguments, **_kwargs):
                        negative = "/std:c++20" in arguments
                        child = mock.Mock()
                        child.stdout.read.return_value = (
                            b"error C2039: 'expected': is not a member of 'std'\n"
                            if negative
                            else b""
                        )
                        child.wait.return_value = 1 if negative else 0
                        child.poll.return_value = 1 if negative else 0
                        processes.append(child)
                        return child

                    with mock.patch.dict(
                        "os.environ", {"VCToolsVersion": "14.44.35207"}
                    ), mock.patch("pathlib.Path.cwd", return_value=root), mock.patch(
                        "subprocess.Popen", side_effect=start
                    ) as popen, mock.patch(
                        "threading.Timer"
                    ) as timer, redirect_stdout(
                        io.StringIO()
                    ):
                        timer.return_value.is_alive.return_value = False
                        if accepted:
                            exec(compile(script, "<cmake-context>", "exec"), {})
                            self.assertEqual(popen.call_count, 2)
                            for index, call in enumerate(popen.call_args_list):
                                arguments = call.args[0]
                                expected = [
                                    compiler,
                                    "/nologo",
                                    "/std:c++23preview" if index == 0 else "/std:c++20",
                                    "/W4",
                                    "/WX",
                                    "/permissive-",
                                    "/Zc:__cplusplus",
                                    "/EHsc",
                                    "/Zs",
                                    "/I",
                                    str(root / "src"),
                                ]
                                self.assertEqual(arguments[:-1], expected)
                                self.assertFalse(Path(arguments[-1]).exists())
                                self.assertEqual(
                                    call.kwargs,
                                    {
                                        "stdin": subprocess.DEVNULL,
                                        "stdout": subprocess.PIPE,
                                        "stderr": subprocess.STDOUT,
                                    },
                                )
                                processes[index].stdout.read.assert_called_once_with(
                                    32769
                                )
                                processes[index].wait.assert_called_once_with(timeout=5)
                                processes[index].stdout.close.assert_called_once()
                                processes[index].kill.assert_not_called()
                                timer_call = timer.call_args_list[index].args
                                self.assertEqual(timer_call[0], 30)
                                self.assertEqual(
                                    timer_call[1].__defaults__[0], processes[index]
                                )
                                self.assertFalse(timer_call[1].__defaults__[1].is_set())
                                self.assertEqual(
                                    timer.return_value.join.call_args_list[
                                        index
                                    ].kwargs,
                                    {"timeout": 5},
                                )
                            self.assertEqual(timer.return_value.start.call_count, 2)
                            self.assertEqual(timer.return_value.cancel.call_count, 4)
                            for failure in (
                                "spawn",
                                "timer_init",
                                "timer_start",
                                "deadline",
                                "positive-deadline-exit0",
                                "negative-deadline-exit1",
                                "timer-still-running",
                                "exit",
                                "overflow",
                                "timeout",
                                "ignored",
                                "override",
                                "warning",
                                "negative-pass",
                                "negative-wrong-error",
                                "negative-driver",
                            ):
                                processes.clear()
                                popen.reset_mock()
                                timer.reset_mock()
                                timer.side_effect = None
                                timer.return_value.start.side_effect = None
                                timer.return_value.is_alive.return_value = False

                                def fail(arguments, **kwargs):
                                    if failure == "spawn":
                                        raise OSError(
                                            "synthetic compiler launch failure"
                                        )
                                    child = start(arguments, **kwargs)
                                    if failure in {
                                        "timer_init",
                                        "timer_start",
                                        "overflow",
                                        "timeout",
                                    }:
                                        child.poll.return_value = None
                                    if failure == "exit":
                                        child.wait.return_value = 1
                                    if failure == "overflow":
                                        child.stdout.read.return_value = b"x" * 32769
                                    if failure == "timeout":
                                        child.wait.side_effect = [
                                            subprocess.TimeoutExpired(arguments, 5),
                                            0,
                                        ]
                                    if failure == "ignored":
                                        child.stdout.read.return_value = b"command line warning D9002: ignoring unknown option\n"
                                    if failure == "override":
                                        child.stdout.read.return_value = b"command line warning D9025: overriding option\n"
                                    if failure == "warning":
                                        child.stdout.read.return_value = (
                                            b"warning C4996: deprecated function\n"
                                        )
                                    if "/std:c++20" in arguments:
                                        if failure == "negative-pass":
                                            child.wait.return_value = 0
                                            child.poll.return_value = 0
                                        if failure == "negative-wrong-error":
                                            child.stdout.read.return_value = b"error C1083: Cannot open source file\n"
                                        if failure == "negative-driver":
                                            child.stdout.read.return_value += b"command line warning D9002: ignoring unknown option\n"
                                    return child

                                popen.side_effect = fail
                                if failure == "timer_init":
                                    timer.side_effect = RuntimeError(
                                        "synthetic timer failure"
                                    )
                                if failure == "timer_start":
                                    timer.return_value.start.side_effect = RuntimeError(
                                        "synthetic timer start failure"
                                    )
                                if failure == "deadline":

                                    def expire():
                                        timer.call_args.args[1]()
                                        processes[-1].wait.return_value = -9
                                        processes[-1].poll.return_value = -9

                                    timer.return_value.start.side_effect = expire
                                if failure in {
                                    "positive-deadline-exit0",
                                    "negative-deadline-exit1",
                                }:

                                    def expire_normal_exit():
                                        if (failure == "positive-deadline-exit0") == (
                                            len(processes) == 1
                                        ):
                                            timer.call_args.args[1]()

                                    timer.return_value.start.side_effect = (
                                        expire_normal_exit
                                    )
                                if failure == "timer-still-running":
                                    timer.return_value.is_alive.return_value = True
                                exception = (
                                    OSError
                                    if failure == "spawn"
                                    else (
                                        RuntimeError
                                        if failure.startswith("timer_")
                                        else (
                                            subprocess.TimeoutExpired
                                            if failure == "timeout"
                                            else SystemExit
                                        )
                                    )
                                )
                                with self.subTest(failure=failure), self.assertRaises(
                                    exception
                                ):
                                    exec(compile(script, "<cmake-context>", "exec"), {})
                                for child in processes:
                                    child.stdout.close.assert_called_once()
                                if failure in {
                                    "timer_init",
                                    "timer_start",
                                    "deadline",
                                    "positive-deadline-exit0",
                                    "overflow",
                                    "timeout",
                                }:
                                    processes[0].kill.assert_called_once()
                                    self.assertEqual(
                                        processes[0].wait.call_args.kwargs,
                                        {"timeout": 5},
                                    )
                                if failure == "negative-deadline-exit1":
                                    self.assertEqual(len(processes), 2)
                                    processes[0].kill.assert_not_called()
                                    processes[1].kill.assert_called_once()
                                    self.assertIn(
                                        b"expected",
                                        processes[1].stdout.read.return_value,
                                    )
                                    self.assertEqual(processes[1].wait.return_value, 1)
                        else:
                            with self.assertRaises(SystemExit):
                                exec(compile(script, "<cmake-context>", "exec"), {})
                            popen.assert_not_called()
            (compiler_context / "CMakeCCompiler.cmake").unlink()
            with mock.patch.dict(
                "os.environ", {"VCToolsVersion": "14.44.35207"}
            ), mock.patch("pathlib.Path.cwd", return_value=root), self.assertRaises(
                SystemExit
            ):
                exec(compile(script, "<cmake-context>", "exec"), {})

    @skipUnless(sys.platform == "win32", "Actual Windows command-line API contract")
    def test_native_windows_command_parser_contract(self) -> None:
        import ctypes

        tree = ast.parse(self._inline_script("Verify Windows security CMake context"))
        bindings = {"shell32", "kernel32", "parse_argv", "free_argv"}
        selected = []
        for node in tree.body:
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                selected.append(node)
            elif isinstance(node, ast.FunctionDef) and node.name == "command_tokens":
                selected.append(node)
            elif isinstance(node, ast.Assign):
                target = node.targets[0]
                if (
                    isinstance(target, ast.Name)
                    and target.id in bindings
                    or isinstance(target, ast.Attribute)
                    and isinstance(target.value, ast.Name)
                    and target.value.id in bindings
                ):
                    selected.append(node)
        scope = {}
        exec(
            compile(
                ast.Module(body=selected, type_ignores=[]), "<native-parser>", "exec"
            ),
            scope,
        )
        parse = scope["command_tokens"]
        vectors = (
            "/Zc:__cplusplus /Zc:__cplusplus",
            '/I "C:/Program Files/O\'Connor/Headers" /WX',
            "/I 'a /Zc:__cplusplus- /I b'",
            '"/Zc:"__cplusplus-',
            r'/I "a\" " /Zc:__cplusplus- /I "b"',
        )
        for tail in vectors:
            with self.subTest(tail=tail):
                delivered = subprocess.run(
                    f'"{sys.executable}" -c "import json,sys;print(json.dumps(sys.argv[1:]))" {tail}',
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertLessEqual(len(delivered.stdout), 4096)
                self.assertEqual(
                    parse("cl.exe " + tail)[1:], json.loads(delivered.stdout)
                )
                self.assertEqual(delivered.stderr, "")
        for command in (
            "",
            "cl.exe\x00 /WX",
            "cl.exe\n /WX",
            'cl.exe "" /WX',
            'cl.exe "unmatched',
            "cl.exe " + "a" * 32767,
            "cl.exe @hidden.rsp",
            "cl.exe /link /WX",
        ):
            with self.subTest(command=command[:80]), self.assertRaises(SystemExit):
                parse(command)
        original_parse, original_free = scope["parse_argv"], scope["free_argv"]
        observed_free = mock.Mock(wraps=original_free)
        scope["free_argv"] = observed_free
        self.assertEqual(parse("cl.exe /WX"), ["cl.exe", "/WX"])
        observed_free.assert_called_once()
        scope["free_argv"] = original_free
        allocation = (ctypes.c_wchar_p * 1)("cl.exe")
        for count, entry, free_result in (
            (0, "cl.exe", None),
            (32767, "cl.exe", None),
            (1, None, None),
            (1, "cl.exe", 1),
        ):
            allocation[0] = entry

            def fake_parse(_command, out_count):
                ctypes.cast(out_count, ctypes.POINTER(ctypes.c_int)).contents.value = (
                    count
                )
                return allocation

            free = mock.Mock(return_value=free_result)
            scope["parse_argv"], scope["free_argv"] = fake_parse, free
            with self.subTest(
                count=count, entry=entry, free_result=free_result
            ), self.assertRaises(SystemExit):
                parse("cl.exe")
            free.assert_called_once()
        scope["parse_argv"], scope["free_argv"] = (
            mock.Mock(return_value=None),
            mock.Mock(),
        )
        with self.assertRaises(SystemExit):
            parse("cl.exe")
        scope["free_argv"].assert_not_called()
        scope["parse_argv"], scope["free_argv"] = original_parse, original_free

    def test_windows_native_frontend_proves_exact_cxx23_and_abi(self) -> None:
        steps = self.workflow["jobs"]["analyze"]["steps"]
        configure = next(
            step["run"]
            for step in steps
            if step.get("name") == "Configure Windows security extraction context"
        )
        context = self._inline_script("Verify Windows security CMake context")
        for proof in (
            "__cplusplus == 202302L",
            "_MSVC_LANG == 202302L",
            "_MSC_VER == 1944",
            "_MSC_FULL_VER == @MSC_FULL_VER@",
            "_M_X64 == 100 && _WIN32 && _WIN64",
            "defined(__clang__)",
            "sizeof(void*) == 8 && sizeof(long) == 4",
            "std::is_same_v<off_t, _off_t>",
            "#ifdef __STDC__",
            "static_assert(not false and true)",
            "static_assert(definition_lookup(0) == 1)",
            "template <> struct tuple_size<Binding> {};",
            "static_assert(sizeof(std::tuple_size<Binding>) > 0)",
            "static_assert(bind_aggregate() == 2386)",
            "operator==(const Comparison&) const = default",
            "std::expected<int, int>",
            "std::optional<int>",
            "std::span<const int>",
            "std::string_view",
        ):
            self.assertIn(proof, context)
        self.assertIn("CMAKE_PROJECT_server_INCLUDE", configure)
        self.assertNotIn("CMAKE_PROJECT_INCLUDE:", configure)
        self.assertNotIn("clang-cl", configure)
        self.assertNotIn("/std:", configure)
        self.assertIn('("/std:c++20", negative, False)', context)
        self.assertNotIn('/Zc:twoPhase"', context)
        warnings = (self.repo / "cmake/CompilerWarnings.cmake").read_text()
        self.assertIn('set(ERRORS "-Werror")', warnings)
        self.assertIn('set(ERRORS "/WX")', warnings)

    def test_windows_does_not_inherit_clang_extractor_workarounds(self) -> None:
        job = self.workflow["jobs"]["analyze"]
        name = "CODEQL_EXTRACTOR_CPP_OPTION_FRONTEND_OPTIONS"
        self.assertNotIn(name, job["env"])
        steps = job["steps"]
        contexts = [
            (index, step)
            for index, step in enumerate(steps)
            if name in json.dumps(step)
        ]
        self.assertEqual(len(contexts), 1)
        index, step = contexts[0]
        self.assertEqual(step["if"], "matrix.windows_security")
        self.assertEqual(
            step["run"], f"printf '%s\\n' '{name}=--ms_c++23' >> \"$GITHUB_ENV\""
        )
        names = [step.get("name") for step in steps]
        self.assertLess(names.index("Verify Windows security CMake context"), index)
        self.assertLess(index, names.index("Initialize CodeQL"))
        for obsolete in ("--alternative_tokens", "--dep_name", "-U__STDC__"):
            self.assertNotIn(obsolete, json.dumps(job))

    def test_windows_cxx23_hook_is_scoped_and_fails_closed(self) -> None:
        hook = self.repo / ".github/codeql/windows-msvc-cxx23.cmake"
        values = {
            "PROJECT_NAME": "server",
            "CMAKE_CXX_COMPILER_ID": "MSVC",
            "CMAKE_CXX_COMPILER_VERSION": "19.44.35207",
            "MSVC_CXX_ARCHITECTURE_ID": "x64",
            "CMAKE_CXX23_STANDARD_COMPILE_OPTION": "-std:c++latest",
            "CMAKE_CXX23_EXTENSION_COMPILE_OPTION": "-std:c++latest",
        }
        cases = [({}, True)] + [
            ({key: value}, False)
            for key, value in (
                ("PROJECT_NAME", "dependency"),
                ("CMAKE_CXX_COMPILER_ID", "Clang"),
                ("CMAKE_CXX_COMPILER_VERSION", "19.51.36260"),
                ("MSVC_CXX_ARCHITECTURE_ID", "ARM64"),
                ("CMAKE_CXX23_STANDARD_COMPILE_OPTION", "/std:c++20"),
                ("CMAKE_CXX23_EXTENSION_COMPILE_OPTION", "-std:c++latest;-DFAKE"),
                ("CMAKE_CXX23_STANDARD_COMPILE_OPTION", ""),
            )
        ]
        with TemporaryDirectory() as temporary:
            script = Path(temporary) / "standard.cmake"
            for changed, accepted in cases:
                with self.subTest(changed=changed):
                    script.write_text(
                        "\n".join(
                            f'set({key} "{value}")'
                            for key, value in (values | changed).items()
                        )
                        + f'\ninclude("{hook.as_posix()}")\n'
                        + "foreach(option CMAKE_CXX23_STANDARD_COMPILE_OPTION CMAKE_CXX23_EXTENSION_COMPILE_OPTION)\n"
                        + 'if(NOT "${${option}}" STREQUAL "/std:c++23preview")\n'
                        + 'message(FATAL_ERROR "C++23 mode was not exact")\nendif()\nendforeach()\n'
                    )
                    result = subprocess.run(
                        ["cmake", "-P", str(script)],
                        capture_output=True,
                        text=True,
                        timeout=30,
                        check=False,
                    )
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)
        source = (self.repo / "CMakeLists.txt").read_text()
        self.assertIn("set(CMAKE_CXX_STANDARD 23)", source)
        self.assertIn("set(CMAKE_CXX_STANDARD_REQUIRED ON)", source)
        self.assertIn("set(CMAKE_CXX_EXTENSIONS OFF)", source)

    def test_windows_system_libraries_follow_platform_not_driver(self) -> None:
        settings = (self.repo / "cmake/StandardProjectSettings.cmake").read_text()
        block = re.search(
            r"if\(WIN32\)\s+link_libraries\((.*?)\)\s+endif\(\)",
            settings,
            re.DOTALL,
        )
        self.assertIsNotNone(block)
        libraries = "ws2_32;dbghelp;winmm;shlwapi;shell32;user32"
        with TemporaryDirectory() as temporary:
            probe = Path(temporary) / "platform.cmake"
            for windows, msvc, expected in (
                ("TRUE", "TRUE", libraries),
                ("TRUE", "FALSE", libraries),
                ("FALSE", "FALSE", ""),
            ):
                with self.subTest(windows=windows, msvc=msvc):
                    probe.write_text(
                        f"set(WIN32 {windows})\nset(MSVC {msvc})\n"
                        "set(actual)\nmacro(link_libraries)\n"
                        'set(actual "${ARGV}")\nendmacro()\n'
                        + block[0]
                        + f'\nif(NOT "${{actual}}" STREQUAL "{expected}")\n'
                        'message(FATAL_ERROR "Unexpected platform libraries")\n'
                        "endif()\n"
                    )
                    result = subprocess.run(
                        ["cmake", "-P", str(probe)],
                        capture_output=True,
                        text=True,
                        timeout=30,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_case_insensitive_aliases_follow_crt_declarations(self) -> None:
        header = (self.repo / "src/common/macros.h").read_text()
        self.assertLess(
            header.index("#include <cstring>"), header.index("#define strcmpi")
        )
        self.assertIn(
            """#if defined(_MSC_VER)
#define strcmpi _stricmp
#define stricmp _stricmp
#else
#define strcmpi strcasecmp
#define stricmp strcasecmp
#endif""",
            header,
        )
        script = self._inline_script("Verify Windows security CMake context")
        probes = [
            node
            for node in ast.walk(ast.parse(script))
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "write_text"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "probe"
        ]
        self.assertEqual(len(probes), 1)
        value = probes[0].args[0]
        self.assertIsInstance(value, ast.Call)
        self.assertEqual(value.func.attr, "replace")
        source = ast.literal_eval(value.func.value)
        self.assertTrue(source.startswith('#include "common/macros.h"\n'))
        self.assertIn("static_assert(&strcmpi == &_stricmp);", source)
        self.assertIn("static_assert(&stricmp == &_stricmp);", source)
        self.assertNotIn("_CRT_NONSTDC_NO_DEPRECATE", source + header)

    def test_vendor_flags_are_real_msvc_only_without_warning_weakening(self) -> None:
        settings = (self.repo / "cmake/StandardProjectSettings.cmake").read_text()
        self.assertEqual(settings.count("/MP"), 1)
        self.assertIn("$<$<CXX_COMPILER_ID:MSVC>:/MP>", settings)
        glaze = (self.repo / "ext/CMakeLists.txt").read_text()
        for flag in ("/Zc:preprocessor", "/permissive-", "/Zc:lambda"):
            self.assertEqual(
                glaze.count(f"$<$<COMPILE_LANG_AND_ID:CXX,MSVC>:{flag}>"), 1
            )
        self.assertNotIn("Qunused-arguments", settings + glaze)
        warnings = (self.repo / "cmake/CompilerWarnings.cmake").read_text()
        self.assertIn(
            'option(WARNINGS_AS_ERRORS "Treat compiler warnings as errors" TRUE)',
            warnings,
        )
        self.assertIn('set(ERRORS "/WX")', warnings)

    def test_fmt_uses_the_normal_library_not_an_unused_module_target(self) -> None:
        facade = (self.repo / "ext/CMakeLists.txt").read_text()
        package = re.search(r"CPMAddPackage\(\s+NAME fmt\s.*?\n\)", facade, re.DOTALL)
        self.assertIsNotNone(package)
        self.assertIn("GIT_TAG 12.2.0", package[0])
        self.assertIn('OPTIONS "FMT_MODULE OFF"', package[0])
        self.assertIn(
            "set(CMAKE_CXX_SCAN_FOR_MODULES OFF)",
            (self.repo / "CMakeLists.txt").read_text(),
        )
        common = (self.repo / "src/common/CMakeLists.txt").read_text()
        shared = re.search(r"set\(\s*SHARED_EXTERNAL_LIBS\s.*?\n\)", facade, re.DOTALL)
        self.assertIsNotNone(shared)
        self.assertIn("fmt::fmt", shared[0])
        self.assertIn("${SHARED_EXTERNAL_LIBS}", common)

    def test_pinned_watcher_failure_patch_owns_its_cache_and_cleanup(self) -> None:
        facade = (self.repo / "ext/CMakeLists.txt").read_text()
        template = (
            self.repo / "cmake/patches/efsw-win32-createwatch-cleanup.patch.in"
        ).read_text()
        self.assertNotIn("\t", template)
        patch = template.replace("@EFSW_TAB@", "\t")
        self.assertIn(
            "set(efsw_revision 22f17a0bcdf3a4edf61f8b14328391463389e548)", facade
        )
        self.assertIn(
            'set(efsw_cleanup_patch "${CMAKE_CURRENT_BINARY_DIR}/patches/efsw-win32-createwatch-cleanup.patch")',
            facade,
        )
        self.assertIn("string(ASCII 9 EFSW_TAB)", facade)
        self.assertIn("@ONLY NEWLINE_STYLE LF", facade)
        generation = re.search(
            r"set\(efsw_cleanup_patch .*?(?=file\(SHA256)", facade, re.DOTALL
        )
        self.assertIsNotNone(generation)
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            script = directory / "render.cmake"
            script.write_text(
                f'set(CMAKE_SOURCE_DIR "{self.repo.as_posix()}")\n' + generation[0]
            )
            result = subprocess.run(
                [
                    "cmake",
                    "-P",
                    str(script),
                ],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            rendered = directory / "patches/efsw-win32-createwatch-cleanup.patch"
            self.assertEqual(rendered.read_bytes(), patch.encode())
        self.assertEqual(
            hashlib.sha256(patch.encode()).hexdigest(),
            "cccb03672f0af3abc267671cba70c51bb0a5c4c2300a3f53b0257a0d121d6d4b",
        )
        self.assertIn('file(SHA256 "${efsw_cleanup_patch}" efsw_patch_hash)', facade)
        self.assertIn(
            'string(SHA256 efsw_cache_key "${efsw_revision}:${efsw_patch_hash}")',
            facade,
        )
        self.assertIn("GIT_TAG ${efsw_revision}", facade)
        self.assertIn("CUSTOM_CACHE_KEY ${efsw_cache_key}", facade)
        self.assertIn('PATCHES "${efsw_cleanup_patch}"', facade)
        self.assertEqual(patch.count("@@"), 2)
        changed = [
            line
            for line in patch.splitlines()
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        ]
        self.assertEqual(
            changed,
            ["-\tefSAFE_DELETE( pWatch->Watch );", "+\tefSAFE_DELETE( pWatch );"],
        )

    def test_patch_is_a_build_only_dependency_in_both_container_images(self) -> None:
        for image in ("ubuntu", "alpine"):
            with self.subTest(image=image):
                source = (self.repo / f"docker/{image}.Dockerfile").read_text()
                base, later = source.split("FROM base AS staging", 1)
                staging = later.split("# Install secondary dependencies as user.", 1)[0]
                package = r"(?m)^    patch \\$"
                self.assertNotRegex(base, package)
                self.assertRegex(staging, package)

    def test_schema_job_declares_patch_before_cmake_configuration(self) -> None:
        workflow = yaml.safe_load(
            (self.repo / ".github/workflows/pr_checks.yml").read_text()
        )
        job = workflow["jobs"]["Data_Validation"]
        self.assertEqual(
            job["container"]["image"],
            "${{ vars.DEVTOOLS_IMAGE || 'ghcr.io/landsandboat/devtools:ubuntu' }}",
        )
        names = [step.get("name") for step in job["steps"]]
        install = next(
            step
            for step in job["steps"]
            if step.get("name") == "Install schema compiler dependencies"
        )
        self.assertEqual(install["if"], "steps.changed.outputs.touched == 'true'")
        self.assertLess(
            names.index(install["name"]), names.index("Configure schema compiler")
        )
        self.assertIn("if ! command -v patch >/dev/null 2>&1; then", install["run"])
        self.assertIn("sudo apt-get update", install["run"])
        self.assertIn(
            "sudo apt-get install --assume-yes --no-install-recommends --quiet patch",
            install["run"],
        )
        self.assertTrue(install["run"].rstrip().endswith("command -v patch"))

    def test_windows_crash_reason_explicitly_initializes_optional_detail(self) -> None:
        source = (self.repo / "src/common/debug_windows.cpp").read_text()
        self.assertIn(
            "{ .kind = exceptionName(code), .detail = std::nullopt, .dumpLocation = dumpPath }",
            source,
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
        self.assertNotIn("clang-cl", configure)
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
    main()
