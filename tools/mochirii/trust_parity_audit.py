#!/usr/bin/env python3
"""Generate a cross-platform Mochirii Trust parity audit.

The existing PowerShell audit remains useful on Windows.  This companion is for
canonical WSL runs where fresh server logs live under /root/projects/FFXI.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
from collections import Counter, defaultdict
from pathlib import Path

SKILL_NAME_OVERRIDES = {
    "23": "dancing_edge",
    "47": "sanguine_blade",
    "61": "dimidiation",
    "128": "blade_rin",
    "129": "blade_retsu",
    "133": "blade_ei",
    "134": "blade_jin",
    "2016": "dark_shot",
    "3741": "doctors_orders",
    "4253": "mix_panacea-1",
}

MESSAGE_NAME_OVERRIDES = {
    "231": "disappear_num",
    "668": "vallation_gain",
    "669": "valiance_gain_party_member",
}

SPELL_NAME_OVERRIDES = {
    "338": "utsusemi_ichi",
    "462": "magic_finale",
}

REQUIRED_SPELL_ROWS = [
    ("Yoran-Oran UC", 393, 54, "Stoneskin"),
    ("Sylvie UC", 394, 143, "Erase"),
    ("Koru-Moru", 364, 58, "Paralyze"),
    ("Koru-Moru", 364, 80, "Paralyze II"),
    ("Koru-Moru", 364, 216, "Gravity"),
    ("Koru-Moru", 364, 217, "Gravity II"),
    ("Koru-Moru", 364, 253, "Sleep"),
    ("Koru-Moru", 364, 258, "Bind"),
    ("Koru-Moru", 364, 259, "Sleep II"),
    ("Koru-Moru", 364, 286, "Addle"),
    ("Koru-Moru", 364, 843, "Frazzle"),
    ("Koru-Moru", 364, 844, "Frazzle II"),
    ("Joachim", 323, 462, "Magic Finale"),
    ("Matsui-P", 435, 338, "Utsusemi: Ichi"),
    ("Matsui-P", 435, 339, "Utsusemi: Ni"),
    ("Matsui-P", 435, 341, "Jubaku: Ichi"),
    ("Matsui-P", 435, 342, "Jubaku: Ni"),
    ("Matsui-P", 435, 344, "Hojo: Ichi"),
    ("Matsui-P", 435, 345, "Hojo: Ni"),
    ("Matsui-P", 435, 347, "Kurayami: Ichi"),
    ("Matsui-P", 435, 348, "Kurayami: Ni"),
    ("Matsui-P", 435, 350, "Dokumori: Ichi"),
    ("Matsui-P", 435, 351, "Dokumori: Ni"),
]

REQUIRED_SKILL_ROWS = [
    ("Matsui-P", 1148, 128, "Blade: Rin"),
    ("Matsui-P", 1148, 129, "Blade: Retsu"),
    ("Matsui-P", 1148, 133, "Blade: Ei"),
    ("Matsui-P", 1148, 134, "Blade: Jin"),
    ("Matsui-P", 1148, 136, "Blade: Ku"),
    ("Matsui-P", 1148, 138, "Blade: Kamu"),
    ("Matsui-P", 1148, 141, "Blade: Shun"),
    ("Lilisette II", 1128, 23, "Dancing Edge"),
    ("Lilisette II", 1128, 25, "Evisceration"),
    ("Lilisette II", 1128, 29, "Pyrrhic Kleos"),
    ("Lilisette II", 1128, 30, "Aeolian Edge"),
    ("Lilisette II", 1128, 31, "Rudra's Storm"),
    ("Lilisette II", 1128, 224, "Exenterator"),
    ("Selh'teus", 1094, 1508, "Luminous Lance"),
    ("Selh'teus", 1094, 1509, "Rejuvenation"),
    ("Selh'teus", 1094, 1510, "Revelation"),
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def normalize_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", name or "").lower()


def to_int(value: str | None) -> int | None:
    try:
        return int(value) if value not in (None, "", "nil") else None
    except ValueError:
        return None


def to_float(value: str | None) -> float | None:
    try:
        return float(value) if value not in (None, "", "nil", "none") else None
    except ValueError:
        return None


def parse_sql_pairs(sql_text: str, kind: str) -> set[tuple[int, int]]:
    pattern = re.compile(r"\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*,") if kind == "spell" else re.compile(r"\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*\)")
    return {(int(a), int(b)) for a, b in pattern.findall(sql_text)}


def enrich(fields: dict[str, str]) -> dict[str, str]:
    category = fields.get("action_category_name", "")
    skill_id = fields.get("skill_id", "") or (fields.get("action_id", "") if "Skill" in category else "")
    skill_name = fields.get("skill_name", "")
    if (not skill_name or re.match(r"^skill_\d+$", skill_name)) and skill_id in SKILL_NAME_OVERRIDES:
        skill_name = SKILL_NAME_OVERRIDES[skill_id]

    spell_id = fields.get("spell_id", "") or (fields.get("action_id", "") if "Magic" in category else "")
    spell_name = fields.get("spell_name", "")
    if (not spell_name or re.match(r"^spell_\d+$", spell_name)) and spell_id in SPELL_NAME_OVERRIDES:
        spell_name = SPELL_NAME_OVERRIDES[spell_id]

    message_id = fields.get("message_id", "")
    message_name = fields.get("message_name", "")
    if (not message_name or message_name == "msg_unknown") and message_id in MESSAGE_NAME_OVERRIDES:
        message_name = MESSAGE_NAME_OVERRIDES[message_id]

    row = dict(fields)
    row["skill_id_resolved"] = skill_id
    row["skill_name_resolved"] = skill_name
    row["spell_id_resolved"] = spell_id
    row["spell_name_resolved"] = spell_name
    row["message_name_resolved"] = message_name
    row["action_name_resolved"] = skill_name or spell_name or message_name or category
    return row


def parse_log(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    if not path.exists():
        return rows
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw or raw.startswith("#"):
            continue
        fields: dict[str, str] = {}
        for part in raw.split("\t"):
            if "=" in part:
                key, value = part.split("=", 1)
                fields[key] = value
        if "trust" in fields:
            rows.append(enrich(fields))
    return rows


def status_entries(status_text: str) -> list[str]:
    if not status_text or status_text == "none":
        return []
    return [part for part in status_text.split(";") if part and part != "none"]


def effect_names(status_text: str) -> list[str]:
    return [entry.split(":", 1)[0] for entry in status_entries(status_text)]


def effect_entry(status_text: str, effect: str) -> tuple[int, int] | None:
    for entry in status_entries(status_text):
        parts = entry.split(":")
        if not parts or parts[0] != effect:
            continue
        remaining = 0
        duration = 0
        for part in parts[1:]:
            if part.startswith("rem="):
                remaining = int(part.split("=", 1)[1])
            elif part.startswith("dur="):
                duration = int(part.split("=", 1)[1])
        return remaining, duration
    return None


def refresh_window(duration: int) -> int:
    if duration <= 0:
        return 0
    if duration <= 60:
        return 5
    if duration <= 180:
        return 15
    if duration <= 600:
        return 30
    return 60


def spell_effect_name(spell_name: str) -> str | None:
    checks = [
        (r"^protect", "protect"), (r"^shell", "shell"), (r"^haste", "haste"),
        (r"^refresh", "refresh"), (r"^regen", "regen"), (r"^phalanx", "phalanx"),
        (r"^reprisal", "reprisal"), (r"^enlight", "enlight"), (r"^aquaveil", "aquaveil"),
        (r"^stoneskin", "stoneskin"), (r"^blink", "blink"), (r"^reraise", "reraise"),
        (r"^auspice", "auspice"), (r"^boost-mnd", "mnd_boost"), (r"^dia", "dia"),
        (r"^slow", "slow"), (r"^paralyze", "paralysis"), (r"^addle", "addle"),
        (r"^distract", "evasion_down"), (r"^frazzle", "magic_evasion_down"),
        (r"^gravity", "weight"), (r"^bind", "bind"), (r"^flash", "flash"),
        (r"^carnage_elegy|elegy", "elegy"), (r"^sleep|^repose", "sleep_i"),
    ]
    for pattern, effect in checks:
        if re.search(pattern, spell_name or ""):
            return effect
    return None


def group_rows(rows: list[dict[str, str]], keys: tuple[str, ...]) -> dict[tuple[str, ...], list[dict[str, str]]]:
    groups: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[tuple(row.get(key, "") for key in keys)].append(row)
    return groups


def top_groups(groups: dict[tuple[str, ...], list[dict[str, str]]], limit: int | None = None):
    values = sorted(groups.items(), key=lambda item: (-len(item[1]), item[0]))
    return values if limit is None else values[:limit]


def distance_bucket(distance: float | None) -> str:
    if distance is None:
        return "unknown"
    if distance < 10:
        return "<10"
    if distance < 20:
        return "10-20"
    if distance < 30:
        return "20-30"
    if distance < 50:
        return "30-50"
    return "50+"


def max_distance(rows: list[dict[str, str]]) -> str:
    values: list[float] = []
    for row in rows:
        for key in ("distance_to_current_target", "distance_to_packet_target"):
            value = to_float(row.get(key))
            if value is not None:
                values.append(value)
    return f"{max(values):.2f}" if values else ""


def context(rows: list[dict[str, str]]) -> str:
    parts = []
    for row in rows[:3]:
        parts.append(
            f"current={row.get('current_battle_target_name') or 'none'}#{row.get('current_battle_target_targid') or '0'};"
            f"gambitTarget#{row.get('gambit_target_targid') or '0'};"
            f"resolved={row.get('gambit_resolved_id') or '0'};selectArg={row.get('gambit_select_arg') or '0'}"
        )
    return "<br>".join(parts)


def format_status(status_text: str) -> str:
    entries = status_entries(status_text)[:18]
    if not entries:
        return "none"
    suffix = "<br>..." if len(status_entries(status_text)) > len(entries) else ""
    return "<br>".join(entries) + suffix


def generate_report(repo_root: Path, runtime_root: Path, player: str) -> Path:
    trust_dir = repo_root / "scripts/actions/spells/trust"
    module_path = repo_root / "modules/custom/lua/trust_retail_parity.lua"
    spell_sql = "\n".join([read_text(repo_root / "sql/mob_spell_lists.sql"), read_text(repo_root / "modules/custom/sql/trust_retail_parity.sql")])
    skill_sql = "\n".join([read_text(repo_root / "sql/mob_skill_lists.sql"), read_text(repo_root / "modules/custom/sql/trust_retail_parity.sql")])
    log_path = runtime_root / "logs/trust_actions/live" / f"{player}.log"
    report_dir = runtime_root / "reports"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"trust-parity-audit-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}.md"

    trust_scripts = sorted(trust_dir.glob("*.lua"))
    profile_keys = sorted(set(re.findall(r"^\s*([a-z0-9_]+)\s*=\s*\{\s*name\s*=", read_text(module_path), re.MULTILINE)))
    spell_pairs = parse_sql_pairs(spell_sql, "spell")
    skill_pairs = parse_sql_pairs(skill_sql, "skill")
    rows = parse_log(log_path)
    active_trusts = sorted({row.get("trust", "") for row in rows if row.get("trust")})
    active_normalized = {normalize_name(trust) for trust in active_trusts}

    lines = [
        "# Mochirii Trust Parity Audit", "",
        f"- Generated: {dt.datetime.now().isoformat(timespec='seconds')}",
        f"- Trust scripts: {len(trust_scripts)}",
        f"- Explicit profile keys: {len(profile_keys)}",
        f"- Generated audit profile keys: {max(0, len(trust_scripts) - len(profile_keys))}",
        f"- Latest log: {log_path}",
        f"- Active Trusts in latest log: {len(active_trusts)}", "",
        "## Active Trusts",
    ]
    lines.extend([f"- {trust}" for trust in active_trusts] or ["- None found in latest live log."])

    lines += ["", "## Roster Coverage", "| Trust Script | Profile | Active In Latest Log |", "| --- | --- | --- |"]
    for script in trust_scripts:
        key = normalize_name(script.stem)
        lines.append(f"| {script.name} | {'explicit' if key in profile_keys else 'generated-audit'} | {'yes' if key in active_normalized else 'no'} |")

    lines += ["", "## Current Alliance Static Preconditions", "| Type | Trust | List | ID | Name | Status |", "| --- | --- | ---: | ---: | --- | --- |"]
    for trust, list_id, value_id, name in REQUIRED_SPELL_ROWS:
        lines.append(f"| spell | {trust} | {list_id} | {value_id} | {name} | {'ok' if (list_id, value_id) in spell_pairs else 'missing'} |")
    for trust, list_id, value_id, name in REQUIRED_SKILL_ROWS:
        lines.append(f"| skill | {trust} | {list_id} | {value_id} | {name} | {'ok' if (list_id, value_id) in skill_pairs else 'missing'} |")

    lines += ["", "## Latest Log Summary"]
    if not rows:
        lines.append("- No Trust action rows found in the latest live log.")
    else:
        by_trust = group_rows(rows, ("trust",))
        lines += ["| Trust | Rows | Top Events | Last HP% | Last MP% | Last Target | Last Rest | Last Rest Block |", "| --- | ---: | --- | ---: | ---: | --- | --- | --- |"]
        for (trust,), group in sorted(by_trust.items()):
            last = group[-1]
            top = ", ".join(f"{name}={count}" for name, count in Counter(row.get("event", "unknown") for row in group).most_common(4))
            lines.append(f"| {trust} | {len(group)} | {top} | {last.get('trust_hpp', '')} | {last.get('trust_mpp', '')} | {last.get('target_name', '')} | {last.get('trust_rest_mode_name', '')} | {last.get('trust_rest_block', '')} |")

        lines += ["", "## Unresolved Log Names"]
        unresolved: list[tuple[str, str, str]] = []
        for row in rows:
            if re.match(r"^spell_\d+$", row.get("spell_name_resolved", "")):
                unresolved.append(("spell_name", row["spell_name_resolved"], row.get("trust", "")))
            if re.match(r"^skill_\d+$", row.get("skill_name_resolved", "")):
                unresolved.append(("skill_name", row["skill_name_resolved"], row.get("trust", "")))
            if row.get("message_name_resolved") == "msg_unknown":
                unresolved.append(("message_name", row["message_name_resolved"], row.get("trust", "")))
        if not unresolved:
            lines.append("- None found.")
        else:
            lines += ["| Field | Value | Count | Trusts |", "| --- | --- | ---: | --- |"]
            unresolved_groups: dict[tuple[str, str], list[str]] = defaultdict(list)
            for field, value, trust in unresolved:
                unresolved_groups[(field, value)].append(trust)
            for (field, value), trusts in sorted(unresolved_groups.items(), key=lambda item: (-len(item[1]), item[0])):
                lines.append(f"| {field} | {value} | {len(trusts)} | {', '.join(sorted(set(trusts)))} |")

        lines += ["", "## Runtime Action Issues"]
        issues = [row for row in rows if re.search(r"invalid|interrupt|out_of_range|too_far|cannot", " ".join([row.get("event", ""), row.get("source", ""), row.get("message_name_resolved", "")]))]
        if not issues:
            lines.append("- None found in latest log rows.")
        else:
            lines += ["| Trust | Event | Source | Action | Target | Context | Max Distance | Count |", "| --- | --- | --- | --- | --- | --- | ---: | ---: |"]
            for keys, group in top_groups(group_rows(issues, ("trust", "event", "source", "action_name_resolved", "target_name")), 60):
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {context(group)} | {max_distance(group)} | {len(group)} |")

        lines += ["", "## Hostile Magic Stale Target Skips"]
        stale_skips = [row for row in rows if row.get("event") == "stale_target_skip"]
        if not stale_skips:
            lines.append("- None found in latest log rows.")
        else:
            lines += ["| Trust | Action ID | Reason | Current Target | Packet Target | Context | Count |", "| --- | ---: | --- | --- | --- | --- | ---: |"]
            for keys, group in top_groups(group_rows(stale_skips, ("trust", "action_id", "skip_reason", "current_battle_target_name", "packet_target_name")), 60):
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {context(group)} | {len(group)} |")

        lines += ["", "## TP Skill Guard Skips"]
        skips = [row for row in rows if row.get("tp_skill_skip_reason_name") not in (None, "", "none")]
        if not skips:
            lines.append("- None found in latest log rows.")
        else:
            lines += ["| Trust | Reason | Skill ID | Target TargID | Current Target | Count |", "| --- | --- | ---: | ---: | --- | ---: |"]
            for keys, group in top_groups(group_rows(skips, ("trust", "tp_skill_skip_reason_name", "tp_skill_skip_id", "tp_skill_skip_target_targid", "current_battle_target_name")), 60):
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {len(group)} |")

        lines += ["", "## Distance Diagnostics"]
        distances: list[tuple[str, str, str, str, str, str]] = []
        for row in rows:
            current = to_float(row.get("distance_to_current_target"))
            packet = to_float(row.get("distance_to_packet_target"))
            if current is not None and current >= 20:
                distances.append((row.get("trust", ""), row.get("event", ""), row.get("action_name_resolved", ""), row.get("current_battle_target_name", ""), "current", distance_bucket(current)))
            if packet is not None and packet >= 20:
                distances.append((row.get("trust", ""), row.get("event", ""), row.get("action_name_resolved", ""), row.get("packet_target_name", ""), "packet", distance_bucket(packet)))
        if not distances:
            lines.append("- No action rows at 20+ yalms from current or packet target.")
        else:
            lines += ["| Trust | Event | Action | Target | Distance Field | Bucket | Count |", "| --- | --- | --- | --- | --- | --- | ---: |"]
            for keys, count in Counter(distances).most_common(60):
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {keys[5]} | {count} |")

        lines += ["", "## Role Enmity Decisions"]
        role_rows = [row for row in rows if row.get("role_enmity_action_name") not in (None, "", "none")]
        if not role_rows:
            lines.append("- No role-enmity decisions found in latest log rows.")
        else:
            lines += ["| Action | Trusts | Rows |", "| --- | --- | ---: |"]
            for (action,), group in top_groups(group_rows(role_rows, ("role_enmity_action_name",))):
                lines.append(f"| {action} | {', '.join(sorted({row.get('trust', '') for row in group}))} | {len(group)} |")

        lines += ["", "## Alliance Support Scope"]
        support_rows = [row for row in rows if (to_int(row.get("target_count")) or 0) > 1 or (to_int(row.get("result_count")) or 0) > 1]
        if not support_rows:
            lines.append("- No multi-target action packets/results found.")
        else:
            lines += ["| Trust | Source | Category | Action | Max Targets | Max Results | Rows With Fewer Results Than Targets | Count |", "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |"]
            for keys, group in top_groups(group_rows(support_rows, ("trust", "source", "action_category_name", "action_name_resolved")), 60):
                target_counts = [to_int(row.get("target_count")) for row in group if to_int(row.get("target_count")) is not None]
                result_counts = [to_int(row.get("result_count")) for row in group if to_int(row.get("result_count")) is not None]
                missed = sum(1 for row in group if to_int(row.get("target_count")) is not None and to_int(row.get("result_count")) is not None and (to_int(row.get("result_count")) or 0) < (to_int(row.get("target_count")) or 0))
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {max(target_counts) if target_counts else ''} | {max(result_counts) if result_counts else ''} | {missed} | {len(group)} |")

        lines += ["", "## Active Effect Coverage"]
        effects: dict[tuple[str, str], list[str]] = defaultdict(list)
        for row in rows:
            for effect in effect_names(row.get("trust_statuses", "")):
                effects[("trust", effect)].append(row.get("trust", ""))
            for effect in effect_names(row.get("master_statuses", "")):
                effects[("master", effect)].append(row.get("trust", ""))
            for effect in effect_names(row.get("target_statuses", "")):
                effects[("target", effect)].append(row.get("trust", ""))
        if not effects:
            lines.append("- No tracked active effects found in latest log rows.")
        else:
            lines += ["| Scope | Effect | Rows | Trusts Reporting |", "| --- | --- | ---: | --- |"]
            for (scope, effect), trusts in sorted(effects.items(), key=lambda item: (-len(item[1]), item[0]))[:40]:
                lines.append(f"| {scope} | {effect} | {len(trusts)} | {', '.join(sorted(set(trusts)))} |")

        lines += ["", "## Latest Active Effects By Entity", "| Scope | Entity | Latest Effects |", "| --- | --- | --- |"]
        latest_master = next((row for row in reversed(rows) if row.get("master_statuses") and row.get("master_statuses") != "none"), None)
        lines.append(f"| master | {player} | {format_status(latest_master.get('master_statuses', '') if latest_master else '')} |")
        for (trust,), group in sorted(by_trust.items()):
            latest = next((row for row in reversed(group) if row.get("trust_statuses")), None)
            lines.append(f"| trust | {trust} | {format_status(latest.get('trust_statuses', '') if latest else '')} |")
        target_groups = group_rows([row for row in rows if row.get("target_name") and row.get("target_name") != "none" and row.get("target_statuses")], ("target_name",))
        for (target,), group in sorted(target_groups.items()):
            lines.append(f"| target | {target} | {format_status(group[-1].get('target_statuses', ''))} |")

        lines += ["", "## Potential Early Buff/Debuff Refreshes"]
        early: list[tuple[str, str, str, str, int, int, int]] = []
        for row in rows:
            if row.get("event") != "magic_start":
                continue
            effect = spell_effect_name(row.get("spell_name_resolved", ""))
            if effect is None:
                continue
            entry = effect_entry(row.get("target_statuses", ""), effect)
            if entry is None:
                continue
            remaining, duration = entry
            window = refresh_window(duration)
            if remaining > window:
                early.append((row.get("trust", ""), row.get("spell_name_resolved", ""), row.get("target_name", ""), effect, remaining, duration, window))
        if not early:
            lines.append("- None found above the duration-based refresh windows.")
        else:
            lines += ["| Trust | Spell | Target | Effect | Remaining Seconds | Duration Seconds | Refresh Window Seconds | Count |", "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |"]
            for keys, count in Counter(early).most_common(40):
                lines.append(f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {keys[5]} | {keys[6]} | {count} |")

    lines += ["", "## Interpretation", "- explicit: the Trust has a Mochirii role/profile row for audit or behavior work.", "- generated-audit: the Trust script has a generated placeholder profile so roster-wide audits include it while detailed source-backed parity is still pending.", "- Active Trusts should be upgraded before inactive roster entries because their logs provide evidence."]
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Mochirii Trust parity audit report.")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--runtime-root", type=Path, default=Path("/root/projects/FFXI-Runtime"))
    parser.add_argument("--player", default="Twills")
    args = parser.parse_args()
    print(generate_report(args.repo_root.resolve(), args.runtime_root.resolve(), args.player))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
