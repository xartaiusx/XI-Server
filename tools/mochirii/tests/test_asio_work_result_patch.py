from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main

REPO = Path(__file__).resolve().parents[3]
REVISION = "03cf5f86a780dd102f1cdd3a59d1244d12143e46"
UPSTREAM_FIX = "f71a59e0673c4c4b3c936225ac36baabb3ba8db7"
PATCH_SHA256 = "835026732af77529dbf78555f73821c61316ae21583c901a838b2350a408a77d"


class AsioWorkResultPatchTests(TestCase):
    def test_patch_is_the_exact_upstream_work_result_correction(self) -> None:
        facade = (REPO / "ext/CMakeLists.txt").read_text()
        patch = (REPO / "cmake/patches/asio-work-result-sfinae.patch").read_bytes()
        self.assertEqual(hashlib.sha256(patch).hexdigest(), PATCH_SHA256)
        self.assertNotIn(b"\r", patch)
        self.assertNotIn(b"\t", patch)
        self.assertIn(
            f"https://github.com/chriskohlhoff/asio/commit/{UPSTREAM_FIX}", facade
        )
        self.assertEqual(
            [
                line
                for line in patch.decode().splitlines()
                if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
            ],
            [
                "-template <typename Function>",
                "+template <typename Function, typename = void>",
                "+{",
                "+};",
                "+",
                "+template <typename Function>",
                "+struct work_result<Function, void_t<result_of_t<decay_t<Function>()>>>",
            ],
        )

    def test_patched_source_uses_a_revision_and_content_bound_cache(self) -> None:
        facade = (REPO / "ext/CMakeLists.txt").read_text()
        binding = re.search(
            r"set\(asio_revision .*?\n\) #defines asio", facade, re.DOTALL
        )
        self.assertIsNotNone(binding)
        self.assertIn(f"set(asio_revision {REVISION})", binding[0])
        self.assertIn(
            'file(SHA256 "${asio_work_result_patch}" asio_patch_hash)', binding[0]
        )
        self.assertIn(
            'string(SHA256 asio_cache_key "${asio_revision}:${asio_patch_hash}")',
            binding[0],
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            script = directory / "cache.cmake"
            script.write_text(
                f'set(CMAKE_SOURCE_DIR "{REPO.as_posix()}")\n'
                + "function(CPMAddPackage)\n"
                + '  cmake_parse_arguments(P "" "NAME;VERSION;GITHUB_REPOSITORY;GIT_TAG;CUSTOM_CACHE_KEY;PATCHES" "" ${ARGN})\n'
                + '  file(WRITE "captured.txt" "${P_NAME}\\n${P_VERSION}\\n${P_GITHUB_REPOSITORY}\\n${P_GIT_TAG}\\n${P_CUSTOM_CACHE_KEY}\\n${P_PATCHES}\\n")\n'
                + "endfunction()\n"
                + binding[0]
                + "\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                ["cmake", "-P", str(script)],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                (directory / "captured.txt").read_text().splitlines(),
                [
                    "asio",
                    "1.38.0",
                    "chriskohlhoff/asio",
                    REVISION,
                    hashlib.sha256(f"{REVISION}:{PATCH_SHA256}".encode()).hexdigest(),
                    (REPO / "cmake/patches/asio-work-result-sfinae.patch").as_posix(),
                ],
            )


if __name__ == "__main__":
    main()
