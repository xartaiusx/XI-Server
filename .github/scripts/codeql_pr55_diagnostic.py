"""Temporary PR55 query-mode diagnostic; emit fingerprints, never SARIF/messages."""

from collections import Counter
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

BASE = "8037f00c446608e0204d9a0ebb9789c182522288"
CONFIG_SHA = "74a276b81502c0bb9052e7002962f6abfe7c263c17a940bb6d761b0d11ee7189"
RULE_IDS_SHA = "c335aeebcba2d65df630d3ad06f7f3cd54ffdde38d5df7c48b0a304d6c338435"
PACKS = {
    "codeql/cpp-queries": "1.9.2+a1575b98a8cc19bcfa7bb6cb41be688cb3dae65c",
    "codeql/cpp-all": "12.3.0+a1575b98a8cc19bcfa7bb6cb41be688cb3dae65c",
}
CONFIG = {
    "name": "codeql config",
    "queries": [{"uses": "security-extended"}, {"uses": "security-and-quality"}],
    "paths-ignore": ["ext/**", "build/**"],
}


def require(condition):
    if not condition:
        raise ValueError("Diagnostic contract failed")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fingerprint(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def unique(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value)
        value[key] = item
    return value


def read_json(path, limit):
    require(
        path.is_file() and not path.is_symlink() and 0 < path.stat().st_size < limit
    )
    return json.loads(path.read_bytes(), object_pairs_hook=unique)


def git(*arguments):
    result = subprocess.run(
        ["git", *arguments], check=True, capture_output=True, timeout=30
    )
    require(len(result.stdout) < 4194304)
    return result.stdout.decode().strip()


def effective(config, mode):
    require(mode in ("full", "diff-informed"))
    require(config["languages"] == ["cpp"] and config["buildMode"] == "none")
    require(
        config["overlayDatabaseMode"] == "none"
        and not config["useOverlayDatabaseCaching"]
    )
    require(
        config["debugMode"] is False and config["enableFileCoverageInformation"] is True
    )
    require(config["trapCaches"] == {} and config["originalUserInput"] == CONFIG)
    require(config["computedConfig"] == CONFIG)
    expected = (
        [{"exclude": {"tags": "exclude-from-incremental"}}]
        if mode == "diff-informed"
        else []
    )
    require(config["extraQueryExclusions"] == expected)
    return {
        "config": CONFIG,
        "extra_query_exclusions": expected,
        "overlay": "none",
        "file_coverage": True,
    }


def source_uri(location, workspace, artifacts, allowed):
    artifact = location["artifactLocation"]
    if "index" in artifact:
        require(
            type(artifact["index"]) is int and 0 <= artifact["index"] < len(artifacts)
        )
    reference = (
        artifacts[artifact["index"]]["location"] if "index" in artifact else artifact
    )
    if "uri" in artifact and "uri" in reference:
        require(artifact["uri"] == reference["uri"])
    raw = artifact.get("uri", reference.get("uri"))
    require(
        isinstance(raw, str)
        and artifact.get("uriBaseId", reference.get("uriBaseId", "%SRCROOT%"))
        == "%SRCROOT%"
    )
    parsed = urlsplit(raw)
    require(not parsed.netloc and not parsed.query and not parsed.fragment)
    text = unquote(parsed.path, errors="strict")
    require(not any(part in ("", ".", "..") for part in text.lstrip("/").split("/")))
    if parsed.scheme == "file":
        text = str(PurePosixPath(text).relative_to(PurePosixPath(workspace)))
    else:
        require(not parsed.scheme and not text.startswith("/"))
    require(text in allowed)
    return text


def summarize(run, mode, workspace, allowed):
    require(run["tool"]["driver"]["semanticVersion"] == "2.27.3")
    require(
        run.get("properties", {}).get("incrementalMode", "")
        == ("diff-informed" if mode == "diff-informed" else "")
    )
    require(
        run["automationDetails"]["id"] == "mochirii-pr55-controlled-cpp-" + mode + "/"
    )
    require(
        run["properties"]["codeqlConfigSummary"]["queries"]
        == [
            {"type": "builtinSuite", "uses": "security-extended"},
            {"type": "builtinSuite", "uses": "security-and-quality"},
        ]
    )
    extensions = run["tool"].get("extensions", [])
    packs = {entry["name"]: entry["semanticVersion"] for entry in extensions}
    expected = dict(PACKS)
    if mode == "diff-informed":
        expected["codeql-action/pr-diff-range"] = "0.0.0"
    require(len(packs) == len(extensions) and packs == expected)
    rules = [rule for entry in extensions for rule in entry.get("rules", [])]
    require(
        len(rules) == 180
        and fingerprint(sorted(rule["id"] for rule in rules)) == RULE_IDS_SHA
    )
    rule_ids = {rule["id"] for rule in rules}
    for invocation in run.get("invocations", []):
        require(invocation.get("executionSuccessful") is True)
        for field in ("toolExecutionNotifications", "toolConfigurationNotifications"):
            require(
                not any(
                    notice.get("level") in ("error", "warning")
                    for notice in invocation.get(field, [])
                )
            )
    rows, regions, known = [], [], Counter()
    require(len(run["results"]) <= 2000)
    for result in run["results"]:
        require(
            result["ruleId"] in rule_ids
            and result.get("level") in ("error", "warning", "note")
        )
        locations = [item["physicalLocation"] for item in result.get("locations", [])]
        require(locations)
        uris = [
            source_uri(item, workspace, run.get("artifacts", []), allowed)
            for item in locations
        ]
        row = [result["ruleId"], result.get("level"), result["message"], uris]
        rows.append(fingerprint(row))
        regions.append(
            fingerprint([row, [item.get("region", {}) for item in locations]])
        )
        for location, uri in zip(locations, uris):
            line = location.get("region", {})
            if uri == "src/test/application_lifecycle_main.cpp":
                if result["ruleId"] == "cpp/missing-return" and (
                    line.get("startLine"),
                    line.get("endLine", line.get("startLine")),
                ) == (141, 143):
                    known["5833"] += 1
                if result["ruleId"] == "cpp/useless-expression" and (
                    line.get("startLine"),
                    line.get("endLine", line.get("startLine")),
                ) == (132, 132):
                    known["5834"] += 1
    return {
        "packs": packs,
        "rule_ids_sha256": RULE_IDS_SHA,
        "result_count": len(rows),
        "semantic_fingerprints": sorted(rows),
        "region_fingerprints": sorted(regions),
        "per_rule": dict(
            sorted(Counter(item["ruleId"] for item in run["results"]).items())
        ),
        "public_probe_identities": {"5833": known["5833"], "5834": known["5834"]},
    }


def cli_json(config, *arguments):
    result = subprocess.run(
        [config["codeQLCmd"], *arguments], check=True, capture_output=True, timeout=60
    )
    require(0 < len(result.stdout) < 4194304)
    return json.loads(result.stdout, object_pairs_hook=unique)


def execution(config, workspace):
    database = Path(config["dbLocation"]) / "cpp"
    require(database == Path(os.environ["RUNNER_TEMP"]) / "pr55-codeql-database/cpp")
    suite = database / "temp/config-queries.qls"
    queries = cli_json(config, "resolve", "queries", "--format=json", str(suite))
    require(isinstance(queries, list) and 180 <= len(queries) <= 256)
    pack = Path(config["codeQLCmd"]).parent / "qlpacks/codeql/cpp-queries/1.9.2"
    relative = [
        str(Path(query).resolve(strict=True).relative_to(pack.resolve(strict=True)))
        for query in queries
    ]
    require(
        len(set(relative)) == len(relative)
        and all(path.endswith(".ql") for path in relative)
    )
    require(
        {"Telemetry/CompilerErrors.ql", "Telemetry/ExtractionMetrics.ql"}
        <= set(relative)
    )
    results = database / "results/codeql/cpp-queries"
    actual = {str(path.relative_to(results)) for path in results.rglob("*.bqrs")}
    require(actual == {path[:-3] + ".bqrs" for path in relative})
    errors = cli_json(
        config,
        "bqrs",
        "decode",
        "--format=json",
        str(results / "Telemetry/CompilerErrors.bqrs"),
    )
    require(errors["#select"]["tuples"] == [])
    metrics = cli_json(
        config,
        "bqrs",
        "decode",
        "--format=json",
        str(results / "Telemetry/ExtractionMetrics.bqrs"),
    )["#select"]["tuples"]
    for label in ("compiler errors", "syntax errors"):
        rows = [row for row in metrics if len(row) == 2 and row[0] == label]
        require(len(rows) == 1 and type(rows[0][1]) is int and rows[0][1] == 0)
    logs = list((database / "log").rglob("*.log"))
    require(
        0 < len(logs) <= 512 and sum(path.stat().st_size for path in logs) < 134217728
    )
    indexed = set()
    for path in logs:
        require(
            path.is_file() and not path.is_symlink() and path.stat().st_size < 33554432
        )
        text = path.read_text(errors="strict")
        require(not re.search(r"\b(?:ERROR|WARN|WARNING|FATAL)\b", text))
        indexed.update(
            re.findall(
                r'Indexed folder "'
                + re.escape(str(workspace))
                + r'", found (\d+) source files, (\d+) header files,',
                text,
            )
        )
    require(indexed == {("655", "1150")})
    return {
        "selected_executed_queries": len(relative),
        "query_fingerprints": sorted(fingerprint(path) for path in relative),
        "suite_sha256": hashlib.sha256(suite.read_bytes()).hexdigest(),
        "indexed_source_files": 655,
        "indexed_header_files": 1150,
        "compiler_errors": 0,
        "syntax_errors": 0,
        "log_severity_errors_warnings": 0,
    }


def main():
    require(sys.argv[1:] in (["cli"], ["summary"]))
    mode, workspace = os.environ["MODE"], Path.cwd()
    event = read_json(Path(os.environ["GITHUB_EVENT_PATH"]), 4194304)
    require(os.environ["GITHUB_EVENT_NAME"] == "pull_request" and event["number"] == 55)
    require(
        event["repository"]["full_name"]
        == event["pull_request"]["head"]["repo"]["full_name"]
        == "xartaiusx/XI-Server"
    )
    require(
        event["pull_request"]["base"]["sha"]
        == "02c7f2f7729161b1fd3e9588bc28f7c1c652b02a"
    )
    sha = git("rev-parse", "HEAD")
    require(re.fullmatch("[0-9a-f]{40}", sha) and sha == os.environ["GITHUB_SHA"])
    require(not git("status", "--porcelain", "--untracked-files=no"))
    require(
        git("diff", "--name-status", "--no-renames", BASE, "HEAD").splitlines()
        == [
            "A\t.github/scripts/codeql_pr55_diagnostic.py",
            "M\t.github/workflows/codeql_analysis.yml",
        ]
    )
    state = Path(os.environ.get("CODEQL_ACTION_TEMP", os.environ["RUNNER_TEMP"]))
    config = read_json(state / "config", 4194304)
    proof = effective(config, mode)
    require(Path(config["repositoryRoot"]) == workspace)
    require((state / "pr-diff-range.json").is_file() == (mode == "diff-informed"))
    require(
        hashlib.sha256(
            Path(".github/codeql/codeql-config.yml").read_bytes()
        ).hexdigest()
        == CONFIG_SHA
    )
    if sys.argv[1] == "cli":
        require(cli_json(config, "version", "--format=json")["version"] == "2.27.3")
        print(
            "PR55_CODEQL_CONFIGURATION "
            + json.dumps(
                {"mode": mode, "source": sha, "effective": proof}, sort_keys=True
            )
        )
        return
    directory = Path(os.environ["SARIF_DIRECTORY"])
    files = list(directory.glob("*.sarif"))
    require(len(files) == 1)
    document = read_json(files[0], 67108864)
    require(document["version"] == "2.1.0" and len(document["runs"]) == 1)
    allowed = set(git("ls-tree", "-r", "--name-only", BASE).splitlines())
    summary = summarize(document["runs"][0], mode, workspace, allowed)
    summary["execution"] = execution(config, workspace)
    summary.update(
        diagnostic_only=True,
        acceptance=False,
        raw_sarif_retained_durably=False,
        source_commit=sha,
        source_tree=git("rev-parse", "HEAD^{tree}"),
        pull_request_head=event["pull_request"]["head"]["sha"],
        program_baseline=BASE,
        mode=mode,
        cli="2.27.3",
        effective=proof,
        effective_sha256=fingerprint(proof),
        workflow_sha256=hashlib.sha256(
            Path(".github/workflows/codeql_analysis.yml").read_bytes()
        ).hexdigest(),
    )
    encoded = json.dumps(summary, sort_keys=True)
    require(len(encoded.encode()) <= 393216)
    print("PR55_CODEQL_DIAGNOSTIC " + encoded)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        raise SystemExit("PR55_DIAGNOSTIC_UNPROVEN") from None
