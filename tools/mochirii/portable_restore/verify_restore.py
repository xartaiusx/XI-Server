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
            lower.startswith("sql/")
            or "/sql/" in lower
            or lower.startswith("modules/")
        ):
            issues.append(f"unexpected tracked SQL outside schema/module paths: {name}")
        try:
            size = (repo / rel).stat().st_size
        except FileNotFoundError:
            continue
        if size > 50 * 1024 * 1024:
            issues.append(f"tracked file exceeds GitHub warning threshold: {name} ({size} bytes)")
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
        except Exception as exc:  # noqa: BLE001 - verifier should report all JSON failures.
            issues.append(f"invalid JSON in {filename}: {exc}")
    return issues


def check_windower_golden_state_manifest(repo: Path) -> list[str]:
    issues: list[str] = []
    manifest_path = repo / "restore" / "manifests" / "windower-golden-state.manifest.json"
    golden_root = repo / "restore" / "windower-golden-state"
    if not manifest_path.exists() or not golden_root.exists():
        return issues

    try:
        manifest = load_json(manifest_path)
    except Exception:
        return issues

    if not isinstance(manifest, dict) or not isinstance(manifest.get("trackedFiles"), list):
        return ["windower golden-state manifest must contain a trackedFiles array"]

    declared: set[str] = set()
    for entry in manifest["trackedFiles"]:
        if not isinstance(entry, dict):
            issues.append("windower golden-state trackedFiles entries must be objects")
            continue

        relative = entry.get("relativePath")
        if not isinstance(relative, str) or not relative or relative.startswith(("/", "\\")):
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
        issues.append("upstream snapshot remote must be the official LandSandBoat repository")
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
    if not isinstance(snapshot.get("changedFileCount"), int) or snapshot["changedFileCount"] < 1:
        issues.append("upstream snapshot changedFileCount must be positive")

    return issues


def check_staged_sensitive(repo: Path) -> list[str]:
    issues: list[str] = []
    status = run_git(repo, "status", "--short")
    for line in status:
        path = line[3:] if len(line) > 3 else line
        lower = path.lower()
        if any(pattern in lower for pattern in SENSITIVE_PATTERNS) and not lower.endswith((".md", ".py", ".ps1", ".sh", ".json")):
            issues.append(f"review sensitive-looking changed path before commit: {path}")
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
