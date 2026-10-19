from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main

REPO = Path(__file__).resolve().parents[3]
REVISION = "d78832c82289c61a9315bfbc35332cec9f4e93ca"
PATCH_SHA256 = "a1e44c133f7b550348b3047b4466af55be7594a2e4e1d4ec9bacae602b3a35f1"


class GlazeSkipPatchTests(TestCase):
    def test_patch_changes_only_the_six_member_signatures(self) -> None:
        patch = (REPO / "cmake/patches/glaze-skip-member-templates.patch").read_bytes()
        self.assertEqual(hashlib.sha256(patch).hexdigest(), PATCH_SHA256)
        self.assertNotIn(b"\r", patch)
        self.assertNotIn(b"\t", patch)
        lines = patch.decode().splitlines()
        self.assertTrue(all(line == line.rstrip() for line in lines))
        self.assertEqual(
            [line for line in lines if line.startswith("diff --git ")],
            [
                "diff --git a/include/glaze/beve/skip.hpp b/include/glaze/beve/skip.hpp",
                "diff --git a/include/glaze/json/skip.hpp b/include/glaze/json/skip.hpp",
            ],
        )
        removed = [
            line[1:].strip()
            for line in lines
            if line.startswith("-") and not line.startswith("---")
        ]
        added = [
            line[1:].strip()
            for line in lines
            if line.startswith("+") and not line.startswith("+++")
        ]
        self.assertCountEqual(
            removed,
            ["template <auto Opts>"] * 6
            + ["requires(not Opts.comments)"] * 2
            + ["requires(bool(Opts.comments))"] * 2
            + [
                "inline static void op(is_context auto&& ctx, auto&& it, auto end) noexcept;",
                "inline void skip_value<BEVE>::op(is_context auto&& ctx, auto&& it, auto end) noexcept",
            ]
            + [
                "GLZ_ALWAYS_INLINE static void op(is_context auto&& ctx, auto&& it, auto end) noexcept;"
            ]
            * 2
            + [
                "GLZ_ALWAYS_INLINE void skip_value<JSON>::op(is_context auto&& ctx, auto&& it, auto end) noexcept"
            ]
            * 2,
        )
        self.assertCountEqual(
            added,
            ["template <auto Opts, class Ctx, class It, class End>"] * 6
            + ["requires(is_context<Ctx>)"] * 2
            + ["requires((not Opts.comments) && is_context<Ctx>)"] * 2
            + ["requires((bool(Opts.comments)) && is_context<Ctx>)"] * 2
            + [
                "inline static void op(Ctx&& ctx, It&& it, End end) noexcept;",
                "inline void skip_value<BEVE>::op(Ctx&& ctx, It&& it, End end) noexcept",
            ]
            + [
                "GLZ_ALWAYS_INLINE static void op(Ctx&& ctx, It&& it, End end) noexcept;"
            ]
            * 2
            + [
                "GLZ_ALWAYS_INLINE void skip_value<JSON>::op(Ctx&& ctx, It&& it, End end) noexcept"
            ]
            * 2,
        )

    def test_patched_source_uses_a_revision_and_content_bound_cache(self) -> None:
        facade = (REPO / "ext/CMakeLists.txt").read_text()
        binding = re.search(
            r"set\(glaze_revision .*?\n\)(?=\nif\(glaze_ADDED\))", facade, re.DOTALL
        )
        self.assertIsNotNone(binding)
        self.assertIn(f"set(glaze_revision {REVISION})", binding[0])
        self.assertIn('file(SHA256 "${glaze_skip_patch}" glaze_patch_hash)', binding[0])
        self.assertIn(
            'string(SHA256 glaze_cache_key "${glaze_revision}:${glaze_patch_hash}")',
            binding[0],
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            script = directory / "cache.cmake"
            script.write_text(
                f'set(CMAKE_SOURCE_DIR "{REPO.as_posix()}")\n'
                + "function(CPMAddPackage)\n"
                + '  cmake_parse_arguments(P "DOWNLOAD_ONLY" "NAME;VERSION;GITHUB_REPOSITORY;GIT_TAG;CUSTOM_CACHE_KEY;PATCHES" "" ${ARGN})\n'
                + '  file(WRITE "captured.txt" "${P_NAME}\\n${P_VERSION}\\n${P_GITHUB_REPOSITORY}\\n${P_GIT_TAG}\\n${P_CUSTOM_CACHE_KEY}\\n${P_PATCHES}\\n${P_DOWNLOAD_ONLY}\\n")\n'
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
                    "glaze",
                    "9.0.0",
                    "stephenberry/glaze",
                    REVISION,
                    hashlib.sha256(f"{REVISION}:{PATCH_SHA256}".encode()).hexdigest(),
                    (
                        REPO / "cmake/patches/glaze-skip-member-templates.patch"
                    ).as_posix(),
                    "TRUE",
                ],
            )


if __name__ == "__main__":
    main()
