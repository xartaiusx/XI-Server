#!/usr/bin/env python3
"""Audit Mochirii's live client graphics stack without tracking client assets.

The report is intentionally written outside Git.  It records hashes and source
provenance for active XIPivot DATs, verifies first-hit collision ownership,
checks XIView's direct-DAT replacements and stock rollback copies, and validates
the static dgVoodoo2/ReShade rollback gates.  Client-visible acceptance still
requires separately captured Windower-native proof metadata.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

CONTRACT_RELATIVE_PATH = Path("restore/manifests/client-graphics-gates.manifest.json")
DIRECT_DAT_RELATIVE_PATH = Path("restore/manifests/client-direct-dat.manifest.json")
ADDRESSABLE_DAT_RE = re.compile(r"^rom\d*/\d+/\d+\.dat$", re.IGNORECASE)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REQUEST_ID_RE = re.compile(r"^[0-9a-f]{32}$")
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$")
REQUIRED_NATIVE_PROOF_GATES = (
    "xipivot",
    "jasmint",
    "remapster",
    "dgvoodoo2",
    "reshade",
)
REQUIRED_RENDERER_GATES = {"dgvoodoo2", "reshade"}


@dataclass(frozen=True)
class DatLayer:
    overlay: str
    relative_path: str
    normalized_path: str
    bytes: int
    sha256: str
    source_name: str


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return data


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_dat_path(value: str | Path) -> str:
    return str(value).replace("\\", "/").strip("/").casefold()


def display_dat_path(value: str | Path) -> str:
    return str(value).replace("\\", "/").strip("/")


def display_relative_path(value: str | Path) -> str:
    normalized = display_dat_path(value)
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def resolve_relative(root: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    relative = Path(normalized)
    if (
        "\x00" in value
        or re.match(r"^[A-Za-z]:", normalized)
        or normalized.startswith("/")
        or relative.is_absolute()
        or ".." in relative.parts
    ):
        raise ValueError(f"unsafe {label}: {value!r}")
    resolved_root = root.resolve()
    resolved = (resolved_root / relative).resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise ValueError(f"{label} escaped its root: {value!r}") from exc
    return resolved


def is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def validate_overlay_name(value: Any) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"invalid XIPivot overlay name: {value!r}")
    if value in {".", ".."} or not re.fullmatch(r"[^/\\:]+", value):
        raise ValueError(f"unsafe XIPivot overlay name: {value!r}")
    return value


def parse_overlay_order(settings_path: Path) -> list[str]:
    root = ET.parse(settings_path).getroot()
    elements = root.findall(".//overlays")
    if len(elements) != 1 or not elements[0].text:
        raise ValueError(
            f"XIPivot settings must define exactly one overlays value: {settings_path}"
        )
    raw_names = elements[0].text.split(",")
    if any(not name.strip() for name in raw_names):
        raise ValueError("XIPivot settings contain a blank overlay name")
    overlays = [validate_overlay_name(name.strip()) for name in raw_names]
    normalized = [name.casefold() for name in overlays]
    if len(normalized) != len(set(normalized)):
        raise ValueError("XIPivot settings contain duplicate overlay names")
    return overlays


def iter_dat_files(root: Path) -> Iterable[Path]:
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"XIPivot DAT trees may not contain symlinks: {path}")
        if not is_within(path, root):
            raise ValueError(f"XIPivot DAT path escaped its overlay root: {path}")
        if path.is_file() and path.suffix.casefold() == ".dat":
            yield path


def tree_digest(layers: list[DatLayer]) -> str:
    digest = hashlib.sha256()
    for layer in sorted(layers, key=lambda item: item.normalized_path):
        digest.update(layer.normalized_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(layer.bytes).encode("ascii"))
        digest.update(b"\0")
        digest.update(layer.sha256.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def scan_overlay(
    dat_root: Path,
    overlay_contract: dict[str, Any],
) -> tuple[list[DatLayer], dict[str, Any], list[str]]:
    issues: list[str] = []
    try:
        name = validate_overlay_name(overlay_contract.get("name"))
    except ValueError as exc:
        return [], {}, [str(exc)]

    declared_overlay_root = dat_root / name
    if declared_overlay_root.is_symlink():
        return (
            [],
            {"name": name, "present": True},
            [f"XIPivot overlay directory may not be a symlink: {name}"],
        )
    overlay_root = resolve_relative(dat_root, name, "XIPivot overlay directory")
    if not overlay_root.is_dir():
        return (
            [],
            {"name": name, "present": False},
            [f"missing active overlay directory: {name}"],
        )

    source = overlay_contract.get("source", {})
    source_name = (
        source.get("name", "unrecorded") if isinstance(source, dict) else "unrecorded"
    )
    try:
        discovered = sorted(
            iter_dat_files(overlay_root),
            key=lambda path: normalize_dat_path(path.relative_to(overlay_root)),
        )
    except ValueError as exc:
        return [], {"name": name, "present": True}, [str(exc)]
    unaddressable = [
        display_dat_path(path.relative_to(overlay_root))
        for path in discovered
        if not ADDRESSABLE_DAT_RE.fullmatch(
            display_dat_path(path.relative_to(overlay_root))
        )
    ]
    paths = [
        path
        for path in discovered
        if ADDRESSABLE_DAT_RE.fullmatch(
            display_dat_path(path.relative_to(overlay_root))
        )
    ]
    if unaddressable:
        issues.append(
            f"overlay {name} contains unaddressable DAT paths: "
            + ", ".join(unaddressable)
        )
    layers: list[DatLayer] = []
    seen: set[str] = set()
    duplicate_paths: list[str] = []
    for path in paths:
        relative = display_dat_path(path.relative_to(overlay_root))
        normalized = normalize_dat_path(relative)
        if normalized in seen:
            duplicate_paths.append(relative)
        seen.add(normalized)
        layers.append(
            DatLayer(
                overlay=name,
                relative_path=relative,
                normalized_path=normalized,
                bytes=path.stat().st_size,
                sha256=sha256_file(path),
                source_name=str(source_name),
            )
        )

    actual_count = len(layers)
    expected_count = overlay_contract.get("expectedDatCount")
    if actual_count != expected_count:
        issues.append(
            f"overlay DAT count mismatch for {name}: expected {expected_count}, actual {actual_count}"
        )
    if duplicate_paths:
        issues.append(
            f"overlay {name} contains case-insensitive duplicate DAT paths: "
            + ", ".join(sorted(duplicate_paths))
        )

    representative = overlay_contract.get("representativeDat")
    if (
        not isinstance(representative, str)
        or normalize_dat_path(representative) not in seen
    ):
        issues.append(
            f"overlay representative DAT is missing for {name}: {representative!r}"
        )

    actual_tree = tree_digest(layers)
    expected_tree = overlay_contract.get("expectedTreeSha256")
    if not isinstance(expected_tree, str) or len(expected_tree) != 64:
        issues.append(f"overlay {name} has no pinned expectedTreeSha256")
    elif actual_tree != expected_tree.casefold():
        issues.append(
            f"overlay tree hash mismatch for {name}: expected {expected_tree}, actual {actual_tree}"
        )

    summary = {
        "name": name,
        "present": True,
        "datCount": actual_count,
        "datBytes": sum(layer.bytes for layer in layers),
        "treeSha256": actual_tree,
        "representativeDat": representative,
        "source": source,
        "duplicateNormalizedPaths": sorted(duplicate_paths),
        "unaddressableDatPaths": unaddressable,
    }
    return layers, summary, issues


def validate_source(
    source: dict[str, Any],
    runtime_root: Path,
    runtime_sources: dict[str, dict[str, Any]],
    verify_artifact: bool,
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []
    kind = source.get("kind")
    name = source.get("name")
    expected_sha_raw = source.get("sha256")
    expected_sha = (
        expected_sha_raw.casefold() if isinstance(expected_sha_raw, str) else ""
    )
    status: dict[str, Any] = {
        "kind": kind,
        "name": name,
        "expectedSha256": expected_sha,
        "metadataMatched": False,
        "artifactPresent": False,
        "artifactHashVerified": False,
    }
    if not SHA256_RE.fullmatch(expected_sha):
        issues.append(f"source {name!r} has no valid pinned SHA-256")

    artifact_path: Path | None = None
    if kind == "runtime-source-manifest":
        entry = runtime_sources.get(str(name))
        if entry is None:
            issues.append(f"runtime source manifest is missing source: {name}")
            return status, issues
        recorded_sha_raw = entry.get("sha256")
        recorded_sha = (
            recorded_sha_raw.casefold() if isinstance(recorded_sha_raw, str) else ""
        )
        status["recordedSha256"] = recorded_sha
        status["metadataMatched"] = recorded_sha == expected_sha
        if not status["metadataMatched"]:
            issues.append(
                f"source hash metadata mismatch for {name}: expected {expected_sha}, recorded {recorded_sha}"
            )
        raw_path = entry.get("path")
        if isinstance(raw_path, str) and raw_path:
            declared_path = Path(raw_path)
            candidate = declared_path.resolve()
            if declared_path.is_symlink():
                issues.append(f"source artifact may not be a symlink for {name}")
            elif is_within(candidate, runtime_root):
                artifact_path = candidate
            else:
                issues.append(f"source artifact escaped runtime root for {name}")
        else:
            issues.append(f"runtime source manifest has no artifact path for {name}")
    elif kind == "runtime-backup":
        relative = source.get("runtimeRelativePath")
        if isinstance(relative, str) and relative:
            try:
                declared_path = runtime_root / relative.replace("\\", "/")
                candidate = resolve_relative(
                    runtime_root, relative, "runtime backup path"
                )
                if declared_path.is_symlink():
                    issues.append(f"source artifact may not be a symlink for {name}")
                else:
                    artifact_path = candidate
            except ValueError as exc:
                issues.append(str(exc))
        else:
            issues.append(f"runtime backup has no artifact path for {name}")
        status["metadataMatched"] = bool(SHA256_RE.fullmatch(expected_sha))
    else:
        issues.append(f"unsupported graphics source kind for {name}: {kind!r}")
        return status, issues

    if artifact_path is not None:
        status["artifactPath"] = str(artifact_path)
        status["artifactPresent"] = artifact_path.is_file()
        status["artifactBytes"] = (
            artifact_path.stat().st_size if artifact_path.is_file() else None
        )
        if not artifact_path.is_file():
            issues.append(f"source artifact is missing for {name}")
        elif verify_artifact:
            actual_sha = sha256_file(artifact_path)
            status["artifactSha256"] = actual_sha
            status["artifactHashVerified"] = actual_sha == expected_sha
            if actual_sha != expected_sha:
                issues.append(
                    f"source artifact hash mismatch for {name}: expected {expected_sha}, actual {actual_sha}"
                )
    return status, issues


def classify_collisions(
    layers_by_path: dict[str, list[DatLayer]],
    allowed_pairs: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], Counter[tuple[str, str]], list[str]]:
    issues: list[str] = []
    allowed = {
        (str(entry.get("owner")), str(entry.get("shadowed"))): entry.get(
            "expectedPaths"
        )
        for entry in allowed_pairs
    }
    actual_pairs: Counter[tuple[str, str]] = Counter()
    collisions: list[dict[str, Any]] = []
    for normalized, layers in sorted(layers_by_path.items()):
        if len(layers) < 2:
            continue
        owner = layers[0]
        unexpected_pairs: list[str] = []
        for shadowed in layers[1:]:
            pair = (owner.overlay, shadowed.overlay)
            actual_pairs[pair] += 1
            if pair not in allowed:
                unexpected_pairs.append(f"{pair[0]}>{pair[1]}")
        collisions.append(
            {
                "relativePath": owner.relative_path,
                "normalizedPath": normalized,
                "owner": owner.overlay,
                "layers": [
                    {
                        "overlay": layer.overlay,
                        "relativePath": layer.relative_path,
                        "bytes": layer.bytes,
                        "sha256": layer.sha256,
                        "source": layer.source_name,
                    }
                    for layer in layers
                ],
                "allHashesEqual": len({layer.sha256 for layer in layers}) == 1,
                "status": "allowed" if not unexpected_pairs else "unexplained",
                "unexpectedPairs": unexpected_pairs,
            }
        )

    for pair, expected_count in sorted(allowed.items()):
        actual_count = actual_pairs[pair]
        if actual_count != expected_count:
            issues.append(
                f"collision pair count mismatch for {pair[0]}>{pair[1]}: "
                f"expected {expected_count}, actual {actual_count}"
            )
    for pair, actual_count in sorted(actual_pairs.items()):
        if pair not in allowed:
            issues.append(
                f"unexplained collision pair {pair[0]}>{pair[1]} on {actual_count} path(s)"
            )
    return collisions, actual_pairs, issues


def index_direct_dat_entries(
    values: Any,
    relative_field: str,
    hash_fields: tuple[str, ...],
    label: str,
) -> tuple[list[tuple[str, str, dict[str, Any]]], dict[str, dict[str, Any]], list[str]]:
    issues: list[str] = []
    ordered: list[tuple[str, str, dict[str, Any]]] = []
    indexed: dict[str, dict[str, Any]] = {}
    if not isinstance(values, list) or not values:
        return ordered, indexed, [f"{label} files must be a non-empty object list"]
    for entry in values:
        if not isinstance(entry, dict):
            issues.append(f"{label} file entries must be objects")
            continue
        raw_relative = entry.get(relative_field)
        relative = (
            display_dat_path(raw_relative) if isinstance(raw_relative, str) else ""
        )
        normalized = normalize_dat_path(relative)
        if not ADDRESSABLE_DAT_RE.fullmatch(relative):
            issues.append(f"{label} has an invalid DAT path: {raw_relative!r}")
            continue
        if normalized in indexed:
            issues.append(f"{label} contains a duplicate DAT path: {relative}")
            continue
        for field in hash_fields:
            value = entry.get(field)
            if not isinstance(value, str) or not SHA256_RE.fullmatch(value.casefold()):
                issues.append(f"{label} has no valid {field} for {relative}")
        size = entry.get("bytes")
        if not isinstance(size, int) or size <= 0:
            issues.append(f"{label} has no valid byte count for {relative}")
        ordered.append((normalized, relative, entry))
        indexed[normalized] = entry
    return ordered, indexed, issues


def audit_direct_dat(
    repo_root: Path,
    client_root: Path,
    runtime_root: Path,
    contract: dict[str, Any],
    layers_by_path: dict[str, list[DatLayer]],
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []
    direct_contract = contract.get("directDat", {})
    if not isinstance(direct_contract, dict):
        raise ValueError("directDat contract must be an object")
    manifest_path = repo_root / DIRECT_DAT_RELATIVE_PATH
    manifest = load_json(manifest_path)
    ffxi_root = resolve_relative(
        client_root, "SquareEnix/FINAL FANTASY XI", "FFXI DAT root"
    )
    rollback_relative = direct_contract.get("rollbackRootRelativePath")
    rollback_root = resolve_relative(
        runtime_root, rollback_relative, "direct DAT rollback root"
    )
    runtime_manifest_relative = direct_contract.get("runtimeManifestRelativePath")
    runtime_manifest_path = resolve_relative(
        runtime_root, runtime_manifest_relative, "direct DAT runtime manifest"
    )
    runtime_manifest = (
        load_json(runtime_manifest_path) if runtime_manifest_path.is_file() else {}
    )
    if manifest.get("schemaVersion") != 2:
        issues.append("XIView tracked direct-DAT manifest schemaVersion must be 2")
    if runtime_manifest.get("schemaVersion") != 1:
        issues.append("XIView runtime direct-DAT manifest schemaVersion must be 1")
    direct_owner = manifest.get("directOwner")
    if not isinstance(direct_owner, str) or not direct_owner:
        issues.append("XIView tracked direct-DAT owner is missing")
    rollback_instruction = runtime_manifest.get("rollback")
    if not isinstance(rollback_instruction, str) or not rollback_instruction.strip():
        issues.append("XIView runtime direct-DAT rollback instruction is missing")

    tracked_order, tracked_entries, tracked_issues = index_direct_dat_entries(
        manifest.get("files"),
        "relativePath",
        ("stockSha256", "replacementSha256"),
        "XIView tracked direct-DAT manifest",
    )
    runtime_order, runtime_entries, runtime_issues = index_direct_dat_entries(
        runtime_manifest.get("files"),
        "relative",
        ("stockSha256", "installedSha256", "sourceSha256"),
        "XIView runtime direct-DAT manifest",
    )
    issues.extend(tracked_issues)
    issues.extend(runtime_issues)
    if set(tracked_entries) != set(runtime_entries):
        issues.append(
            "XIView runtime direct-DAT path set does not match the tracked manifest"
        )
    expected_files = direct_contract.get("expectedFiles")
    if not isinstance(expected_files, int) or expected_files < 1:
        issues.append("XIView direct-DAT expectedFiles must be a positive integer")
    elif len(tracked_entries) != expected_files:
        issues.append(
            "XIView direct-DAT manifest file count mismatch: "
            f"expected {expected_files}, actual {len(tracked_entries)}"
        )
    if direct_contract.get("allowActiveOverlayOverlap") is not False:
        issues.append("XIView direct-DAT active overlay overlap must remain disabled")

    if issues:
        return {
            "owner": direct_owner,
            "files": [],
            "activeOverlayOverlaps": [],
            "rollbackRootPresent": rollback_root.is_dir(),
            "runtimeManifestPresent": runtime_manifest_path.is_file(),
            "trackedPathCount": len(tracked_entries),
            "runtimePathCount": len(runtime_entries),
            "status": "failed",
        }, issues

    files: list[dict[str, Any]] = []
    overlaps: list[dict[str, Any]] = []
    for normalized, relative, entry in tracked_order:
        installed = resolve_relative(ffxi_root, relative, "XIView installed DAT")
        backup = resolve_relative(rollback_root, relative, "XIView rollback DAT")
        expected_installed = entry["replacementSha256"].casefold()
        expected_backup = entry["stockSha256"].casefold()
        installed_sha = sha256_file(installed) if installed.is_file() else None
        backup_sha = sha256_file(backup) if backup.is_file() else None
        runtime_entry = runtime_entries.get(normalized)
        runtime_backup_raw = runtime_entry.get("backup") if runtime_entry else None
        runtime_backup = (
            Path(runtime_backup_raw).resolve()
            if isinstance(runtime_backup_raw, str) and runtime_backup_raw
            else None
        )
        runtime_matched = bool(
            runtime_entry
            and runtime_entry["installedSha256"].casefold() == expected_installed
            and runtime_entry["sourceSha256"].casefold() == expected_installed
            and runtime_entry["stockSha256"].casefold() == expected_backup
            and runtime_entry.get("owner") == direct_owner
            and runtime_entry.get("bytes") == entry.get("bytes")
            and runtime_backup == backup
            and not Path(runtime_backup_raw).is_symlink()
        )

        if installed_sha != expected_installed:
            issues.append(f"XIView installed DAT mismatch: {relative}")
        if backup_sha != expected_backup:
            issues.append(f"XIView stock rollback DAT mismatch: {relative}")
        if not runtime_matched:
            issues.append(f"XIView runtime install manifest mismatch: {relative}")

        active_layers = layers_by_path.get(normalized, [])
        if active_layers:
            overlaps.append(
                {
                    "relativePath": relative,
                    "directSha256": installed_sha,
                    "activeLayers": [
                        {
                            "overlay": layer.overlay,
                            "sha256": layer.sha256,
                            "sameBytesAsDirect": layer.sha256 == installed_sha,
                        }
                        for layer in active_layers
                    ],
                }
            )
        files.append(
            {
                "relativePath": relative,
                "installedSha256": installed_sha,
                "expectedInstalledSha256": expected_installed,
                "rollbackSha256": backup_sha,
                "expectedRollbackSha256": expected_backup,
                "runtimeManifestMatched": runtime_matched,
                "status": (
                    "passed"
                    if installed_sha == expected_installed
                    and backup_sha == expected_backup
                    and runtime_matched
                    else "failed"
                ),
            }
        )

    if overlaps:
        issues.append(
            f"{len(overlaps)} XIView direct-DAT path(s) also exist in active XIPivot overlays"
        )
    return {
        "owner": direct_owner,
        "files": files,
        "activeOverlayOverlaps": overlaps,
        "rollbackRootPresent": rollback_root.is_dir(),
        "runtimeManifestPresent": runtime_manifest_path.is_file(),
        "status": (
            "passed"
            if not issues
            and len(files) == expected_files
            and all(item["status"] == "passed" for item in files)
            else "failed"
        ),
    }, issues


def audit_renderer(
    client_root: Path,
    runtime_root: Path,
    renderer_contract: dict[str, Any],
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []
    gates_raw = renderer_contract.get("gates")
    if not isinstance(gates_raw, dict) or set(gates_raw) != REQUIRED_RENDERER_GATES:
        issues.append(
            "renderer contract must define exactly the dgvoodoo2 and reshade gates"
        )
    gates = gates_raw if isinstance(gates_raw, dict) else {}

    current_path = resolve_relative(
        runtime_root,
        renderer_contract.get("currentManifestRelativePath"),
        "renderer current manifest",
    )
    if not current_path.is_file():
        return {"status": "failed"}, ["missing renderer-current runtime manifest"]
    current = load_json(current_path)
    target_root = resolve_relative(
        client_root, "SquareEnix/PlayOnlineViewer", "PlayOnlineViewer root"
    )
    component_failures: Counter[str] = Counter()

    checks: list[tuple[str, Any, str]] = [
        ("pol.exe", current.get("pol", {}).get("sha256"), "pol"),
        ("d3d8.dll", current.get("dgVoodoo", {}).get("d3d8Sha256"), "dgVoodoo2"),
        ("dgVoodoo.conf", current.get("dgVoodoo", {}).get("configSha256"), "dgVoodoo2"),
        ("DXGI.DLL", current.get("reShade", {}).get("dxgiSha256"), "ReShade"),
        ("ReShade.ini", current.get("reShade", {}).get("iniSha256"), "ReShade"),
    ]

    reshade_contract = gates.get("reshade", {})
    if not isinstance(reshade_contract, dict):
        reshade_contract = {}
    required_preset = reshade_contract.get("requiredPresetRelativePath")
    active_preset = current.get("reShade", {}).get("presetPath")
    if not isinstance(required_preset, str) or not required_preset:
        issues.append("ReShade gate has no requiredPresetRelativePath")
    else:
        normalized_required_preset = display_relative_path(required_preset)
        normalized_active_preset = (
            display_relative_path(active_preset)
            if isinstance(active_preset, str) and active_preset
            else None
        )
        if (
            normalized_active_preset is None
            or normalized_active_preset.casefold()
            != normalized_required_preset.casefold()
        ):
            issues.append(
                "ReShade active preset mismatch: "
                f"expected {normalized_required_preset}, actual {normalized_active_preset}"
            )
            component_failures["ReShade"] += 1
        checks.append(
            (
                normalized_required_preset,
                current.get("reShade", {}).get("presetSha256"),
                "ReShade",
            )
        )

    required_techniques = reshade_contract.get("requiredEnabledTechniques")
    active_techniques = current.get("reShade", {}).get("enabledTechniques")
    if (
        not isinstance(required_techniques, list)
        or not required_techniques
        or not all(isinstance(value, str) and value for value in required_techniques)
    ):
        issues.append("ReShade gate has no valid requiredEnabledTechniques")
        required_techniques = []
    if active_techniques != required_techniques:
        issues.append(
            "ReShade enabled-technique list mismatch: "
            f"expected {required_techniques}, actual {active_techniques}"
        )
        component_failures["ReShade"] += 1

    file_results: list[dict[str, Any]] = []
    for relative, expected, component in checks:
        try:
            path = resolve_relative(
                target_root, relative, f"{component} installed file"
            )
        except ValueError as exc:
            issues.append(str(exc))
            component_failures[component] += 1
            file_results.append(
                {
                    "component": component,
                    "relativePath": relative,
                    "expectedSha256": expected,
                    "actualSha256": None,
                    "status": "failed",
                }
            )
            continue
        expected_sha = expected.casefold() if isinstance(expected, str) else ""
        actual = sha256_file(path) if path.is_file() else None
        matched = bool(SHA256_RE.fullmatch(expected_sha) and actual == expected_sha)
        if not matched:
            issues.append(f"{component} installed file mismatch: {relative}")
            component_failures[component] += 1
        file_results.append(
            {
                "component": component,
                "relativePath": relative,
                "expectedSha256": expected_sha,
                "actualSha256": actual,
                "status": "passed" if matched else "failed",
            }
        )

    gate_results: dict[str, Any] = {}
    for gate_name in sorted(REQUIRED_RENDERER_GATES):
        gate_issue_start = len(issues)
        gate_contract = gates.get(gate_name, {})
        if not isinstance(gate_contract, dict):
            gate_contract = {}
        rollback_values = gate_contract.get("rollbackManifestRelativePaths")
        if not isinstance(rollback_values, list) or not rollback_values:
            issues.append(f"{gate_name} must declare rollback manifests")
            rollback_values = []
        rollback_paths = [
            resolve_relative(runtime_root, relative, f"{gate_name} rollback manifest")
            for relative in rollback_values
        ]
        missing = [str(path.name) for path in rollback_paths if not path.is_file()]
        if missing:
            issues.append(
                f"{gate_name} rollback manifest(s) missing: {', '.join(missing)}"
            )
        documents: list[dict[str, Any]] = []
        invalid: list[str] = []
        for path in rollback_paths:
            if not path.is_file():
                continue
            try:
                documents.append(load_json(path))
            except (OSError, ValueError, json.JSONDecodeError):
                invalid.append(path.name)
        if invalid:
            issues.append(
                f"{gate_name} rollback manifest(s) invalid: {', '.join(invalid)}"
            )

        instructions = [
            value
            for document in documents
            for key in ("rollback", "Rollback")
            if isinstance((value := document.get(key)), str) and value.strip()
        ]
        if gate_contract.get("requireRollbackInstruction", True) and not instructions:
            issues.append(f"{gate_name} rollback instruction is missing")

        required_removals = {
            str(value).casefold()
            for value in gate_contract.get("requiredRemovalEntries", [])
        }
        recorded_removals = {
            str(value).casefold()
            for document in documents
            for value in document.get("removeIfPresent", [])
            if isinstance(value, str)
        }
        missing_removals = sorted(required_removals - recorded_removals)
        if missing_removals:
            issues.append(
                f"{gate_name} rollback removal inventory missing: "
                + ", ".join(missing_removals)
            )

        required_preserves = {
            str(value).casefold()
            for value in gate_contract.get("requiredPreserveEntries", [])
        }
        recorded_preserves = {
            str(value).casefold()
            for document in documents
            for value in document.get("preserve", [])
            if isinstance(value, str)
        }
        missing_preserves = sorted(required_preserves - recorded_preserves)
        if missing_preserves:
            issues.append(
                f"{gate_name} rollback preserve inventory missing: "
                + ", ".join(missing_preserves)
            )

        required_installed = {
            str(value).casefold()
            for value in gate_contract.get("requiredInstalledEntries", [])
        }
        recorded_installed = {
            str(item.get("Name")).casefold()
            for document in documents
            for item in document.get("Installed", [])
            if isinstance(item, dict) and isinstance(item.get("Name"), str)
        }
        missing_installed = sorted(required_installed - recorded_installed)
        if missing_installed:
            issues.append(
                f"{gate_name} installed inventory missing: "
                + ", ".join(missing_installed)
            )

        rollback_contract_passed = not (
            missing
            or invalid
            or (
                gate_contract.get("requireRollbackInstruction", True)
                and not instructions
            )
            or missing_removals
            or missing_preserves
            or missing_installed
        )
        gate_contract_issues = len(issues) != gate_issue_start
        gate_results[gate_name] = {
            "installedFilesPassed": component_failures[gate_contract.get("component")]
            == 0,
            "rollbackManifestsPresent": not missing and not invalid,
            "rollbackManifestNames": [path.name for path in rollback_paths],
            "rollbackInstructionPresent": bool(instructions),
            "removalInventoryPassed": not missing_removals,
            "preserveInventoryPassed": not missing_preserves,
            "installedInventoryPassed": not missing_installed,
            "status": (
                "passed"
                if component_failures[gate_contract.get("component")] == 0
                and rollback_contract_passed
                and not gate_contract_issues
                else "failed"
            ),
        }

    return {
        "currentManifest": str(current_path),
        "files": file_results,
        "activePreset": active_preset,
        "requiredPreset": required_preset,
        "enabledTechniques": active_techniques,
        "requiredEnabledTechniques": required_techniques,
        "gates": gate_results,
        "status": (
            "passed"
            if not issues
            and file_results
            and all(item["status"] == "passed" for item in file_results)
            and set(gate_results) == REQUIRED_RENDERER_GATES
            and all(item["status"] == "passed" for item in gate_results.values())
            else "failed"
        ),
    }, issues


def read_image_dimensions(path: Path) -> tuple[int, int]:
    """Read trusted dimensions from PNG, BMP, or JPEG bytes without metadata."""
    with path.open("rb") as handle:
        header = handle.read(26)
        if header.startswith(b"\x89PNG\r\n\x1a\n") and header[12:16] == b"IHDR":
            width = int.from_bytes(header[16:20], "big")
            height = int.from_bytes(header[20:24], "big")
            if width > 0 and height > 0:
                return width, height
        if header.startswith(b"BM") and len(header) >= 24:
            width = int.from_bytes(header[18:22], "little", signed=True)
            height = abs(int.from_bytes(header[22:26], "little", signed=True))
            if width > 0 and height > 0:
                return width, height
        if not header.startswith(b"\xff\xd8"):
            raise ValueError(f"unsupported or malformed proof image: {path}")

        handle.seek(2)
        start_of_frame_markers = {
            0xC0,
            0xC1,
            0xC2,
            0xC3,
            0xC5,
            0xC6,
            0xC7,
            0xC9,
            0xCA,
            0xCB,
            0xCD,
            0xCE,
            0xCF,
        }
        while True:
            prefix = handle.read(1)
            if not prefix:
                break
            if prefix != b"\xff":
                continue
            marker_byte = handle.read(1)
            while marker_byte == b"\xff":
                marker_byte = handle.read(1)
            if not marker_byte:
                break
            marker = marker_byte[0]
            if marker in {0x01, 0xD8} or 0xD0 <= marker <= 0xD7:
                continue
            if marker in {0xD9, 0xDA}:
                break
            length_raw = handle.read(2)
            if len(length_raw) != 2:
                break
            segment_length = int.from_bytes(length_raw, "big")
            if segment_length < 2:
                break
            if marker in start_of_frame_markers:
                frame = handle.read(5)
                if len(frame) != 5:
                    break
                height = int.from_bytes(frame[1:3], "big")
                width = int.from_bytes(frame[3:5], "big")
                if width > 0 and height > 0:
                    return width, height
                break
            handle.seek(segment_length - 2, 1)
    raise ValueError(f"could not decode proof image dimensions: {path}")


def parse_capture_timestamp(value: Any) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValueError("CapturedAtUtc must be a timezone-aware ISO-8601 timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("CapturedAtUtc must include a timezone")
    return parsed.astimezone(timezone.utc)


def audit_native_proofs(
    contract: dict[str, Any],
    proof_paths: dict[str, Path],
    require_proofs: bool,
    runtime_root: Path,
    client_root: Path,
) -> tuple[dict[str, Any], list[str], list[str]]:
    issues: list[str] = []
    warnings: list[str] = []
    results: dict[str, Any] = {}
    declared = contract.get("nativeProofGates")
    required = list(REQUIRED_NATIVE_PROOF_GATES)
    if declared != required:
        issues.append(
            "nativeProofGates must contain exactly, in order: " + ", ".join(required)
        )
    extra_gates = sorted(set(proof_paths) - set(required))
    if extra_gates:
        issues.append("undeclared native proof gate(s): " + ", ".join(extra_gates))

    metadata_root = resolve_relative(
        runtime_root, "manifests", "native proof metadata root"
    )
    screenshot_root = resolve_relative(
        runtime_root, "screenshots", "native proof screenshot root"
    )
    native_screenshot_root = resolve_relative(
        client_root, "Windower/screenshots", "Windower screenshot root"
    )
    for declared_root, label in (
        (runtime_root / "manifests", "runtime manifests"),
        (runtime_root / "screenshots", "runtime screenshots"),
        (client_root / "Windower" / "screenshots", "Windower screenshots"),
    ):
        if declared_root.is_symlink():
            raise ValueError(f"{label} root may not be a symlink")
    used_metadata_paths: set[Path] = set()
    used_screenshot_paths: set[Path] = set()
    used_screenshot_hashes: set[str] = set()
    used_request_ids: set[str] = set()
    session_ids: set[str] = set()
    process_ids: set[int] = set()
    process_start_times: set[datetime] = set()
    capture_times: list[datetime] = []
    for gate in required:
        path = proof_paths.get(gate)
        if path is None:
            message = f"missing Windower-native proof metadata for gate: {gate}"
            (issues if require_proofs else warnings).append(message)
            results[gate] = {"status": "missing"}
            continue
        resolved = path.resolve()
        gate_issues: list[str] = []
        if path.is_symlink() or not is_within(resolved, metadata_root):
            gate_issues.append(
                f"Windower-native proof metadata escaped runtime manifests for {gate}"
            )
        if resolved in used_metadata_paths:
            gate_issues.append(
                f"Windower-native proof metadata must be distinct for gate: {gate}"
            )
        used_metadata_paths.add(resolved)
        if not resolved.is_file():
            gate_issues.append(
                f"Windower-native proof metadata does not exist for {gate}"
            )
            issues.extend(gate_issues)
            results[gate] = {"status": "failed"}
            continue
        try:
            metadata = load_json(resolved)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            issues.extend(gate_issues)
            issues.append(f"invalid Windower-native proof JSON for {gate}: {exc}")
            results[gate] = {"status": "failed"}
            continue

        recorded_metadata_path = metadata.get("MetadataPath")
        if not isinstance(recorded_metadata_path, str) or (
            Path(recorded_metadata_path).resolve() != resolved
        ):
            gate_issues.append(f"proof metadata path is not self-consistent for {gate}")

        screenshot_raw = metadata.get("CopiedPath")
        screenshot = (
            Path(screenshot_raw).resolve()
            if isinstance(screenshot_raw, str) and screenshot_raw
            else None
        )
        actual_hash: str | None = None
        actual_width: int | None = None
        actual_height: int | None = None
        if screenshot is None:
            gate_issues.append(f"proof screenshot path is missing for {gate}")
        elif not is_within(screenshot, screenshot_root):
            gate_issues.append(
                f"proof screenshot escaped runtime screenshots for {gate}"
            )
        elif Path(screenshot_raw).is_symlink():
            gate_issues.append(f"proof screenshot may not be a symlink for {gate}")
        elif not screenshot.is_file():
            gate_issues.append(f"proof screenshot does not exist for {gate}")
        else:
            actual_hash = sha256_file(screenshot)
            try:
                actual_width, actual_height = read_image_dimensions(screenshot)
            except ValueError as exc:
                gate_issues.append(str(exc))
            if screenshot in used_screenshot_paths:
                gate_issues.append(f"proof screenshot path is reused for {gate}")
            if actual_hash in used_screenshot_hashes:
                gate_issues.append(f"proof screenshot bytes are reused for {gate}")
            used_screenshot_paths.add(screenshot)
            used_screenshot_hashes.add(actual_hash)

        expected_hash_raw = metadata.get("ScreenshotSha256")
        expected_hash = (
            expected_hash_raw.casefold() if isinstance(expected_hash_raw, str) else ""
        )
        if not SHA256_RE.fullmatch(expected_hash) or actual_hash != expected_hash:
            gate_issues.append(f"proof screenshot hash mismatch for {gate}")
        if (actual_width, actual_height) != (2560, 1600):
            gate_issues.append(
                f"proof screenshot dimensions are not 2560x1600 for {gate}: "
                f"{actual_width}x{actual_height}"
            )
        if (
            metadata.get("ImageWidth") != actual_width
            or metadata.get("ImageHeight") != actual_height
        ):
            gate_issues.append(f"proof image metadata dimensions mismatch for {gate}")

        native_raw = metadata.get("NativePath")
        native_path = (
            Path(native_raw).resolve()
            if isinstance(native_raw, str) and native_raw
            else None
        )
        native_hash: str | None = None
        native_mtime: datetime | None = None
        if native_path is None:
            gate_issues.append(f"native Windower screenshot path is missing for {gate}")
        elif not is_within(native_path, native_screenshot_root):
            gate_issues.append(
                f"native Windower screenshot escaped client root for {gate}"
            )
        elif Path(native_raw).is_symlink() or not native_path.is_file():
            gate_issues.append(f"native Windower screenshot is invalid for {gate}")
        else:
            native_hash = sha256_file(native_path)
            native_mtime = datetime.fromtimestamp(
                native_path.stat().st_mtime, timezone.utc
            )
            if native_hash != actual_hash:
                gate_issues.append(f"native and copied screenshots differ for {gate}")

        recorded_native_mtime: datetime | None = None
        try:
            recorded_native_mtime = parse_capture_timestamp(
                metadata.get("NativeLastWriteTimeUtc")
            )
        except (TypeError, ValueError) as exc:
            gate_issues.append(
                f"native screenshot timestamp is invalid for {gate}: {exc}"
            )
        if (
            native_mtime is not None
            and recorded_native_mtime is not None
            and abs((native_mtime - recorded_native_mtime).total_seconds()) > 1
        ):
            gate_issues.append(f"native screenshot timestamp mismatch for {gate}")

        request_id_raw = metadata.get("RequestId")
        request_id = (
            request_id_raw.casefold() if isinstance(request_id_raw, str) else ""
        )
        if not REQUEST_ID_RE.fullmatch(request_id):
            gate_issues.append(f"proof RequestId is invalid for {gate}")
        elif request_id in used_request_ids:
            gate_issues.append(f"proof RequestId is reused for {gate}")
        used_request_ids.add(request_id)

        session_id = metadata.get("SessionId")
        if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
            gate_issues.append(f"proof SessionId is invalid for {gate}")
        else:
            session_ids.add(session_id)
        if metadata.get("EvidenceGate") != gate:
            gate_issues.append(f"proof gate identity mismatch for {gate}")

        capture_time: datetime | None = None
        try:
            capture_time = parse_capture_timestamp(metadata.get("CapturedAtUtc"))
            capture_times.append(capture_time)
        except (TypeError, ValueError) as exc:
            gate_issues.append(f"proof capture timestamp is invalid for {gate}: {exc}")
        if (
            capture_time is not None
            and native_mtime is not None
            and abs((capture_time - native_mtime).total_seconds()) > 5
        ):
            gate_issues.append(f"native screenshot is not temporally tied to {gate}")

        process_id = metadata.get("ClientProcessId")
        if not isinstance(process_id, int) or process_id <= 0:
            gate_issues.append(f"proof client process id is invalid for {gate}")
        else:
            process_ids.add(process_id)
        process_started_at: datetime | None = None
        try:
            process_started_at = parse_capture_timestamp(
                metadata.get("ClientProcessStartedAtUtc")
            )
            process_start_times.add(process_started_at)
        except (TypeError, ValueError) as exc:
            gate_issues.append(
                f"proof client process start is invalid for {gate}: {exc}"
            )
        if metadata.get("ClientProcessName") != "xiloader":
            gate_issues.append(f"proof client process name is invalid for {gate}")
        if (
            capture_time is not None
            and process_started_at is not None
            and not timedelta(0)
            <= capture_time - process_started_at
            <= timedelta(hours=12)
        ):
            gate_issues.append(
                f"proof capture is outside the client process session for {gate}"
            )
        if metadata.get("CaptureMode") != "WindowerNativeScreenshot":
            gate_issues.append(f"proof capture mode is invalid for {gate}")
        bridge_version = metadata.get("CaptureBridgeVersion")
        if bridge_version not in {"1.1.0", "1.2.0"}:
            gate_issues.append(f"proof capture bridge version is invalid for {gate}")
        if (
            bridge_version == "1.2.0"
            and metadata.get("RequestAcknowledged") is not True
        ):
            gate_issues.append(f"proof request acknowledgement is missing for {gate}")
        if metadata.get("ControlMode") != "BackgroundBridge":
            gate_issues.append(f"proof control mode is invalid for {gate}")
        if metadata.get("PreviousForegroundRestored") is not True:
            gate_issues.append(f"proof did not restore previous foreground for {gate}")

        issues.extend(gate_issues)
        results[gate] = {
            "metadataPath": str(resolved),
            "screenshotPath": str(screenshot) if screenshot else None,
            "screenshotSha256": actual_hash,
            "nativeScreenshotPath": str(native_path) if native_path else None,
            "nativeScreenshotSha256": native_hash,
            "nativeLastWriteTimeUtc": (
                native_mtime.isoformat() if native_mtime is not None else None
            ),
            "evidenceGate": metadata.get("EvidenceGate"),
            "sessionId": session_id,
            "requestId": request_id,
            "capturedAtUtc": metadata.get("CapturedAtUtc"),
            "clientProcessId": process_id,
            "clientProcessName": metadata.get("ClientProcessName"),
            "clientProcessStartedAtUtc": metadata.get("ClientProcessStartedAtUtc"),
            "captureMode": metadata.get("CaptureMode"),
            "captureBridgeVersion": bridge_version,
            "requestAcknowledged": metadata.get("RequestAcknowledged"),
            "controlMode": metadata.get("ControlMode"),
            "previousForegroundRestored": metadata.get("PreviousForegroundRestored"),
            "imageWidth": actual_width,
            "imageHeight": actual_height,
            "status": "passed" if not gate_issues else "failed",
        }

    if len(session_ids) > 1:
        issues.append("Windower-native proofs must share one SessionId")
        for result in results.values():
            if result.get("status") == "passed":
                result["status"] = "failed"
    if len(process_ids) > 1 or len(process_start_times) > 1:
        issues.append("Windower-native proofs must share one client process session")
        for result in results.values():
            if result.get("status") == "passed":
                result["status"] = "failed"
    if len(capture_times) > 1 and max(capture_times) - min(capture_times) > timedelta(
        minutes=30
    ):
        issues.append("Windower-native proofs span more than one 30-minute session")
        for result in results.values():
            if result.get("status") == "passed":
                result["status"] = "failed"
    return results, issues, warnings


def parse_proof_arguments(values: list[str]) -> dict[str, Path]:
    parsed: dict[str, Path] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"proof metadata must use gate=path form: {value!r}")
        gate, raw_path = value.split("=", 1)
        gate = gate.strip().casefold()
        raw_path = raw_path.strip()
        if not gate or gate in parsed or not raw_path:
            raise ValueError(f"invalid or duplicate proof gate: {gate!r}")
        parsed[gate] = Path(raw_path)
    return parsed


def write_tsv(path: Path, path_entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
            writer.writerow(
                [
                    "relative_path",
                    "owner",
                    "owner_sha256",
                    "owner_source",
                    "layers",
                    "layer_hashes",
                    "collision_status",
                ]
            )
            for entry in path_entries:
                layers = entry["layers"]
                writer.writerow(
                    [
                        entry["relativePath"],
                        entry["owner"],
                        layers[0]["sha256"],
                        layers[0]["source"],
                        ",".join(layer["overlay"] for layer in layers),
                        ",".join(layer["sha256"] for layer in layers),
                        entry["collisionStatus"],
                    ]
                )
        temporary_path.replace(path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        temporary_path.replace(path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def validate_output_policy(
    output_json: Path,
    output_tsv: Path,
    verify_source_artifacts: bool,
    require_native_proofs: bool,
) -> None:
    current_json = output_json.name == "client-graphics-audit-current.json"
    current_tsv = output_tsv.name == "client-graphics-audit-current.tsv"
    if current_json != current_tsv:
        raise ValueError(
            "canonical current JSON and TSV outputs must be updated together"
        )
    if current_json and not (verify_source_artifacts and require_native_proofs):
        raise ValueError(
            "canonical current outputs require --verify-source-artifacts and "
            "--require-native-proofs; use distinct static output names for preflight"
        )


def audit_graphics(
    repo_root: Path,
    client_root: Path,
    runtime_root: Path,
    contract_path: Path,
    *,
    verify_source_artifacts: bool = False,
    proof_paths: dict[str, Path] | None = None,
    require_native_proofs: bool = False,
) -> tuple[dict[str, Any], list[str], list[str]]:
    issues: list[str] = []
    warnings: list[str] = []
    contract = load_json(contract_path)
    if contract.get("schemaVersion") != 1:
        issues.append("client graphics gate manifest schemaVersion must be 1")

    xipivot = contract.get("xipivot", {})
    if not isinstance(xipivot, dict):
        raise ValueError("xipivot contract must be an object")
    settings_path = resolve_relative(
        client_root, xipivot.get("settingsRelativePath"), "XIPivot settings"
    )
    tracked_settings_path = resolve_relative(
        repo_root,
        xipivot.get("trackedSettingsRelativePath"),
        "tracked XIPivot settings",
    )
    dat_root = resolve_relative(
        client_root, xipivot.get("datRootRelativePath"), "XIPivot DAT root"
    )
    overlay_contracts = xipivot.get("overlays")
    if (
        not isinstance(overlay_contracts, list)
        or not overlay_contracts
        or not all(isinstance(entry, dict) for entry in overlay_contracts)
    ):
        raise ValueError("xipivot overlays must be a non-empty object list")
    expected_order = [
        validate_overlay_name(entry.get("name")) for entry in overlay_contracts
    ]
    if len({name.casefold() for name in expected_order}) != len(expected_order):
        issues.append("XIPivot contract contains duplicate overlay names")
    try:
        actual_order = parse_overlay_order(settings_path)
    except (
        Exception
    ) as exc:  # noqa: BLE001 - report settings failure with other issues.
        actual_order = []
        issues.append(str(exc))
    if actual_order != expected_order:
        issues.append(
            f"XIPivot overlay order mismatch: expected {expected_order}, actual {actual_order}"
        )
    try:
        tracked_order = parse_overlay_order(tracked_settings_path)
    except Exception as exc:  # noqa: BLE001 - report with other gate failures.
        tracked_order = []
        issues.append(str(exc))
    if tracked_order != expected_order:
        issues.append(
            "tracked XIPivot overlay order mismatch: "
            f"expected {expected_order}, actual {tracked_order}"
        )
    if tracked_order != actual_order:
        issues.append("live and tracked XIPivot overlay orders do not match")

    source_manifest_path = resolve_relative(
        runtime_root,
        contract.get("sourceManifestRelativePath"),
        "client source manifest",
    )
    source_manifest = (
        load_json(source_manifest_path) if source_manifest_path.is_file() else {}
    )
    runtime_sources = {
        str(entry.get("name")): entry
        for entry in source_manifest.get("sources", [])
        if isinstance(entry, dict)
    }
    if not source_manifest_path.is_file():
        issues.append("missing runtime client source manifest")

    source_results: dict[str, Any] = {}
    overlays: list[dict[str, Any]] = []
    all_layers: list[DatLayer] = []
    layers_by_path: dict[str, list[DatLayer]] = defaultdict(list)
    for overlay_contract in overlay_contracts:
        name = str(overlay_contract.get("name"))
        print(f"Scanning XIPivot overlay {name}...", file=sys.stderr, flush=True)
        source = overlay_contract.get("source", {})
        if isinstance(source, dict):
            source_key = f"{source.get('kind')}:{source.get('name')}"
            if source_key not in source_results:
                source_status, source_issues = validate_source(
                    source,
                    runtime_root,
                    runtime_sources,
                    verify_source_artifacts,
                )
                source_results[source_key] = source_status
                issues.extend(source_issues)
        layers, summary, overlay_issues = scan_overlay(dat_root, overlay_contract)
        rollback_values: list[str] = []
        single_rollback = overlay_contract.get("rollbackManifestRelativePath")
        if isinstance(single_rollback, str):
            rollback_values.append(single_rollback)
        evidence_values = overlay_contract.get("rollbackEvidenceRelativePaths", [])
        if isinstance(evidence_values, list):
            rollback_values.extend(
                value for value in evidence_values if isinstance(value, str)
            )
        rollback_paths = [
            resolve_relative(runtime_root, value, f"{name} rollback evidence")
            for value in rollback_values
        ]
        missing_rollback = [path.name for path in rollback_paths if not path.is_file()]
        if missing_rollback:
            overlay_issues.append(
                f"{name} rollback evidence is missing: {', '.join(missing_rollback)}"
            )
        invalid_rollback: list[str] = []
        missing_instruction: list[str] = []
        for path in rollback_paths:
            if not path.is_file() or path.suffix.casefold() != ".json":
                continue
            try:
                rollback_document = load_json(path)
            except (OSError, ValueError, json.JSONDecodeError):
                invalid_rollback.append(path.name)
                continue
            instruction = rollback_document.get("rollback") or rollback_document.get(
                "Rollback"
            )
            if not isinstance(instruction, str) or not instruction.strip():
                missing_instruction.append(path.name)
        if invalid_rollback:
            overlay_issues.append(
                f"{name} rollback evidence is invalid: {', '.join(invalid_rollback)}"
            )
        if missing_instruction:
            overlay_issues.append(
                f"{name} rollback instruction is missing: "
                + ", ".join(missing_instruction)
            )
        summary["rollbackEvidence"] = [path.name for path in rollback_paths]
        summary["rollbackEvidencePresent"] = not (
            missing_rollback or invalid_rollback or missing_instruction
        )
        overlays.append(summary)
        all_layers.extend(layers)
        issues.extend(overlay_issues)
        for layer in layers:
            layers_by_path[layer.normalized_path].append(layer)

    order_index = {name: index for index, name in enumerate(expected_order)}
    for layers in layers_by_path.values():
        layers.sort(key=lambda layer: order_index.get(layer.overlay, len(order_index)))

    collisions, pair_counts, collision_issues = classify_collisions(
        layers_by_path, xipivot.get("allowedCollisionPairs", [])
    )
    issues.extend(collision_issues)
    collision_by_path = {entry["normalizedPath"]: entry for entry in collisions}
    path_entries: list[dict[str, Any]] = []
    for normalized, layers in sorted(layers_by_path.items()):
        collision = collision_by_path.get(normalized)
        path_entries.append(
            {
                "relativePath": layers[0].relative_path,
                "normalizedPath": normalized,
                "owner": layers[0].overlay,
                "layers": [
                    {
                        "overlay": layer.overlay,
                        "relativePath": layer.relative_path,
                        "bytes": layer.bytes,
                        "sha256": layer.sha256,
                        "source": layer.source_name,
                    }
                    for layer in layers
                ],
                "collisionStatus": collision["status"] if collision else "none",
            }
        )

    layer_count = len(all_layers)
    unique_count = len(layers_by_path)
    collision_count = len(collisions)
    for field, actual in (
        ("expectedLayerDatFiles", layer_count),
        ("expectedUniqueDatPaths", unique_count),
        ("expectedCollisionPaths", collision_count),
    ):
        expected = xipivot.get(field)
        if actual != expected:
            issues.append(
                f"XIPivot {field} mismatch: expected {expected}, actual {actual}"
            )

    active_names = set(actual_order)
    root_dirs = (
        sorted(path.name for path in dat_root.iterdir() if path.is_dir())
        if dat_root.is_dir()
        else []
    )
    inactive_container = validate_overlay_name(
        xipivot.get("inactiveContainer", "_inactive")
    )
    unexpected_root_dirs = [
        name
        for name in root_dirs
        if name not in active_names and name != inactive_container
    ]
    if unexpected_root_dirs:
        issues.append(
            "undeclared overlay directories exist at the active DAT root: "
            + ", ".join(unexpected_root_dirs)
        )
    inactive_root = resolve_relative(
        dat_root, inactive_container, "XIPivot inactive container"
    )
    if (dat_root / inactive_container).is_symlink():
        issues.append("XIPivot inactive container may not be a symlink")
    inactive_overlays = []
    if inactive_root.is_dir():
        for path in sorted(item for item in inactive_root.iterdir() if item.is_dir()):
            inactive_overlays.append(
                {
                    "name": path.name,
                    "datCount": sum(1 for _ in iter_dat_files(path)),
                }
            )
    allowed_inactive = set(xipivot.get("allowedInactiveOverlays", []))
    unknown_inactive = [
        entry["name"]
        for entry in inactive_overlays
        if entry["name"] not in allowed_inactive
    ]
    if unknown_inactive:
        issues.append("unmanifested inactive overlays: " + ", ".join(unknown_inactive))

    addon_files = []
    for entry in xipivot.get("addonFiles", []):
        relative = str(entry.get("relativePath"))
        addon_root = resolve_relative(
            client_root, xipivot.get("addonRootRelativePath"), "XIPivot addon root"
        )
        path = resolve_relative(addon_root, relative, "XIPivot addon file")
        actual = sha256_file(path) if path.is_file() else None
        expected = str(entry.get("sha256", "")).casefold()
        matched = actual == expected
        if not matched:
            issues.append(f"XIPivot addon file mismatch: {relative}")
        addon_files.append(
            {
                "relativePath": relative,
                "expectedSha256": expected,
                "actualSha256": actual,
                "status": "passed" if matched else "failed",
            }
        )

    direct_result, direct_issues = audit_direct_dat(
        repo_root, client_root, runtime_root, contract, layers_by_path
    )
    issues.extend(direct_issues)
    renderer_result, renderer_issues = audit_renderer(
        client_root, runtime_root, contract.get("renderer", {})
    )
    issues.extend(renderer_issues)
    proof_result, proof_issues, proof_warnings = audit_native_proofs(
        contract,
        proof_paths or {},
        require_native_proofs,
        runtime_root,
        client_root,
    )
    issues.extend(proof_issues)
    warnings.extend(proof_warnings)

    report = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "policy": contract.get("policy"),
        "summary": {
            "status": "passed" if not issues else "failed",
            "issueCount": len(issues),
            "warningCount": len(warnings),
            "activeOverlayCount": len(actual_order),
            "layerDatFiles": layer_count,
            "uniqueDatPaths": unique_count,
            "collisionPaths": collision_count,
            "unexplainedCollisionPaths": sum(
                1 for collision in collisions if collision["status"] != "allowed"
            ),
            "directDatFiles": len(direct_result.get("files", [])),
            "directDatActiveOverlayOverlaps": len(
                direct_result.get("activeOverlayOverlaps", [])
            ),
        },
        "xipivot": {
            "settingsSha256": (
                sha256_file(settings_path) if settings_path.is_file() else None
            ),
            "trackedSettingsPath": str(tracked_settings_path),
            "trackedSettingsSha256": (
                sha256_file(tracked_settings_path)
                if tracked_settings_path.is_file()
                else None
            ),
            "expectedOrder": expected_order,
            "actualOrder": actual_order,
            "trackedOrder": tracked_order,
            "addonFiles": addon_files,
            "overlays": overlays,
            "inactiveOverlays": inactive_overlays,
            "unexpectedRootDirectories": unexpected_root_dirs,
            "collisionPairCounts": [
                {"owner": pair[0], "shadowed": pair[1], "paths": count}
                for pair, count in sorted(pair_counts.items())
            ],
            "collisions": collisions,
        },
        "sources": source_results,
        "directDat": direct_result,
        "renderer": renderer_result,
        "nativeProof": proof_result,
        "datPaths": path_entries,
        "issues": issues,
        "warnings": warnings,
    }
    return report, issues, warnings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--client-root",
        type=Path,
        default=Path(r"D:\Steam\steamapps\common\FFXINA"),
    )
    parser.add_argument(
        "--runtime-root",
        type=Path,
        default=Path(r"C:\Github Repo's\FFXI\Runtime"),
    )
    parser.add_argument("--contract", type=Path)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-tsv", type=Path)
    parser.add_argument("--verify-source-artifacts", action="store_true")
    parser.add_argument(
        "--proof-metadata", action="append", default=[], metavar="GATE=PATH"
    )
    parser.add_argument("--require-native-proofs", action="store_true")
    args = parser.parse_args()

    try:
        if os.name != "nt":
            raise ValueError(
                "the client graphics audit is Windows-only; run it from Windows "
                "PowerShell against the canonical FFXINA installation"
            )
        repo_root = args.repo_root.resolve()
        client_root = args.client_root.resolve()
        runtime_root = args.runtime_root.resolve()
        contract_path = (
            args.contract or (repo_root / CONTRACT_RELATIVE_PATH)
        ).resolve()
        if not is_within(contract_path, repo_root):
            raise ValueError("client graphics contract must remain under the repo root")

        declared_output_root = runtime_root / "manifests"
        output_root = declared_output_root.resolve()
        if declared_output_root.is_symlink() or not is_within(
            output_root, runtime_root
        ):
            raise ValueError("Runtime/manifests may not redirect outside Runtime")
        output_json = (
            args.output_json or (output_root / "client-graphics-audit-current.json")
        ).resolve()
        output_tsv = (
            args.output_tsv or (output_root / "client-graphics-audit-current.tsv")
        ).resolve()
        if not is_within(output_json, output_root) or output_json.suffix != ".json":
            raise ValueError("JSON output must remain under Runtime/manifests")
        if not is_within(output_tsv, output_root) or output_tsv.suffix != ".tsv":
            raise ValueError("TSV output must remain under Runtime/manifests")
        if (
            output_json == output_tsv
            or output_json.is_symlink()
            or output_tsv.is_symlink()
        ):
            raise ValueError("graphics audit outputs must be distinct regular paths")
        validate_output_policy(
            output_json,
            output_tsv,
            args.verify_source_artifacts,
            args.require_native_proofs,
        )

        proof_paths = parse_proof_arguments(args.proof_metadata)
        report, issues, warnings = audit_graphics(
            repo_root,
            client_root,
            runtime_root,
            contract_path,
            verify_source_artifacts=args.verify_source_artifacts,
            proof_paths=proof_paths,
            require_native_proofs=args.require_native_proofs,
        )
        canonical_current = output_json.name == "client-graphics-audit-current.json"
        outputs_written = not (canonical_current and issues)
        if outputs_written:
            write_json_atomic(output_json, report)
            write_tsv(output_tsv, report["datPaths"])
    except (
        Exception
    ) as exc:  # noqa: BLE001 - CLI should fail closed with one clear line.
        print(f"Mochirii client graphics audit failed to run: {exc}", file=sys.stderr)
        return 2

    if outputs_written:
        print(f"JSON report: {output_json}")
        print(f"TSV report: {output_tsv}")
    else:
        print("Canonical current reports were not replaced because the audit failed.")
    print(
        "Graphics summary: "
        f"{report['summary']['activeOverlayCount']} overlays, "
        f"{report['summary']['layerDatFiles']} DAT files, "
        f"{report['summary']['uniqueDatPaths']} unique paths, "
        f"{report['summary']['collisionPaths']} collisions, "
        f"{len(issues)} issue(s), {len(warnings)} warning(s)."
    )
    if issues:
        print("Mochirii client graphics audit failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1
    print("Mochirii client graphics audit passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
