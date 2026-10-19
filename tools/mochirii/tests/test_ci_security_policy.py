from __future__ import annotations

import hashlib
import io
import json
import re
import subprocess
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main, mock

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
            '-DCMAKE_C_COMPILER:FILEPATH="C:/Program Files/LLVM/bin/clang-cl.exe"',
            '-DCMAKE_CXX_COMPILER:FILEPATH="C:/Program Files/LLVM/bin/clang-cl.exe"',
            '-DCMAKE_PROJECT_server_INCLUDE:FILEPATH="$RUNNER_TEMP/mochirii-codeql-cxx23.cmake"',
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
        output = "clang version 20.1.8\nTarget: x86_64-pc-windows-msvc\n"
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
            ({}, output.replace("20.1.8", "21.1.0"), True, False),
            ({}, output.replace("x86_64", "aarch64"), True, False),
            ({}, output + "x" * 32768, True, False),
        )
        for changed, version, exists, accepted in cases:
            with self.subTest(
                changed=changed, exists=exists, accepted=accepted
            ), mock.patch.dict(
                "os.environ", environment | changed, clear=True
            ), mock.patch(
                "pathlib.Path.is_file", return_value=exists
            ), mock.patch(
                "subprocess.run", return_value=mock.Mock(stdout=version, stderr="")
            ) as run, redirect_stdout(
                io.StringIO()
            ):
                if accepted:
                    exec(compile(script, "<toolchain-preflight>", "exec"), {})
                    self.assertEqual(run.call_args.kwargs["timeout"], 15)
                    self.assertTrue(run.call_args.kwargs["check"])
                else:
                    with self.assertRaises(SystemExit):
                        exec(compile(script, "<toolchain-preflight>", "exec"), {})

    def test_windows_cmake_context_rejects_wrong_compiler_or_standard(self) -> None:
        script = self._inline_script("Verify Windows security CMake context")
        values = {
            "COMPILER": "C:/Program Files/LLVM/bin/clang-cl.exe",
            "COMPILER_ID": "Clang",
            "COMPILER_VERSION": "20.1.8",
            "COMPILER_FRONTEND_VARIANT": "MSVC",
        }
        cases = (
            ({}, ["/std:c++23preview"], "src", True),
            (
                {"COMPILER": "C:/other/clang-cl.exe"},
                ["/std:c++23preview"],
                "src",
                False,
            ),
            ({"COMPILER_ID": "MSVC"}, ["/std:c++23preview"], "src", False),
            ({"COMPILER_VERSION": "21.1.0"}, ["/std:c++23preview"], "src", False),
            ({"COMPILER_FRONTEND_VARIANT": "GNU"}, ["/std:c++23preview"], "src", False),
            ({}, ["-clang:-std=c++23"], "src", False),
            ({}, ["-std:c++latest"], "src", False),
            ({}, ["/std:c++latest"], "src", False),
            ({}, ["-clang:-std=c++26"], "src", False),
            ({}, [], "src", False),
            ({}, ["/std:c++23preview", "-clang:-std=c++23"], "src", False),
            ({}, ["/std:c++23preview", "/std:c++latest"], "src", False),
            ({}, ["/std:c++23preview", "/std:c++23preview"], "src", False),
            ({}, ["/std:c++23preview"], "ext", False),
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
                                for key, value in (values | changed).items()
                            )
                        )
                    (build / "compile_commands.json").write_text(
                        json.dumps(
                            [
                                {
                                    "file": str(root / folder / "sample.cpp"),
                                    "command": "clang-cl.exe " + " ".join(standards),
                                }
                            ]
                        )
                    )
                    with mock.patch("pathlib.Path.cwd", return_value=root), mock.patch(
                        "subprocess.run", return_value=mock.Mock(stdout="", stderr="")
                    ) as run, redirect_stdout(io.StringIO()):
                        if accepted:
                            exec(compile(script, "<cmake-context>", "exec"), {})
                            self.assertEqual(run.call_args.kwargs["timeout"], 30)
                            self.assertTrue(run.call_args.kwargs["check"])
                            arguments = run.call_args.args[0]
                            self.assertEqual(
                                arguments[:-1],
                                [
                                    "C:/Program Files/LLVM/bin/clang-cl.exe",
                                    "/nologo",
                                    "/Zs",
                                    "/WX",
                                    "/W4",
                                    "/EHsc",
                                    "/std:c++23preview",
                                    "--",
                                ],
                            )
                            self.assertFalse(Path(arguments[-1]).exists())
                            for failure in (
                                subprocess.CalledProcessError(1, arguments),
                                subprocess.TimeoutExpired(arguments, 30),
                            ):
                                run.side_effect = failure
                                with self.assertRaises(type(failure)):
                                    exec(compile(script, "<cmake-context>", "exec"), {})
                            run.side_effect = None
                            run.return_value.stdout = "x" * 32769
                            with self.assertRaises(SystemExit):
                                exec(compile(script, "<cmake-context>", "exec"), {})
                        else:
                            with self.assertRaises(SystemExit):
                                exec(compile(script, "<cmake-context>", "exec"), {})
                            run.assert_not_called()
            (compiler_context / "CMakeCCompiler.cmake").unlink()
            with mock.patch("pathlib.Path.cwd", return_value=root), self.assertRaises(
                SystemExit
            ):
                exec(compile(script, "<cmake-context>", "exec"), {})

    def test_windows_cxx23_override_is_narrow_and_preserves_the_language(self) -> None:
        script = self._inline_script("Configure Windows security extraction context")
        context = self._inline_script("Verify Windows security CMake context")
        for proof in (
            "__cplusplus == 202302L",
            "_MSVC_LANG == 202302L",
            "operator==(const Comparison&) const = default",
            "std::expected<int, int>",
            "std::optional<int>",
            "std::span<const int>",
            "std::string_view",
        ):
            self.assertIn(proof, context)
        values = {
            "WIN32": "TRUE",
            "CMAKE_CXX_COMPILER_ID": "Clang",
            "CMAKE_CXX_COMPILER_VERSION": "20.1.8",
            "CMAKE_CXX_COMPILER_FRONTEND_VARIANT": "MSVC",
            "CMAKE_CXX23_STANDARD_COMPILE_OPTION": "-clang:-std=c++23",
            "CMAKE_CXX23_EXTENSION_COMPILE_OPTION": "-clang:-std=c++23",
        }
        cases = (
            ({}, True),
            ({"WIN32": "FALSE"}, False),
            ({"CMAKE_CXX_COMPILER_ID": "MSVC"}, False),
            ({"CMAKE_CXX_COMPILER_VERSION": "21.1.0"}, False),
            ({"CMAKE_CXX_COMPILER_FRONTEND_VARIANT": "GNU"}, False),
            ({"CMAKE_CXX23_STANDARD_COMPILE_OPTION": "/std:c++latest"}, False),
            ({"CMAKE_CXX23_EXTENSION_COMPILE_OPTION": "-std=c++26"}, False),
            ({"CMAKE_CXX23_STANDARD_COMPILE_OPTION": ""}, False),
        )
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.dict("os.environ", {"RUNNER_TEMP": temporary}):
                exec(compile(script, "<cmake-override>", "exec"), {})
            override = root / "mochirii-codeql-cxx23.cmake"
            for changed, accepted in cases:
                with self.subTest(changed=changed):
                    probe = root / "verify.cmake"
                    probe.write_text(
                        "\n".join(
                            f'set({key} "{value}")'
                            for key, value in (values | changed).items()
                        )
                        + f'\ninclude("{override.as_posix()}")\n'
                        + """foreach(kind STANDARD EXTENSION)
                        if(NOT CMAKE_CXX23_${kind}_COMPILE_OPTION STREQUAL "/std:c++23preview")
                            message(FATAL_ERROR "C++23 option was not replaced exactly")
                        endif()
                        endforeach()
                        """
                    )
                    result = subprocess.run(
                        ["cmake", "-P", str(probe)],
                        capture_output=True,
                        text=True,
                        timeout=30,
                        check=False,
                    )
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)

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
