from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main

REPO = Path(__file__).resolve().parents[3]
REVISION = "1078bfe346d9bb560faa748c8fde2e7aae73a3ab"
PATCH_SHA256 = "f4f4e3df025bed99fd4f76f331fdd91228608bd20bb9433e360c69a3a378afcf"
PATCH = REPO / "cmake/patches/recast-security.patch"
PATHS = (
    "Recast/Source/RecastMesh.cpp",
    "Recast/Source/RecastRegion.cpp",
)


class RecastSecurityPatchTests(TestCase):
    def test_patch_format_rule_is_limited_to_its_context_markers(self) -> None:
        attributes = (REPO / ".gitattributes").read_text().splitlines()
        self.assertEqual(
            [line for line in attributes if "recast-security.patch" in line],
            [
                "cmake/patches/recast-security.patch text eol=lf whitespace=-space-before-tab"
            ],
        )
        # These are unified context markers, not added C++ indentation.
        self.assertEqual(
            sum(line.startswith(" \t") for line in PATCH.read_text().splitlines()),
            15,
        )

    def test_patch_changes_only_the_reviewed_products_and_format(self) -> None:
        patch = PATCH.read_bytes()
        self.assertEqual(hashlib.sha256(patch).hexdigest(), PATCH_SHA256)
        self.assertNotIn(b"\r", patch)
        lines = patch.decode().splitlines()
        self.assertTrue(all(line == line.rstrip() for line in lines))
        self.assertEqual(
            [line for line in lines if line.startswith("diff --git ")],
            [f"diff --git a/{path} b/{path}" for path in PATHS],
        )
        self.assertEqual(
            [line[1:].strip() for line in lines if line.startswith("-") and not line.startswith("---")],
            [
                "memset(polys, 0xff, ntris*nvp*sizeof(unsigned short));",
                "memset(polys, 0xff, maxVertsPerCont*nvp*sizeof(unsigned short));",
                'ctx->log(RC_LOG_ERROR, "rcBuildRegions: %d overlapping regions.", overlaps.size());',
            ],
        )
        self.assertEqual(
            [line[1:].strip() for line in lines if line.startswith("+") and not line.startswith("+++")],
            [
                "memset(polys, 0xff, sizeof(unsigned short)*ntris*nvp);",
                "memset(polys, 0xff, sizeof(unsigned short)*maxVertsPerCont*nvp);",
                'ctx->log(RC_LOG_ERROR, "rcBuildRegions: %lld overlapping regions.", static_cast<long long>(overlaps.size()));',
            ],
        )

    def test_patch_applies_and_reverses_with_exact_context(self) -> None:
        # Reconstruct only the exact public old-context snippets; no dependency
        # fetch, existing build cache, repository initialization, or compilation.
        fixtures: dict[str, list[str]] = {}
        current = ""
        hunks = 0
        lines = PATCH.read_text().splitlines()
        index = 0
        while index < len(lines):
            line = lines[index]
            if line.startswith("--- a/"):
                current = line.removeprefix("--- a/")
                self.assertIn(current, PATHS)
            header = re.fullmatch(r"@@ -(\d+),(\d+) \+(\d+),(\d+) @@.*", line)
            if header is None:
                index += 1
                continue
            hunks += 1
            old_start, old_count, new_start, new_count = map(int, header.groups())
            self.assertTrue(1 < old_start <= 2000)
            self.assertTrue(1 < new_start <= 2000)
            self.assertTrue(1 <= old_count <= 20)
            self.assertEqual(old_count, new_count)
            body = []
            old_seen = new_seen = 0
            index += 1
            while old_seen < old_count or new_seen < new_count:
                self.assertLess(index, len(lines))
                entry = lines[index]
                self.assertTrue(not entry or entry[0] in " +-")
                body.append(entry)
                old_seen += not entry.startswith("+")
                new_seen += not entry.startswith("-")
                index += 1
            self.assertEqual((old_seen, new_seen), (old_count, new_count))
            leading = []
            for entry in body:
                if entry.startswith(("+", "-")):
                    break
                leading.append(entry)
            trailing = []
            for entry in reversed(body):
                if entry.startswith(("+", "-")):
                    break
                trailing.append(entry)
            # Balanced exact context avoids driver fuzz without including or
            # normalizing upstream TAB-only lines. The middle hunk retains its
            # genuinely empty source line; no whitespace source edit is made.
            expected_headers = [(876, 5, 876, 5), (1133, 9, 1133, 9), (1656, 5, 1656, 5)]
            expected_context = [(2, 2, 2, 2), (4, 4, 3, 4), (2, 2, 2, 2)]
            self.assertEqual(
                (old_start, old_count, new_start, new_count),
                expected_headers[hunks - 1],
            )
            self.assertEqual(
                (
                    len(leading),
                    len(trailing),
                    sum(bool(entry.strip()) for entry in leading),
                    sum(bool(entry.strip()) for entry in trailing),
                ),
                expected_context[hunks - 1],
            )
            self.assertEqual(len(leading), len(trailing))
            for context in (leading, trailing):
                self.assertGreaterEqual(len(context), 2)
                self.assertGreaterEqual(sum(bool(entry.strip()) for entry in context), 2)
            old = [entry[1:] if entry else "" for entry in body if not entry.startswith("+")]
            fixture = fixtures.setdefault(current, [])
            while len(fixture) < old_start + old_count - 1:
                fixture.append("// Unused source line in the patch-only fixture.")
            fixture[old_start - 1 : old_start + old_count - 1] = old
        self.assertEqual(hunks, 3)
        self.assertEqual(set(fixtures), set(PATHS))

        with TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            originals = {}
            for path, contents in fixtures.items():
                target = directory / path
                target.parent.mkdir(parents=True, exist_ok=True)
                originals[path] = ("\n".join(contents) + "\n").encode()
                target.write_bytes(originals[path])
            for flags in (["--check"], [], ["--reverse", "--check"], ["--reverse"]):
                result = subprocess.run(
                    ["git", "apply", "--whitespace=error-all", *flags, str(PATCH)],
                    cwd=directory,
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for path, contents in originals.items():
                self.assertEqual((directory / path).read_bytes(), contents)

    def test_validation_failure_cleanup_precedes_any_tile_transfer(self) -> None:
        builder = (REPO / "src/map/navmesh/navmesh_builder.cpp").read_text()
        contour_build = builder.index("!rcBuildContours(")
        contour_check = builder.index("if (!supportsContourSet(*cset))", contour_build)
        poly_build = builder.index("!rcBuildPolyMesh(", contour_check)
        rejected_tile = builder[contour_check:poly_build]
        self.assertIn("return { .validationFailed = true };", rejected_tile)
        self.assertIn("if (cset->nconts == 0)", rejected_tile)
        self.assertLess(contour_build, contour_check)
        self.assertLess(contour_check, poly_build)

        asynchronous_build = builder.index("auto NavMeshBuilder::buildAsync(")
        validation = builder.index("if (hasTileValidationFailure(results))", asynchronous_build)
        transfer = builder.index("navMesh->addTile(", asynchronous_build)
        cleanup = builder[validation:transfer]
        self.assertLess(validation, transfer)
        self.assertIn("for (const auto& result : results)", cleanup)
        self.assertIn("dtFree(result.data);", cleanup)
        self.assertIn("dtFreeNavMesh(navMesh);", cleanup)
        self.assertIn("co_return nullptr;", cleanup)
        self.assertLess(cleanup.index("dtFree(result.data);"), cleanup.index("dtFreeNavMesh(navMesh);"))
        self.assertLess(cleanup.index("dtFreeNavMesh(navMesh);"), cleanup.index("co_return nullptr;"))

    def test_patched_source_uses_revision_and_content_bound_cache(self) -> None:
        facade = (REPO / "ext/CMakeLists.txt").read_text()
        binding = re.search(
            r"set\(recast_revision .*?\n\) # defines: RecastNavigation::Recast, RecastNavigation::Detour",
            facade,
            re.DOTALL,
        )
        self.assertIsNotNone(binding)
        self.assertIn(f"set(recast_revision {REVISION})", binding[0])
        self.assertIn('file(SHA256 "${recast_security_patch}" recast_patch_hash)', binding[0])
        self.assertIn(
            'string(SHA256 recast_cache_key "${recast_revision}:${recast_patch_hash}")',
            binding[0],
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            script = directory / "cache.cmake"
            script.write_text(
                f'set(CMAKE_SOURCE_DIR "{REPO.as_posix()}")\n'
                + "function(CPMAddPackage)\n"
                + '  cmake_parse_arguments(P "" "NAME;GITHUB_REPOSITORY;GIT_TAG;CUSTOM_CACHE_KEY;PATCHES;SYSTEM" "OPTIONS" ${ARGN})\n'
                + '  file(WRITE "captured.txt" "${P_NAME}\\n${P_GITHUB_REPOSITORY}\\n${P_GIT_TAG}\\n${P_CUSTOM_CACHE_KEY}\\n${P_PATCHES}\\n${P_SYSTEM}\\n${P_OPTIONS}\\n")\n'
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
                    "recastnavigation",
                    "recastnavigation/recastnavigation",
                    REVISION,
                    hashlib.sha256(f"{REVISION}:{PATCH_SHA256}".encode()).hexdigest(),
                    PATCH.as_posix(),
                    "ON",
                    "RECASTNAVIGATION_DEMO OFF;RECASTNAVIGATION_TESTS OFF;"
                    "RECASTNAVIGATION_EXAMPLES OFF;RECASTNAVIGATION_DT_POLYREF64 OFF;"
                    "RECASTNAVIGATION_DT_VIRTUAL_QUERYFILTER OFF;RECASTNAVIGATION_ENABLE_ASSERTS OFF",
                ],
            )


if __name__ == "__main__":
    main()
