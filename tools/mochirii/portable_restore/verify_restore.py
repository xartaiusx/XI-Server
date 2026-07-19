#!/usr/bin/env python3
"""Git-safe verification for Mochirii portable restore material."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

FORBIDDEN_SUFFIXES = {
    ".enc",
    ".zip",
    ".7z",
    ".rar",
    ".bak",
    ".dump",
}

FORBIDDEN_NAMES = {
    "settings/network.lua",
}

SENSITIVE_PATTERNS = (
    "password",
    "passphrase",
    "secret",
    "xiloader",
    "token",
)
REQUIRED_NATIVE_PROOF_GATES = [
    "xipivot",
    "jasmint",
    "remapster",
    "dgvoodoo2",
    "reshade",
]
REQUIRED_RENDERER_GATES = {"dgvoodoo2", "reshade"}


def is_safe_relative_path(value: object) -> bool:
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    normalized = value.replace("\\", "/")
    path = Path(normalized)
    return not (
        re.match(r"^[A-Za-z]:", normalized)
        or normalized.startswith("/")
        or path.is_absolute()
        or ".." in path.parts
    )


def run_git(repo: Path, *args: str) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.splitlines()


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def check_tracked_files(repo: Path) -> list[str]:
    issues: list[str] = []
    tracked = run_git(repo, "ls-files")
    for name in tracked:
        rel = Path(name)
        lower = name.lower()
        if name in FORBIDDEN_NAMES:
            issues.append(f"forbidden tracked local settings file: {name}")
        if rel.suffix.lower() in FORBIDDEN_SUFFIXES:
            issues.append(f"forbidden tracked artifact/archive: {name}")
        if lower.endswith(".sql") and not (
            lower.startswith("sql/") or "/sql/" in lower or lower.startswith("modules/")
        ):
            issues.append(f"unexpected tracked SQL outside schema/module paths: {name}")
        try:
            size = (repo / rel).stat().st_size
        except FileNotFoundError:
            continue
        if size > 50 * 1024 * 1024:
            issues.append(
                f"tracked file exceeds GitHub warning threshold: {name} ({size} bytes)"
            )
    return issues


def check_manifest_set(repo: Path) -> list[str]:
    issues: list[str] = []
    manifest_dir = repo / "restore" / "manifests"
    required = [
        "database-backup.manifest.json",
        "windower-golden-state.manifest.json",
        "twills-state.redacted.json",
        "mods.manifest.json",
        "client-direct-dat.manifest.json",
        "client-graphics-gates.manifest.json",
        "source-of-truth.manifest.json",
        "restore-verification.manifest.json",
        "upstream-base.manifest.json",
    ]
    for filename in required:
        path = manifest_dir / filename
        if not path.exists():
            issues.append(f"missing restore manifest: {filename}")
            continue
        try:
            load_json(path)
        except Exception as exc:  # noqa: BLE001 - report all JSON failures.
            issues.append(f"invalid JSON in {filename}: {exc}")
    return issues


def check_client_graphics_manifest(repo: Path) -> list[str]:
    issues: list[str] = []
    manifest_dir = repo / "restore" / "manifests"
    gate_path = manifest_dir / "client-graphics-gates.manifest.json"
    mods_path = manifest_dir / "mods.manifest.json"
    source_path = manifest_dir / "source-of-truth.manifest.json"
    missing = [
        path.name for path in (gate_path, mods_path, source_path) if not path.is_file()
    ]
    if missing:
        return [
            "client graphics cross-check manifest(s) missing: " + ", ".join(missing)
        ]

    try:
        gate = load_json(gate_path)
        mods = load_json(mods_path)
        source = load_json(source_path)
    except Exception as exc:  # noqa: BLE001 - fail closed on any malformed input.
        return [f"could not load client graphics cross-check manifests: {exc}"]
    if not isinstance(gate, dict) or gate.get("schemaVersion") != 1:
        return ["client graphics gate manifest schemaVersion must be 1"]

    xipivot = gate.get("xipivot")
    if not isinstance(xipivot, dict):
        return ["client graphics gate manifest must contain xipivot"]
    overlays = xipivot.get("overlays")
    if not isinstance(overlays, list) or not overlays:
        return ["client graphics gate manifest must declare overlays"]

    names: list[str] = []
    counts: dict[str, int] = {}
    sha_pattern = re.compile(r"^[0-9a-f]{64}$")
    for entry in overlays:
        if not isinstance(entry, dict):
            issues.append("client graphics overlay entries must be objects")
            continue
        name = entry.get("name")
        count = entry.get("expectedDatCount")
        tree_hash = entry.get("expectedTreeSha256")
        if (
            not isinstance(name, str)
            or not name
            or name != name.strip()
            or re.search(r"[/\\:]", name)
        ):
            issues.append(f"invalid client graphics overlay name: {name!r}")
            continue
        if name.casefold() in {value.casefold() for value in names}:
            issues.append(f"duplicate client graphics overlay: {name}")
        names.append(name)
        if not isinstance(count, int) or count < 1:
            issues.append(f"invalid client graphics DAT count for {name}: {count!r}")
        else:
            counts[name] = count
        if not isinstance(tree_hash, str) or not sha_pattern.fullmatch(tree_hash):
            issues.append(f"client graphics overlay tree hash is not pinned: {name}")
        source_entry = entry.get("source")
        if not isinstance(source_entry, dict) or not source_entry.get("name"):
            issues.append(f"client graphics overlay source is not declared: {name}")
        else:
            source_kind = source_entry.get("kind")
            source_sha = source_entry.get("sha256")
            if source_kind not in {"runtime-source-manifest", "runtime-backup"}:
                issues.append(f"invalid client graphics source kind for {name}")
            if not isinstance(source_sha, str) or not sha_pattern.fullmatch(source_sha):
                issues.append(f"client graphics source hash is not pinned: {name}")
            if source_kind == "runtime-backup" and not is_safe_relative_path(
                source_entry.get("runtimeRelativePath")
            ):
                issues.append(f"invalid runtime backup path for {name}")

        rollback_values: list[object] = []
        if "rollbackManifestRelativePath" in entry:
            rollback_values.append(entry.get("rollbackManifestRelativePath"))
        evidence = entry.get("rollbackEvidenceRelativePaths", [])
        if not isinstance(evidence, list):
            issues.append(f"invalid rollback evidence list for {name}")
        else:
            rollback_values.extend(evidence)
        for value in rollback_values:
            if not is_safe_relative_path(value):
                issues.append(f"invalid rollback evidence path for {name}: {value!r}")

    mods_xipivot = mods.get("xipivot", {}) if isinstance(mods, dict) else {}
    source_windower = source.get("windower", {}) if isinstance(source, dict) else {}
    for label, configured in (
        ("mods.manifest.json", mods_xipivot.get("activeOverlays")),
        ("source-of-truth.manifest.json", source_windower.get("xipivot_overlay_order")),
    ):
        if configured != names:
            issues.append(f"client graphics overlay order differs from {label}")
    if mods_xipivot.get("fileCounts") != counts:
        issues.append("client graphics overlay counts differ from mods.manifest.json")
    if sum(counts.values()) != xipivot.get("expectedLayerDatFiles"):
        issues.append(
            "client graphics expectedLayerDatFiles does not equal overlay counts"
        )
    if (
        isinstance(xipivot.get("expectedLayerDatFiles"), int)
        and isinstance(xipivot.get("expectedUniqueDatPaths"), int)
        and isinstance(xipivot.get("expectedCollisionPaths"), int)
        and xipivot["expectedLayerDatFiles"] - xipivot["expectedUniqueDatPaths"]
        != xipivot["expectedCollisionPaths"]
    ):
        issues.append("client graphics layer/unique/collision totals are inconsistent")
    if mods_xipivot.get("totalUniquePaths") != xipivot.get("expectedUniqueDatPaths"):
        issues.append(
            "client graphics unique DAT count differs from mods.manifest.json"
        )
    if mods_xipivot.get("intentionalCollisions") != xipivot.get(
        "expectedCollisionPaths"
    ):
        issues.append("client graphics collision count differs from mods.manifest.json")

    pairs = xipivot.get("allowedCollisionPairs")
    if not isinstance(pairs, list) or not pairs:
        issues.append("client graphics allowedCollisionPairs must be declared")
    else:
        pair_total = 0
        seen_pairs: set[tuple[str, str]] = set()
        for entry in pairs:
            if not isinstance(entry, dict):
                issues.append("client graphics collision pair entries must be objects")
                continue
            pair = (str(entry.get("owner")), str(entry.get("shadowed")))
            if pair in seen_pairs:
                issues.append(
                    f"duplicate client graphics collision pair: {pair[0]}>{pair[1]}"
                )
            seen_pairs.add(pair)
            expected = entry.get("expectedPaths")
            if not isinstance(expected, int) or expected < 1:
                issues.append(f"invalid collision count for {pair[0]}>{pair[1]}")
            else:
                pair_total += expected
        if pair_total != xipivot.get("expectedCollisionPaths"):
            issues.append(
                "client graphics expectedCollisionPaths differs from pair totals"
            )

    if gate.get("nativeProofGates") != REQUIRED_NATIVE_PROOF_GATES:
        issues.append(
            "client graphics nativeProofGates must contain the five canonical gates"
        )
    if not is_safe_relative_path(gate.get("sourceManifestRelativePath")):
        issues.append("client graphics source manifest path is invalid")
    tracked_settings = xipivot.get("trackedSettingsRelativePath")
    if not is_safe_relative_path(tracked_settings):
        issues.append("tracked XIPivot settings path is invalid")
    elif not (repo / str(tracked_settings)).is_file():
        issues.append("tracked XIPivot settings file is missing")

    direct = gate.get("directDat")
    if not isinstance(direct, dict):
        issues.append("client graphics directDat gate must be declared")
    else:
        if (
            not isinstance(direct.get("expectedFiles"), int)
            or direct["expectedFiles"] < 1
        ):
            issues.append("client graphics direct DAT count is invalid")
        if direct.get("allowActiveOverlayOverlap") is not False:
            issues.append("client graphics direct DAT overlap must remain disabled")
        for field in ("runtimeManifestRelativePath", "rollbackRootRelativePath"):
            if not is_safe_relative_path(direct.get(field)):
                issues.append(f"client graphics direct DAT {field} is invalid")

    renderer = gate.get("renderer")
    if not isinstance(renderer, dict):
        issues.append("client graphics renderer gate must be declared")
    else:
        if not is_safe_relative_path(renderer.get("currentManifestRelativePath")):
            issues.append("client graphics renderer current manifest path is invalid")
        renderer_gates = renderer.get("gates")
        if (
            not isinstance(renderer_gates, dict)
            or set(renderer_gates) != REQUIRED_RENDERER_GATES
        ):
            issues.append(
                "client graphics renderer must define dgvoodoo2 and reshade gates"
            )
            renderer_gates = {}
        for gate_name in sorted(REQUIRED_RENDERER_GATES):
            renderer_gate = renderer_gates.get(gate_name)
            if not isinstance(renderer_gate, dict):
                continue
            rollback_paths = renderer_gate.get("rollbackManifestRelativePaths")
            if (
                not isinstance(rollback_paths, list)
                or not rollback_paths
                or not all(is_safe_relative_path(value) for value in rollback_paths)
            ):
                issues.append(f"{gate_name} rollback manifest list is invalid")
            if renderer_gate.get("requireRollbackInstruction") is not True:
                issues.append(f"{gate_name} must require a rollback instruction")
        reshade = renderer_gates.get("reshade", {})
        if isinstance(reshade, dict):
            if not is_safe_relative_path(reshade.get("requiredPresetRelativePath")):
                issues.append("ReShade required preset path is invalid")
            techniques = reshade.get("requiredEnabledTechniques")
            if (
                not isinstance(techniques, list)
                or not techniques
                or len(techniques) != len(set(techniques))
                or not all(isinstance(value, str) and value for value in techniques)
            ):
                issues.append("ReShade required enabled techniques are invalid")

    return issues


def check_windower_golden_state_manifest(repo: Path) -> list[str]:
    issues: list[str] = []
    manifest_path = (
        repo / "restore" / "manifests" / "windower-golden-state.manifest.json"
    )
    golden_root = repo / "restore" / "windower-golden-state"
    if not manifest_path.exists() or not golden_root.exists():
        return issues

    try:
        manifest = load_json(manifest_path)
    except Exception:
        return issues

    if not isinstance(manifest, dict) or not isinstance(
        manifest.get("trackedFiles"), list
    ):
        return ["windower golden-state manifest must contain a trackedFiles array"]

    declared: set[str] = set()
    for entry in manifest["trackedFiles"]:
        if not isinstance(entry, dict):
            issues.append("windower golden-state trackedFiles entries must be objects")
            continue

        relative = entry.get("relativePath")
        if (
            not isinstance(relative, str)
            or not relative
            or relative.startswith(("/", "\\"))
        ):
            issues.append(f"invalid windower golden-state relativePath: {relative!r}")
            continue
        if relative in declared:
            issues.append(f"duplicate windower golden-state manifest entry: {relative}")
            continue
        declared.add(relative)

        path = golden_root / Path(relative)
        if not path.is_file():
            issues.append(f"missing windower golden-state file: {relative}")
            continue

        payload = path.read_bytes()
        expected_bytes = entry.get("bytes")
        expected_sha256 = entry.get("sha256")
        actual_sha256 = hashlib.sha256(payload).hexdigest()
        if expected_bytes != len(payload):
            issues.append(
                f"windower golden-state size mismatch: {relative} "
                f"(manifest {expected_bytes}, actual {len(payload)})"
            )
        if expected_sha256 != actual_sha256:
            issues.append(
                f"windower golden-state hash mismatch: {relative} "
                f"(manifest {expected_sha256}, actual {actual_sha256})"
            )

    actual = {
        path.relative_to(golden_root).as_posix()
        for path in golden_root.rglob("*")
        if path.is_file()
    }
    for relative in sorted(actual - declared):
        issues.append(f"unmanifested windower golden-state file: {relative}")
    for relative in sorted(declared - actual):
        issues.append(f"manifest-only windower golden-state file: {relative}")

    return issues


def check_upstream_snapshot(repo: Path) -> list[str]:
    issues: list[str] = []
    path = repo / "restore" / "manifests" / "upstream-base.manifest.json"
    if not path.exists():
        return issues

    try:
        snapshot = load_json(path)
    except Exception:
        return issues

    if not isinstance(snapshot, dict):
        return ["upstream-base.manifest.json must contain a JSON object"]

    if snapshot.get("remote") != "https://github.com/LandSandBoat/server.git":
        issues.append(
            "upstream snapshot remote must be the official LandSandBoat repository"
        )
    if snapshot.get("branch") != "base":
        issues.append("upstream snapshot branch must be base")

    sha_pattern = re.compile(r"^[0-9a-f]{40}$")
    for field in ("previousSnapshot", "currentSnapshot"):
        value = snapshot.get(field)
        if not isinstance(value, str) or not sha_pattern.fullmatch(value):
            issues.append(f"upstream snapshot {field} must be a full lowercase Git SHA")

    if snapshot.get("previousSnapshot") == snapshot.get("currentSnapshot"):
        issues.append("upstream snapshot range must advance")
    if not isinstance(snapshot.get("commitCount"), int) or snapshot["commitCount"] < 1:
        issues.append("upstream snapshot commitCount must be positive")
    if (
        not isinstance(snapshot.get("changedFileCount"), int)
        or snapshot["changedFileCount"] < 1
    ):
        issues.append("upstream snapshot changedFileCount must be positive")

    return issues


def check_staged_sensitive(repo: Path) -> list[str]:
    issues: list[str] = []
    status = run_git(repo, "status", "--short")
    for line in status:
        path = line[3:] if len(line) > 3 else line
        lower = path.lower()
        if any(
            pattern in lower for pattern in SENSITIVE_PATTERNS
        ) and not lower.endswith((".md", ".py", ".ps1", ".sh", ".json")):
            issues.append(
                f"review sensitive-looking changed path before commit: {path}"
            )
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--check-manifests", action="store_true")
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    issues = []
    issues.extend(check_tracked_files(repo))
    issues.extend(check_manifest_set(repo))
    issues.extend(check_windower_golden_state_manifest(repo))
    issues.extend(check_client_graphics_manifest(repo))
    issues.extend(check_upstream_snapshot(repo))
    issues.extend(check_staged_sensitive(repo))

    if issues:
        print("Mochirii portable restore verification failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print("Mochirii portable restore verification passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
