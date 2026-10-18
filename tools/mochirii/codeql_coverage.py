"""Fail-closed inventory of native CodeQL SARIF coverage, diagnostics and findings."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path, PurePosixPath
import re
import subprocess
from urllib.parse import unquote, urlsplit

MAX_SARIF_BYTES = 64 * 1024 * 1024

# Exact unextracted C++ translation units in analysis 1975798551 at main02c.
# This is a minimum recovery gate, not a coverage denominator or an exclusion.
CPP_RECOVERY_PATHS = (
    "modules/tools/packetcap/packetcap.cpp",
    "src/common/application.cpp",
    "src/common/database/caching_database.cpp",
    "src/common/database/libmariadb/libmariadb_connection.cpp",
    "src/common/settings.cpp",
    "src/map/ai/states/mobskill_state.cpp",
    "src/map/battlefield.cpp",
    "src/map/ipc_client.cpp",
    "src/map/items/transactions/player_trade.cpp",
    "src/map/lua/lua_base_entity.cpp",
    "src/map/lua/lua_instance.cpp",
    "src/map/lua/lua_item.cpp",
    "src/map/lua/lua_mobskill.cpp",
    "src/map/lua/lua_petskill.cpp",
    "src/map/lua/lua_spell.cpp",
    "src/map/lua/lua_trait.cpp",
    "src/map/lua/lua_weaponskill.cpp",
    "src/map/lua/lua_zone.cpp",
    "src/map/map_networking.cpp",
    "src/map/map_session.cpp",
    "src/map/map_session_container.cpp",
    "src/map/packets/c2s/0x03b_subcontainer.cpp",
    "src/map/packets/c2s/0x05e_maprect.cpp",
    "src/map/packets/c2s/0x083_shop_buy.cpp",
    "src/map/packets/c2s/0x085_shop_sell_set.cpp",
    "src/map/packets/c2s/0x0aa_guild_buy.cpp",
    "src/map/packets/c2s/0x0ac_guild_sell.cpp",
    "src/map/status_effect_container.cpp",
    "src/map/treasure_pool.cpp",
    "src/map/utils/charutils.cpp",
    "src/map/utils/trustutils.cpp",
    "src/map/ximesh/ximesh_impl.cpp",
    "src/map/zone_entities.cpp",
    "src/profile/data/files.cpp",
    "src/search/search_handler.cpp",
    "src/test/lua/helpers/lua_client_entity_pair_events.cpp",
    "src/test/lua/lua_simulation.cpp",
    "src/test/reporters/ctrf_reporter.cpp",
    "src/test/test_lua_environment.cpp",
    "src/test/test_matcher.cpp",
)


def repository_path(uri: str) -> str:
    """Accept only a repository-relative SARIF URI, including encoded paths."""
    if not isinstance(uri, str) or not uri:
        raise ValueError("Missing artifact URI")
    parsed = urlsplit(uri)
    path = unquote(parsed.path)
    if (
        parsed.scheme
        or parsed.netloc
        or parsed.query
        or parsed.fragment
        or "\\" in path
        or ":" in path
        or any(ord(char) < 32 for char in path)
        or PurePosixPath(path).is_absolute()
        or ".." in PurePosixPath(path).parts
        or not PurePosixPath(path).parts
    ):
        raise ValueError("Unsafe or non-relative artifact URI")
    return str(PurePosixPath(path))


def location_paths(item: dict, artifacts: list[dict]) -> list[str]:
    paths = []
    for location in item.get("locations", []):
        physical = location.get("physicalLocation", {})
        artifact = physical.get("artifactLocation", {})
        if "uri" not in artifact:
            index = artifact.get("index")
            if not isinstance(index, int) or isinstance(index, bool) or index < 0:
                raise ValueError("Missing artifact location")
            if index >= len(artifacts):
                raise ValueError("Artifact index out of bounds")
            artifact = artifacts[index]["location"]
        if artifact.get("uriBaseId") not in (None, "%SRCROOT%"):
            raise ValueError("Unsupported artifact URI base")
        paths.append(repository_path(artifact.get("uri")))
    return sorted(set(paths))


def security_severity(rule: dict) -> tuple[str, str]:
    properties = rule.get("properties", {})
    raw = properties.get("security-severity")
    security = raw is not None or "security" in properties.get("tags", [])
    if raw is None:
        return ("security" if security else "quality", "unrated")
    if isinstance(raw, bool):
        raise ValueError("Invalid security severity")
    try:
        score = float(raw)
    except (ValueError, TypeError) as error:
        raise ValueError("Invalid security severity") from error
    if not math.isfinite(score) or not 0 <= score <= 10:
        raise ValueError("Invalid security severity range")
    band = (
        "critical"
        if score >= 9
        else (
            "high"
            if score >= 7
            else "medium" if score >= 4 else "low" if score > 0 else "none"
        )
    )
    return "security", band


def analyze_sarif(
    data: dict,
    *,
    language: str,
    category: str,
    source_sha: str,
    required_paths: tuple[str, ...] = (),
) -> dict:
    if (
        not isinstance(data, dict)
        or data.get("version") != "2.1.0"
        or not isinstance(data.get("runs"), list)
        or not data["runs"]
        or any(not isinstance(run, dict) for run in data["runs"])
    ):
        raise ValueError("Expected nonempty SARIF 2.1.0 runs")
    if language not in {"cpp", "python"} or not re.fullmatch(
        r"[0-9a-f]{40}", source_sha
    ):
        raise ValueError("Invalid language or source SHA")
    prefix = "py" if language == "python" else "cpp"
    coverage_prefixes = {"py"} if language == "python" else {"cpp", "c"}
    expected_ids = {
        f"{item}/baseline/expected-extracted-files" for item in coverage_prefixes
    } | {
        f"cli/expected-extracted-files/{item}"
        for item in ({"python"} if language == "python" else {"cpp", "c"})
    }
    expected, extracted = set(), set()
    diagnostics, findings = [], Counter()
    compiler_errors = 0
    tool_versions = set()
    for run in data["runs"]:
        driver = run["tool"]["driver"]
        if driver.get("name") != "CodeQL":
            raise ValueError("Expected native CodeQL driver")
        tool_versions.add(
            driver.get("semanticVersion", driver.get("version", "unknown"))
        )
        if run.get("automationDetails", {}).get("id", "").rstrip(
            "/"
        ) != category.rstrip("/"):
            raise ValueError("SARIF category mismatch")
        revisions = {
            item.get("revisionId") for item in run.get("versionControlProvenance", [])
        }
        # Native pre-upload SARIF may omit provenance; uploaded REST SARIF adds it.
        # The CLI independently binds the report to the actual checkout below.
        if "versionControlProvenance" in run and revisions != {source_sha}:
            raise ValueError("SARIF source provenance mismatch")
        artifacts = run.get("artifacts", [])
        invocations = run.get("invocations", [])
        if not invocations or any(
            item.get("executionSuccessful") is not True for item in invocations
        ):
            raise ValueError("Missing or failed CodeQL invocation")
        for invocation in invocations:
            for note in [
                *invocation.get("toolExecutionNotifications", []),
                *invocation.get("toolConfigurationNotifications", []),
            ]:
                descriptor = note.get("descriptor", {})
                identifier = descriptor.get("id")
                if identifier is None:
                    index = descriptor.get("index")
                    notifications = driver.get("notifications", [])
                    if (
                        descriptor.get("toolComponent") is not None
                        or not isinstance(index, int)
                        or isinstance(index, bool)
                        or not 0 <= index < len(notifications)
                    ):
                        raise ValueError("Invalid diagnostic descriptor index")
                    identifier = notifications[index]["id"]
                if not isinstance(identifier, str):
                    raise ValueError("Missing diagnostic descriptor")
                level = note.get("level", "warning")
                if level not in {"none", "note", "warning", "error"}:
                    raise ValueError("Invalid diagnostic level")
                if identifier in expected_ids:
                    expected.update(location_paths(note, artifacts))
                elif identifier in {
                    f"{item}/diagnostics/successfully-extracted-files"
                    for item in coverage_prefixes
                }:
                    extracted.update(location_paths(note, artifacts))
                else:
                    diagnostics.append(
                        {
                            "id": identifier,
                            "level": level,
                            "message": note.get("message", {}).get("text", "")[:4096],
                        }
                    )
        for metric in run.get("properties", {}).get("metricResults", []):
            identifier = metric.get("ruleId", metric.get("rule", {}).get("id"))
            if identifier == f"{prefix}/telemetry/compiler-errors":
                value = metric.get("value")
                if (
                    not isinstance(value, (int, float))
                    or isinstance(value, bool)
                    or not math.isfinite(value)
                    or value < 0
                ):
                    raise ValueError("Invalid compiler error metric")
                compiler_errors += value
        components = [driver, *run["tool"].get("extensions", [])]
        rules = {
            rule["id"]: rule
            for component in components
            for rule in component.get("rules", [])
        }
        for result in run.get("results", []):
            identifier = result.get("ruleId", result.get("rule", {}).get("id"))
            if identifier not in rules:
                raise ValueError("Finding references unknown rule")
            rule = rules[identifier]
            kind, severity = security_severity(rule)
            level = result.get(
                "level", rule.get("defaultConfiguration", {}).get("level", "warning")
            )
            if level not in {"none", "note", "warning", "error"}:
                raise ValueError("Invalid finding level")
            findings[identifier, kind, severity, level] += 1
    failures = []
    first_party = {path for path in expected if not path.startswith(("ext/", "build/"))}
    if not first_party & extracted:
        failures.append(
            "Missing baseline or successfully-extracted file diagnostics; zero-scan is not acceptance"
        )
    missing_required = sorted(set(required_paths) - extracted)
    if missing_required:
        failures.append("Required C++ translation units were not extracted")
    if required_paths and (
        compiler_errors or any(item["level"] == "error" for item in diagnostics)
    ):
        failures.append("Traced extraction has compiler errors or error diagnostics")
    return {
        "source_sha": source_sha,
        "language": language,
        "category": category,
        "tool_versions": sorted(tool_versions),
        "expected_files": len(expected),
        "extracted_expected_files": len(expected & extracted),
        "first_party_expected_files": len(first_party),
        "first_party_extracted_files": len(first_party & extracted),
        "missing_files": sorted(expected - extracted),
        "missing_required_cpp": missing_required,
        "files": [
            {"path": path, "expected": path in expected, "extracted": path in extracted}
            for path in sorted(expected | extracted)
        ],
        "compiler_errors": compiler_errors,
        "diagnostics": sorted(
            diagnostics, key=lambda item: (item["id"], item["level"], item["message"])
        ),
        "findings": [
            {
                "rule": key[0],
                "kind": key[1],
                "security_severity": key[2],
                "level": key[3],
                "count": count,
            }
            for key, count in sorted(findings.items())
        ],
        "gate": "failed" if failures else "passed",
        "failures": failures,
    }


def load_sarif(path: Path) -> dict:
    if not 0 < path.stat().st_size <= MAX_SARIF_BYTES:
        raise ValueError("SARIF is empty or exceeds the size limit")

    def unique_object(pairs: list[tuple[str, object]]) -> dict:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result

    with path.open(encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=unique_object)


def verify_checkout_sha(expected_sha: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha):
        raise ValueError("Invalid source SHA")
    actual = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=Path(__file__).resolve().parents[2],
        check=True,
        capture_output=True,
        text=True,
        encoding="ascii",
        timeout=10,
    ).stdout.strip()
    if actual != expected_sha:
        raise ValueError("Checkout source SHA mismatch")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sarif", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language", choices=("cpp", "python"), required=True)
    parser.add_argument("--category", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--require-cpp-recovery", action="store_true")
    args = parser.parse_args()
    if args.require_cpp_recovery and args.language != "cpp":
        parser.error("--require-cpp-recovery requires --language cpp")
    try:
        verify_checkout_sha(args.source_sha)
        report = analyze_sarif(
            load_sarif(args.sarif),
            language=args.language,
            category=args.category,
            source_sha=args.source_sha,
            required_paths=CPP_RECOVERY_PATHS if args.require_cpp_recovery else (),
        )
        report["source_proof"] = "verified-checkout-head"
    except (
        ValueError,
        KeyError,
        IndexError,
        TypeError,
        AttributeError,
        OSError,
        UnicodeError,
        subprocess.SubprocessError,
    ) as error:
        report = {
            "gate": "failed",
            "expected_source_sha": args.source_sha,
            "expected_category": args.category,
            "failures": [f"Invalid coverage input: {type(error).__name__}"],
        }
    with args.output.open("x", encoding="utf-8") as destination:
        json.dump(report, destination, indent=2, sort_keys=True, allow_nan=False)
        destination.write("\n")
    print(json.dumps({key: report[key] for key in ("gate", "failures")}))
    return 0 if report["gate"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
