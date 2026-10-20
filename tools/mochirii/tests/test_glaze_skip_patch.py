from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main

REPO = Path(__file__).resolve().parents[3]
REVISION = "d78832c82289c61a9315bfbc35332cec9f4e93ca"
PATCH_SHA256 = "18ca70d499921efc5b5c4d9d540b26190def1d2b33a59db46eb68731baab3fe5"


class GlazeSkipPatchTests(TestCase):
    def test_patch_changes_only_the_reviewed_template_bindings(self) -> None:
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
                "diff --git a/include/glaze/util/parse.hpp b/include/glaze/util/parse.hpp",
                "diff --git a/include/glaze/reflection/get_name.hpp b/include/glaze/reflection/get_name.hpp",
                "diff --git a/include/glaze/json/schema.hpp b/include/glaze/json/schema.hpp",
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
            * 2
            + ["it = std::find_if_not(it, end, is_digit);"] * 3
            + [
                'str = str.substr(str.find("->") + 2);',
                'return str.substr(0, str.find(">"));',
                "template <const std::string_view& ref>",
                "static_assert(!has_slash(ref),",
                'join_v<chars<"Slash in name: \\"">, ref, chars<"\\" in json schema references is not allowed">>);',
                'static_assert(!has_slash(ref), "Slashes in json schema references are not allowed");',
                "validate_ref<name_v<inner_val_t>>();",
                "validate_ref<name_v<val_t>>();",
            ],
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
            * 2
            + [
                "it = std::find_if_not(it, end, static_cast<bool (*)(uint8_t) noexcept>(&glz::is_digit));"
            ]
            * 3
            + [
                'if (str.find("->") != std::string_view::npos) {',
                'str = str.substr(str.find("->") + 2);',
                'return str.substr(0, str.find(">"));',
                "const auto dot = str.rfind('.');",
                "if (dot == std::string_view::npos) {",
                "str.remove_prefix(dot + 1);",
                'const auto end = str.find_first_of(")>");',
                "if (end == std::string_view::npos) {",
                "return str.substr(0, end);",
                "template <class T>",
                "static_assert(!has_slash(name_v<T>),",
                'join_v<chars<"Slash in name: \\"">, name_v<T>, chars<"\\" in json schema references is not allowed">>);',
                'static_assert(!has_slash(name_v<T>), "Slashes in json schema references are not allowed");',
                "validate_ref<inner_val_t>();",
                "validate_ref<val_t>();",
            ]
            + ["return {};"] * 2
            + ["}"] * 3,
        )

    def test_interior_patch_hunks_keep_balanced_portable_context(self) -> None:
        lines = (
            (REPO / "cmake/patches/glaze-skip-member-templates.patch")
            .read_text()
            .splitlines()
        )
        hunks = 0
        index = 0
        while index < len(lines):
            header = re.fullmatch(r"@@ -(\d+),(\d+) \+(\d+),(\d+) @@.*", lines[index])
            if header is None:
                index += 1
                continue
            hunks += 1
            old_start, old_count, new_start, new_count = map(int, header.groups())
            self.assertGreater(old_start, 1)
            self.assertGreater(new_start, 1)
            old_seen = new_seen = 0
            body = []
            index += 1
            while old_seen < old_count or new_seen < new_count:
                self.assertLess(index, len(lines))
                line = lines[index]
                self.assertTrue(not line or line[0] in " +-", line)
                body.append(line)
                old_seen += not line.startswith("+")
                new_seen += not line.startswith("-")
                index += 1
            self.assertEqual((old_seen, new_seen), (old_count, new_count))
            leading = 0
            for line in body:
                if line.startswith(("+", "-")):
                    break
                leading += 1
            trailing = 0
            for line in reversed(body):
                if line.startswith(("+", "-")):
                    break
                trailing += 1
            # Keep one extra final context line so the patch does not end on
            # an empty source line, while retaining all portable context.
            self.assertEqual((leading, trailing), (3, 4 if hunks == 12 else 3))
        self.assertEqual(hunks, 12)

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
