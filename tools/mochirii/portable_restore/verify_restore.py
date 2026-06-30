#!/usr/bin/env python3
"""Git-safe verification for Mochirii portable restore material."""

from __future__ import annotations

import argparse
import json
import os
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
