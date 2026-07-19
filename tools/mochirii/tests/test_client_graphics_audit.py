from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "client_graphics_audit.py"
SPEC = importlib.util.spec_from_file_location("client_graphics_audit", MODULE_PATH)
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


class ClientGraphicsAuditTests(unittest.TestCase):
    def test_parse_overlay_order_and_reject_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "settings.xml"
            path.write_text(
                '<?xml version="1.1"?><settings><global><overlays> One, Two </overlays></global></settings>',
                encoding="utf-8",
            )
            self.assertEqual(audit.parse_overlay_order(path), ["One", "Two"])

            path.write_text(
                "<settings><global><overlays>One,One</overlays></global></settings>",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "duplicate"):
                audit.parse_overlay_order(path)

            for payload, message in (
                ("One,one", "duplicate"),
                ("One,,Two", "blank"),
                ("../One", "unsafe"),
                ("One/Two", "unsafe"),
            ):
                path.write_text(
                    f"<settings><global><overlays>{payload}</overlays></global></settings>",
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(ValueError, message):
                    audit.parse_overlay_order(path)

            path.write_text(
                "<settings><overlays>One</overlays><global><overlays>Two</overlays></global></settings>",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "exactly one"):
                audit.parse_overlay_order(path)

    def test_relative_paths_reject_platform_independent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for value in ("../escape", "..\\escape", "C:\\escape", "/escape"):
                with self.assertRaisesRegex(ValueError, "unsafe"):
                    audit.resolve_relative(root, value, "fixture")

    def test_scan_counts_only_addressable_dat_files_case_insensitively(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dat_root = Path(temporary)
            overlay_root = dat_root / "Layer"
            (overlay_root / "ROM" / "1").mkdir(parents=True)
            (overlay_root / "ROM" / "1" / "2.DaT").write_bytes(b"two")
            (overlay_root / "ROM" / "1" / "note.txt").write_text("ignored")
            (overlay_root / "ROM" / "Backup").mkdir()
            (overlay_root / "ROM" / "Backup" / "2.DAT").write_bytes(b"inactive")

            contract = {
                "name": "Layer",
                "expectedDatCount": 1,
                "expectedTreeSha256": "",
                "representativeDat": "rom/1/2.dat",
                "source": {"name": "fixture"},
            }
            layers, summary, issues = audit.scan_overlay(dat_root, contract)
            self.assertEqual(len(layers), 1)
            self.assertEqual(summary["datCount"], 1)
            self.assertEqual(summary["unaddressableDatPaths"], ["ROM/Backup/2.DAT"])
            self.assertTrue(any("unaddressable" in issue for issue in issues))

            (overlay_root / "ROM" / "Backup" / "2.DAT").unlink()
            contract["expectedTreeSha256"] = summary["treeSha256"]
            _, clean_summary, clean_issues = audit.scan_overlay(dat_root, contract)
            self.assertEqual(clean_summary["datCount"], 1)
            self.assertEqual(clean_issues, [])

    def test_scan_rejects_dat_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dat_root = Path(temporary)
            overlay_root = dat_root / "Layer" / "ROM" / "1"
            overlay_root.mkdir(parents=True)
            outside = dat_root / "outside.dat"
            outside.write_bytes(b"outside")
            link = overlay_root / "2.DAT"
            try:
                os.symlink(outside, link)
            except OSError as exc:
                self.skipTest(f"symlink creation is unavailable: {exc}")
            _, _, issues = audit.scan_overlay(
                dat_root,
                {
                    "name": "Layer",
                    "expectedDatCount": 1,
                    "expectedTreeSha256": "a" * 64,
                    "representativeDat": "ROM/1/2.DAT",
                    "source": {"name": "fixture"},
                },
            )
            self.assertTrue(any("symlink" in issue for issue in issues))

    def test_case_variant_paths_collide_and_first_layer_owns(self) -> None:
        first = audit.DatLayer(
            overlay="First",
            relative_path="ROM/1/2.DAT",
            normalized_path="rom/1/2.dat",
            bytes=3,
            sha256="a" * 64,
            source_name="first source",
        )
        second = audit.DatLayer(
            overlay="Second",
            relative_path="rom/1/2.dat",
            normalized_path="rom/1/2.dat",
            bytes=4,
            sha256="b" * 64,
            source_name="second source",
        )
        collisions, pairs, issues = audit.classify_collisions(
            {"rom/1/2.dat": [first, second]},
            [{"owner": "First", "shadowed": "Second", "expectedPaths": 1}],
        )
        self.assertEqual(issues, [])
        self.assertEqual(pairs[("First", "Second")], 1)
        self.assertEqual(collisions[0]["owner"], "First")
        self.assertEqual(
            [layer["relativePath"] for layer in collisions[0]["layers"]],
            ["ROM/1/2.DAT", "rom/1/2.dat"],
        )
        self.assertFalse(collisions[0]["allHashesEqual"])

    def test_direct_dat_index_rejects_duplicate_paths(self) -> None:
        entries = [
            {
                "relativePath": relative,
                "stockSha256": "a" * 64,
                "replacementSha256": "b" * 64,
                "bytes": 1,
            }
            for relative in ("ROM/0/12.DAT", "rom\\0\\12.dat")
        ]
        ordered, indexed, issues = audit.index_direct_dat_entries(
            entries,
            "relativePath",
            ("stockSha256", "replacementSha256"),
            "fixture",
        )
        self.assertEqual(len(ordered), 1)
        self.assertEqual(len(indexed), 1)
        self.assertTrue(any("duplicate" in issue for issue in issues))

    def test_tsv_uses_real_tab_delimiters(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.tsv"
            audit.write_tsv(
                path,
                [
                    {
                        "relativePath": "ROM/1/2.DAT",
                        "owner": "First",
                        "layers": [
                            {
                                "overlay": "First",
                                "sha256": "a" * 64,
                                "source": "fixture",
                            }
                        ],
                        "collisionStatus": "none",
                    }
                ],
            )
            payload = path.read_bytes()
            self.assertIn(b"\t", payload)
            self.assertNotIn(b"`t", payload)

    def test_canonical_outputs_require_full_verification(self) -> None:
        with self.assertRaisesRegex(ValueError, "canonical current outputs require"):
            audit.validate_output_policy(
                Path("client-graphics-audit-current.json"),
                Path("client-graphics-audit-current.tsv"),
                False,
                False,
            )
        audit.validate_output_policy(
            Path("client-graphics-audit-static.json"),
            Path("client-graphics-audit-static.tsv"),
            False,
            False,
        )

    def test_source_provenance_requires_hash_and_artifact_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime_root = Path(temporary)
            _, issues = audit.validate_source(
                {
                    "kind": "runtime-source-manifest",
                    "name": "Fixture",
                    "sha256": "not-a-hash",
                },
                runtime_root,
                {"Fixture": {"name": "Fixture", "sha256": "a" * 64}},
                True,
            )
            self.assertTrue(any("valid pinned SHA-256" in issue for issue in issues))
            self.assertTrue(any("no artifact path" in issue for issue in issues))

    def test_renderer_requires_semantic_rollback_inventories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            client_root = root / "client"
            runtime_root = root / "runtime"
            target = client_root / "SquareEnix" / "PlayOnlineViewer"
            manifests = runtime_root / "manifests"
            target.mkdir(parents=True)
            manifests.mkdir(parents=True)

            hashes: dict[str, str] = {}
            for name in (
                "pol.exe",
                "d3d8.dll",
                "dgVoodoo.conf",
                "DXGI.DLL",
                "ReShade.ini",
                "preset.ini",
            ):
                path = target / name
                path.write_bytes(name.encode("ascii"))
                hashes[name] = audit.sha256_file(path)

            (manifests / "renderer-current.json").write_text(
                json.dumps(
                    {
                        "pol": {"sha256": hashes["pol.exe"]},
                        "dgVoodoo": {
                            "d3d8Sha256": hashes["d3d8.dll"],
                            "configSha256": hashes["dgVoodoo.conf"],
                        },
                        "reShade": {
                            "dxgiSha256": hashes["DXGI.DLL"],
                            "iniSha256": hashes["ReShade.ini"],
                            "presetPath": ".\\preset.ini",
                            "presetSha256": hashes["preset.ini"],
                            "enabledTechniques": ["Fixture@fixture.fx"],
                        },
                    }
                ),
                encoding="utf-8",
            )
            (manifests / "dg.json").write_text(
                json.dumps(
                    {
                        "Rollback": "Remove installed files.",
                        "Installed": [
                            {"Name": "D3D8.dll"},
                            {"Name": "dgVoodoo.conf"},
                        ],
                    }
                ),
                encoding="utf-8",
            )
            reshade_path = manifests / "reshade.json"
            reshade = {
                "rollback": "Move created files to backup.",
                "removeIfPresent": [
                    "dxgi.dll",
                    "ReShade.ini",
                    "ReShadePreset.ini",
                    "reshade-shaders",
                ],
                "preserve": ["d3d8.dll", "dgVoodoo.conf", "pol.exe"],
            }
            reshade_path.write_text(json.dumps(reshade), encoding="utf-8")
            contract = {
                "currentManifestRelativePath": "manifests/renderer-current.json",
                "gates": {
                    "dgvoodoo2": {
                        "component": "dgVoodoo2",
                        "requiredInstalledEntries": ["D3D8.dll", "dgVoodoo.conf"],
                        "rollbackManifestRelativePaths": ["manifests/dg.json"],
                    },
                    "reshade": {
                        "component": "ReShade",
                        "requiredPresetRelativePath": "preset.ini",
                        "requiredEnabledTechniques": ["Fixture@fixture.fx"],
                        "requiredRemovalEntries": [
                            "dxgi.dll",
                            "ReShade.ini",
                            "ReShadePreset.ini",
                            "reshade-shaders",
                        ],
                        "requiredPreserveEntries": [
                            "d3d8.dll",
                            "dgVoodoo.conf",
                            "pol.exe",
                        ],
                        "rollbackManifestRelativePaths": ["manifests/reshade.json"],
                    },
                },
            }

            result, issues = audit.audit_renderer(client_root, runtime_root, contract)
            self.assertEqual(issues, [])
            self.assertEqual(result["status"], "passed")

            reshade["removeIfPresent"].remove("reshade-shaders")
            reshade_path.write_text(json.dumps(reshade), encoding="utf-8")
            result, issues = audit.audit_renderer(client_root, runtime_root, contract)
            self.assertEqual(result["gates"]["reshade"]["status"], "failed")
            self.assertTrue(
                any("removal inventory missing" in issue for issue in issues)
            )

            reshade["removeIfPresent"].append("reshade-shaders")
            reshade_path.write_text(json.dumps(reshade), encoding="utf-8")
            current = json.loads((manifests / "renderer-current.json").read_text())
            del current["reShade"]["presetPath"]
            (manifests / "renderer-current.json").write_text(
                json.dumps(current), encoding="utf-8"
            )
            result, issues = audit.audit_renderer(client_root, runtime_root, contract)
            self.assertEqual(result["status"], "failed")
            self.assertTrue(any("active preset mismatch" in issue for issue in issues))

    def test_native_proofs_reject_reused_screenshot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime_root = root / "runtime"
            client_root = root / "client"
            manifests = runtime_root / "manifests"
            screenshots = runtime_root / "screenshots"
            native_root = client_root / "Windower" / "screenshots"
            manifests.mkdir(parents=True)
            screenshots.mkdir(parents=True)
            native_root.mkdir(parents=True)

            proof_paths: dict[str, Path] = {}
            for index, gate in enumerate(audit.REQUIRED_NATIVE_PROOF_GATES, 1):
                # JPEG SOI, a unique COM segment, SOF0 for 2560x1600, and EOI.
                image_bytes = (
                    b"\xff\xd8\xff\xfe\x00\x03"
                    + bytes([index])
                    + b"\xff\xc0\x00\x0b\x08\x06\x40\x0a\x00\x01\x01\x11\x00\xff\xd9"
                )
                copied = screenshots / f"{gate}.jpg"
                native = native_root / f"{gate}.jpg"
                copied.write_bytes(image_bytes)
                native.write_bytes(image_bytes)
                captured = audit.datetime.fromtimestamp(
                    native.stat().st_mtime, audit.timezone.utc
                ).isoformat()
                metadata_path = manifests / f"{gate}.json"
                metadata_path.write_text(
                    json.dumps(
                        {
                            "CaptureMode": "WindowerNativeScreenshot",
                            "CaptureBridgeVersion": "1.2.0",
                            "ControlMode": "BackgroundBridge",
                            "PreviousForegroundRestored": True,
                            "EvidenceGate": gate,
                            "SessionId": "windower-1234-fixture",
                            "ClientProcessId": 1234,
                            "ClientProcessName": "xiloader",
                            "ClientProcessStartedAtUtc": "2026-07-19T02:00:00+00:00",
                            "RequestId": f"{index:032x}",
                            "RequestAcknowledged": True,
                            "CapturedAtUtc": captured,
                            "NativeLastWriteTimeUtc": captured,
                            "NativePath": str(native),
                            "CopiedPath": str(copied),
                            "ImageWidth": 2560,
                            "ImageHeight": 1600,
                            "ScreenshotSha256": audit.sha256_file(copied),
                            "MetadataPath": str(metadata_path),
                        }
                    ),
                    encoding="utf-8",
                )
                proof_paths[gate] = metadata_path

            contract = {"nativeProofGates": list(audit.REQUIRED_NATIVE_PROOF_GATES)}
            results, issues, warnings = audit.audit_native_proofs(
                contract, proof_paths, True, runtime_root, client_root
            )
            self.assertEqual(issues, [])
            self.assertEqual(warnings, [])
            self.assertTrue(
                all(value["status"] == "passed" for value in results.values())
            )

            second_gate = audit.REQUIRED_NATIVE_PROOF_GATES[1]
            first_gate = audit.REQUIRED_NATIVE_PROOF_GATES[0]
            second_metadata = json.loads(proof_paths[second_gate].read_text())
            first_metadata = json.loads(proof_paths[first_gate].read_text())
            for key in ("CopiedPath", "NativePath", "ScreenshotSha256"):
                second_metadata[key] = first_metadata[key]
            proof_paths[second_gate].write_text(
                json.dumps(second_metadata), encoding="utf-8"
            )
            _, issues, _ = audit.audit_native_proofs(
                contract, proof_paths, True, runtime_root, client_root
            )
            self.assertTrue(any("reused" in issue for issue in issues))

    def test_native_contract_cannot_omit_required_gates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, issues, _ = audit.audit_native_proofs(
                {"nativeProofGates": []}, {}, False, root / "runtime", root / "client"
            )
            self.assertTrue(any("exactly" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
