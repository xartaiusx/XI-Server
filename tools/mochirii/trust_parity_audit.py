#!/usr/bin/env python3
"""Validate and report Mochirii Trust evidence sessions.

Schema-v2 evidence is fail-closed and is the only format eligible for readiness
or combat acceptance. Older logs remain readable as descriptive history, but
they can never satisfy an acceptance gate.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

EVIDENCE_SCHEMA_VERSION = 2
REPORT_SCHEMA_VERSION = 1

MODE_RETAIL = "retail_control"
MODE_ALLIANCE = "twills_full_alliance_qa"
TOPOLOGY_RETAIL = "retail_party_1_plus_5"
TOPOLOGY_ALLIANCE = "virtual_trust_alliance_5_6_6"

RETAIL_ROSTER = (
    (910, "Valaineral"),
    (980, "Yoran-Oran UC"),
    (914, "Ulmia"),
    (1013, "Lilisette II"),
    (1019, "Shantotto II"),
)

ALLIANCE_ROSTER = (
    (984, "August"),
    (980, "Yoran-Oran UC"),
    (952, "Koru-Moru"),
    (967, "Qultada"),
    (1002, "Cornelia"),
    (910, "Valaineral"),
    (999, "Monberaux"),
    (911, "Joachim"),
    (914, "Ulmia"),
    (1013, "Lilisette II"),
    (1003, "Matsui-P"),
    (969, "Amchuchu"),
    (981, "Sylvie UC"),
    (955, "Apururu UC"),
    (1019, "Shantotto II"),
    (935, "Star Sibyl"),
    (979, "Selh'teus"),
)

MODE_CONTRACTS = {
    MODE_RETAIL: {
        "topology": TOPOLOGY_RETAIL,
        "roster": RETAIL_ROSTER,
        "party_counts": (6, 0, 0),
        "party_trust_counts": (5, 0, 0),
        "trust_engage_type": 0,
        "banner": "RETAIL-CONTROL EVIDENCE LANE",
    },
    MODE_ALLIANCE: {
        "topology": TOPOLOGY_ALLIANCE,
        "roster": ALLIANCE_ROSTER,
        "party_counts": (6, 6, 6),
        "party_trust_counts": (5, 6, 6),
        "trust_engage_type": 1,
        "banner": "MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE",
    },
}

COMMON_REQUIRED_FIELDS = {
    "schema_version",
    "record_type",
    "session_id",
    "server_commit",
    "sequence",
    "timestamp_epoch",
    "timestamp_utc",
    "owner",
    "owner_id",
    "evidence_mode",
    "topology",
    "state",
    "generation",
    "zone",
    "trust_engage_type",
    "event",
}

SESSION_BEGIN_FIELDS = {
    "entitlement",
    "actual_gm",
    "visible_gm",
    "authorized",
    "alliance_active",
    "authorization_predicate_available",
    "feature_enabled",
    "max_parties",
    "expected_count",
    "expected_trust_ids",
    "expected_trust_names",
    "expected_party1_count",
    "expected_party2_count",
    "expected_party3_count",
    "expected_party1_trusts",
    "expected_party2_trusts",
    "expected_party3_trusts",
    "expected_party1_trust_ids",
    "expected_party2_trust_ids",
    "expected_party3_trust_ids",
    "aep_setting",
    "aep_effective",
    "unity_setting",
    "unity_effective",
    "campaign_extravaganza_setting",
    "campaign_expo_setting",
    "campaign_extravaganza_effective",
    "campaign_expo_effective",
    "campaign_effective",
    "combat_summoning_setting",
    "combat_summoning_effective",
    "defensive_setting",
    "defensive_effective",
    "shared_target_setting",
    "shared_target_effective",
    "role_enmity_setting",
    "role_enmity_effective",
    "combat_rest_setting",
    "combat_rest_effective",
    "qa_extension",
    "qa_watermark",
    "log_truncated",
}

ROSTER_FIELDS = {
    "expected_count",
    "expected_trust_ids",
    "active_count",
    "active_trust_ids",
    "active_trust_names",
    "real_pc_count",
    "party1_count",
    "party2_count",
    "party3_count",
    "duplicate_count",
    "unexpected_count",
    "order_match",
    "exact_match",
}

ALLOWED_RECORD_TYPES = {
    "session_begin",
    "session_state",
    "roster",
    "logger",
    "checkpoint",
    "diagnostic",
    "combat",
    "session_end",
}
STRUCTURED_EVENTS = {
    "session_begin": {"session_begin"},
    "session_state": {"spawning", "ready", "failed", "idle"},
    "roster": {
        "preflight",
        "cleared",
        "spawn_result",
        "summon_complete",
        "failure",
        "watchdog",
    },
    "checkpoint": {"summon_attempt", "summon_complete", "watchdog"},
    "session_end": {"session_end"},
}
ALLOWED_STATES = {"spawning", "ready", "failed", "idle"}
LOG_ONLY_COMBAT_EVENTS = {"progression_bonus"}
COMBAT_PACKET_EVENTS = {"action_packet", "action_result"}
ACTION_CONTEXT_FIELDS = {
    "action_uid",
    "decision",
    "rejection_reason",
    "outcome",
    "trust",
    "trust_id",
    "trust_entity_id",
    "trust_mp",
    "source",
    "action_category",
    "action_category_name",
    "action_id",
    "action_recast_ms",
    "focus_target_targid",
    "focus_reason",
    "role_enmity_action",
    "role_enmity_target_targid",
    "gambit_target",
    "gambit_reaction",
    "gambit_select",
    "distance_to_current_target",
    "distance_to_primary_target",
    "action_range",
    "distance_to_master",
    "actor_x",
    "actor_y",
    "actor_z",
    "master_x",
    "master_y",
    "master_z",
    "current_target_x",
    "current_target_y",
    "current_target_z",
    "primary_target_x",
    "primary_target_y",
    "primary_target_z",
    "primary_target_objtype",
    "enmity_ce",
    "enmity_ve",
    "enmity_total",
}
ACTION_PACKET_FIELDS = ACTION_CONTEXT_FIELDS | {
    "packet_actor_id",
    "target_count",
    "result_count",
    "total_param",
}
ACTION_RESULT_FIELDS = ACTION_CONTEXT_FIELDS | {
    "packet_actor_id",
    "packet_raw_target_id",
    "packet_target_resolution",
    "target_index",
    "result_index",
    "result_resolution",
    "result_resolution_name",
    "result_param",
    "message_id",
    "message_name",
    "packet_target_objtype",
    "packet_target_x",
    "packet_target_y",
    "packet_target_z",
    "distance_to_packet_target",
}
ACTION_INTEGER_FIELDS = {
    "trust_id": 1,
    "trust_entity_id": 1,
    "trust_mp": 0,
    "action_category": 0,
    "action_id": 0,
    "action_recast_ms": 0,
    "focus_target_targid": 0,
    "focus_reason": 0,
    "role_enmity_action": 0,
    "role_enmity_target_targid": 0,
    "gambit_target": 0,
    "gambit_reaction": 0,
    "gambit_select": 0,
    "primary_target_objtype": 0,
    "packet_actor_id": 1,
}
PACKET_INTEGER_FIELDS = {
    "target_count": 0,
    "result_count": 0,
    "total_param": -(2**63),
}
RESULT_INTEGER_FIELDS = {
    "packet_raw_target_id": 0,
    "target_index": 0,
    "result_index": 0,
    "result_resolution": 0,
    "result_param": -(2**31),
    "message_id": 0,
    "packet_target_objtype": 0,
}
ACTION_FINITE_FIELDS = {
    "distance_to_master": (0.0, False),
    "actor_x": (None, False),
    "actor_y": (None, False),
    "actor_z": (None, False),
    "master_x": (None, False),
    "master_y": (None, False),
    "master_z": (None, False),
    "distance_to_current_target": (0.0, True),
    "distance_to_primary_target": (0.0, True),
    "action_range": (0.0, True),
    "current_target_x": (None, True),
    "current_target_y": (None, True),
    "current_target_z": (None, True),
    "primary_target_x": (None, True),
    "primary_target_y": (None, True),
    "primary_target_z": (None, True),
    "enmity_ce": (0.0, True),
    "enmity_ve": (0.0, True),
    "enmity_total": (0.0, True),
}
RESULT_FINITE_FIELDS = {
    "packet_target_x": (None, True),
    "packet_target_y": (None, True),
    "packet_target_z": (None, True),
    "distance_to_packet_target": (0.0, True),
}
SIGNED_INTEGER_MAXIMUMS = {
    "total_param": 2**63 - 1,
    "result_param": 2**31 - 1,
}
KEY_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
SESSION_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


@dataclass(frozen=True)
class AuditIssue:
    code: str
    message: str
    line: int | None = None

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.line is not None:
            result["line"] = self.line
        return result


@dataclass(frozen=True)
class EvidenceRecord:
    line_number: int
    fields: dict[str, str]

    @property
    def record_type(self) -> str:
        return self.fields.get("record_type", "")

    @property
    def event(self) -> str:
        return self.fields.get("event", "")


@dataclass
class ParsedEvidence:
    path: Path
    records: list[EvidenceRecord] = field(default_factory=list)
    legacy_rows: list[dict[str, str]] = field(default_factory=list)
    comments: list[str] = field(default_factory=list)
    issues: list[AuditIssue] = field(default_factory=list)


@dataclass
class AuditResult:
    report: dict[str, Any]
    rows: list[dict[str, str]]
    exit_code: int
    markdown_path: Path | None = None
    json_path: Path | None = None


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

MONBERAUX_SUPPORT_SKILLS = {
    "4231",
    "4237",
    "4238",
    "4239",
    "4240",
    "4241",
    "4242",
    "4243",
    "4244",
    "4245",
    "4246",
    "4247",
    "4248",
    "4249",
    "4250",
    "4251",
    "4252",
    "4253",
    "4254",
    "4255",
    "4256",
    "4257",
    "4258",
    "4259",
    "4261",
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
    pattern = (
        re.compile(r"\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*,")
        if kind == "spell"
        else re.compile(r"\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*\)")
    )
    return {(int(a), int(b)) for a, b in pattern.findall(sql_text)}


def enrich(fields: dict[str, str]) -> dict[str, str]:
    category = fields.get("action_category_name", "")
    skill_id = fields.get("skill_id", "") or (
        fields.get("action_id", "") if "Skill" in category else ""
    )
    skill_name = fields.get("skill_name", "")
    if (
        not skill_name or re.match(r"^skill_\d+$", skill_name)
    ) and skill_id in SKILL_NAME_OVERRIDES:
        skill_name = SKILL_NAME_OVERRIDES[skill_id]

    spell_id = fields.get("spell_id", "") or (
        fields.get("action_id", "") if "Magic" in category else ""
    )
    spell_name = fields.get("spell_name", "")
    if (
        not spell_name or re.match(r"^spell_\d+$", spell_name)
    ) and spell_id in SPELL_NAME_OVERRIDES:
        spell_name = SPELL_NAME_OVERRIDES[spell_id]

    message_id = fields.get("message_id", "")
    message_name = fields.get("message_name", "")
    if (
        not message_name or message_name == "msg_unknown"
    ) and message_id in MESSAGE_NAME_OVERRIDES:
        message_name = MESSAGE_NAME_OVERRIDES[message_id]

    row = dict(fields)
    row["skill_id_resolved"] = skill_id
    row["skill_name_resolved"] = skill_name
    row["spell_id_resolved"] = spell_id
    row["spell_name_resolved"] = spell_name
    row["message_name_resolved"] = message_name
    row["action_name_resolved"] = skill_name or spell_name or message_name or category
    return row


def _parse_fields(
    raw: str, line_number: int
) -> tuple[dict[str, str], list[AuditIssue]]:
    fields: dict[str, str] = {}
    issues: list[AuditIssue] = []
    for part in raw.split("\t"):
        if not part or "=" not in part:
            issues.append(
                AuditIssue(
                    "malformed_token",
                    "every tab-delimited token must be a nonempty key=value pair",
                    line_number,
                )
            )
            continue
        key, value = part.split("=", 1)
        if not KEY_PATTERN.fullmatch(key):
            issues.append(
                AuditIssue("invalid_key", f"invalid evidence key {key!r}", line_number)
            )
            continue
        if key in fields:
            issues.append(
                AuditIssue(
                    "duplicate_key", f"duplicate evidence key {key!r}", line_number
                )
            )
            continue
        fields[key] = value
    return fields, issues


def parse_evidence(path: Path) -> ParsedEvidence:
    parsed = ParsedEvidence(path=path)
    if not path.exists():
        parsed.issues.append(
            AuditIssue("input_missing", f"evidence log not found: {path}")
        )
        return parsed
    if not path.is_file():
        parsed.issues.append(
            AuditIssue("input_not_file", f"evidence path is not a file: {path}")
        )
        return parsed

    payload = path.read_bytes()
    if not payload:
        parsed.issues.append(AuditIssue("empty_evidence", "evidence log is empty"))
        return parsed
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as exc:
        parsed.issues.append(
            AuditIssue("invalid_utf8", f"evidence log is not strict UTF-8: {exc}")
        )
        return parsed

    if not payload.endswith(b"\n"):
        parsed.issues.append(
            AuditIssue(
                "unterminated_final_row",
                "evidence log does not end with a newline and may be torn",
            )
        )

    saw_noncomment = False
    for line_number, raw in enumerate(text.splitlines(), 1):
        if not raw:
            parsed.issues.append(
                AuditIssue(
                    "blank_line", "blank rows are not valid evidence", line_number
                )
            )
            continue
        if raw.startswith("#"):
            parsed.comments.append(raw)
            continue

        saw_noncomment = True
        fields, line_issues = _parse_fields(raw, line_number)
        parsed.issues.extend(line_issues)
        if "schema_version" in fields and fields["schema_version"] != str(
            EVIDENCE_SCHEMA_VERSION
        ):
            parsed.issues.append(
                AuditIssue(
                    "unsupported_schema",
                    f"unsupported evidence schema {fields['schema_version']!r}",
                    line_number,
                )
            )
        if fields.get("schema_version") != str(EVIDENCE_SCHEMA_VERSION):
            parsed.legacy_rows.append(fields)
            continue
        parsed.records.append(EvidenceRecord(line_number, fields))

    if parsed.records and parsed.legacy_rows:
        parsed.issues.append(
            AuditIssue(
                "mixed_schema",
                "schema-v2 and legacy/headerless rows cannot share an evidence session",
            )
        )
    elif not parsed.records:
        code = (
            "legacy_schema_no_session_contract"
            if saw_noncomment or parsed.comments
            else "empty_evidence"
        )
        parsed.issues.append(
            AuditIssue(
                code,
                "legacy or header-only evidence is descriptive and cannot satisfy acceptance",
            )
        )
    return parsed


def descriptive_rows(parsed: ParsedEvidence) -> list[dict[str, str]]:
    source = [record.fields for record in parsed.records] or parsed.legacy_rows
    rows: list[dict[str, str]] = []
    for fields in source:
        if not (fields.get("trust") or fields.get("trust_name")):
            continue
        row = dict(fields)
        row.setdefault("trust", row.get("trust_name", ""))
        rows.append(enrich(row))
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
        (r"^protect", "protect"),
        (r"^shell", "shell"),
        (r"^haste", "haste"),
        (r"^refresh", "refresh"),
        (r"^regen", "regen"),
        (r"^phalanx", "phalanx"),
        (r"^reprisal", "reprisal"),
        (r"^enlight", "enlight"),
        (r"^aquaveil", "aquaveil"),
        (r"^stoneskin", "stoneskin"),
        (r"^blink", "blink"),
        (r"^reraise", "reraise"),
        (r"^auspice", "auspice"),
        (r"^boost-mnd", "mnd_boost"),
        (r"^dia", "dia"),
        (r"^slow", "slow"),
        (r"^paralyze", "paralysis"),
        (r"^addle", "addle"),
        (r"^distract", "evasion_down"),
        (r"^frazzle", "magic_evasion_down"),
        (r"^gravity", "weight"),
        (r"^bind", "bind"),
        (r"^flash", "flash"),
        (r"^carnage_elegy|elegy", "elegy"),
        (r"^sleep|^repose", "sleep_i"),
    ]
    for pattern, effect in checks:
        if re.search(pattern, spell_name or ""):
            return effect
    return None


def group_rows(
    rows: list[dict[str, str]], keys: tuple[str, ...]
) -> dict[tuple[str, ...], list[dict[str, str]]]:
    groups: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[tuple(row.get(key, "") for key in keys)].append(row)
    return groups


def top_groups(
    groups: dict[tuple[str, ...], list[dict[str, str]]], limit: int | None = None
):
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


def is_support_scope(row: dict[str, str]) -> bool:
    if normalize_name(row.get("trust", "")) == "monberaux":
        for key in (
            "gambit_resolved_id",
            "gambit_select_arg",
            "action_id",
            "result_param",
        ):
            if row.get(key) in MONBERAUX_SUPPORT_SKILLS:
                return True
    if row.get("gambit_target_name") in {"self", "party", "melee"}:
        return True
    if (to_int(row.get("target_count")) or 0) > 1 or (
        to_int(row.get("result_count")) or 0
    ) > 1:
        return True
    message = row.get("message_name_resolved", "")
    if re.search(
        r"roll|receives_effect|starts_casting_self|uses_job_ability|uses_ability_gains_effect",
        message,
    ):
        return True
    if row.get("packet_target_objtype") == "32" and row.get(
        "packet_target_name"
    ) not in ("", "none", "nil"):
        return True
    return False


def is_hostile_scope(row: dict[str, str]) -> bool:
    if is_support_scope(row):
        return False
    if row.get("packet_target_objtype") == "4":
        return True
    category = row.get("action_category_name", "")
    message = row.get("message_name_resolved", "")
    if re.search(
        r"attack|weaponskill|takes_damage|is_hit|casts",
        f"{category} {message}",
        re.IGNORECASE,
    ):
        return True
    return False


def is_support_result_scope(row: dict[str, str]) -> bool:
    if not is_support_scope(row):
        return False
    message = row.get("message_name_resolved", "")
    return bool(
        re.search(
            r"receives_effect|gains_effect|target_receives_effect|magic_gains_effect",
            message,
        )
    )


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


def _add_issue(
    issues: list[AuditIssue],
    code: str,
    message: str,
    record: EvidenceRecord | None = None,
) -> None:
    issues.append(AuditIssue(code, message, record.line_number if record else None))


def _require_fields(
    record: EvidenceRecord, required: set[str], issues: list[AuditIssue]
) -> bool:
    missing = sorted(key for key in required if key not in record.fields)
    if missing:
        _add_issue(
            issues,
            "missing_required_fields",
            f"{record.record_type or 'unknown'} row is missing: {', '.join(missing)}",
            record,
        )
        return False
    blank = sorted(key for key in required if record.fields.get(key) == "")
    if blank:
        _add_issue(
            issues,
            "blank_required_fields",
            f"{record.record_type or 'unknown'} row has blank values: {', '.join(blank)}",
            record,
        )
        return False
    return True


def _int_field(
    record: EvidenceRecord,
    key: str,
    issues: list[AuditIssue],
    minimum: int = 0,
) -> int | None:
    value = record.fields.get(key)
    if value is None:
        return None
    try:
        number = int(value)
    except ValueError:
        _add_issue(issues, "invalid_integer", f"{key} must be an integer", record)
        return None
    if number < minimum:
        _add_issue(
            issues,
            "integer_out_of_range",
            f"{key} must be at least {minimum}",
            record,
        )
        return None
    return number


def _finite_number_field(
    record: EvidenceRecord,
    key: str,
    issues: list[AuditIssue],
    *,
    minimum: float | None = None,
    allow_nil: bool = False,
) -> float | None:
    value = record.fields.get(key)
    if value is None:
        return None
    if value == "nil":
        if allow_nil:
            return None
        _add_issue(issues, "invalid_number", f"{key} must be numeric", record)
        return None
    try:
        number = float(value)
    except ValueError:
        _add_issue(issues, "invalid_number", f"{key} must be numeric", record)
        return None
    if not math.isfinite(number):
        _add_issue(issues, "invalid_number", f"{key} must be finite", record)
        return None
    if minimum is not None and number < minimum:
        _add_issue(
            issues,
            "number_out_of_range",
            f"{key} must be at least {minimum:g}",
            record,
        )
        return None
    return number


def _validate_action_numbers(
    record: EvidenceRecord, issues: list[AuditIssue]
) -> None:
    integer_fields = dict(ACTION_INTEGER_FIELDS)
    if record.event == "action_packet":
        integer_fields.update(PACKET_INTEGER_FIELDS)
    elif record.event == "action_result":
        integer_fields.update(RESULT_INTEGER_FIELDS)
    for key, minimum in integer_fields.items():
        number = _int_field(record, key, issues, minimum=minimum)
        maximum = SIGNED_INTEGER_MAXIMUMS.get(key)
        if maximum is not None and number is not None and number > maximum:
            _add_issue(
                issues,
                "integer_out_of_range",
                f"{key} exceeds its signed schema range",
                record,
            )

    finite_fields = dict(ACTION_FINITE_FIELDS)
    if record.event == "action_result":
        finite_fields.update(RESULT_FINITE_FIELDS)
    for key, (minimum, allow_nil) in finite_fields.items():
        _finite_number_field(
            record,
            key,
            issues,
            minimum=minimum,
            allow_nil=allow_nil,
        )


def _bool_field(
    record: EvidenceRecord, key: str, issues: list[AuditIssue]
) -> bool | None:
    value = record.fields.get(key)
    if value not in {"true", "false"}:
        _add_issue(
            issues,
            "invalid_boolean",
            f"{key} must be the literal true or false",
            record,
        )
        return None
    return value == "true"


def _csv_values(value: str | None) -> list[str]:
    if value in (None, "", "none"):
        return []
    return value.split(",")


def _csv_ints(
    record: EvidenceRecord, key: str, issues: list[AuditIssue]
) -> list[int] | None:
    values = _csv_values(record.fields.get(key))
    if any(not value or not value.isdigit() for value in values):
        _add_issue(
            issues,
            "invalid_integer_list",
            f"{key} must be none or a comma-separated list of unsigned integers",
            record,
        )
        return None
    result = [int(value) for value in values]
    if len(result) != len(set(result)):
        _add_issue(issues, "duplicate_list_value", f"{key} contains duplicates", record)
    return result


def _normalized_names(value: str | None) -> list[str]:
    return [normalize_name(name) for name in _csv_values(value)]


def resolve_repo_commit(repo_root: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    commit = result.stdout.strip().lower()
    if not COMMIT_PATTERN.fullmatch(commit):
        raise ValueError(f"git returned an invalid commit identifier: {commit!r}")
    return commit


def _record_summary(records: list[EvidenceRecord]) -> dict[str, Any]:
    events = Counter(record.event or "unknown" for record in records)
    trusts: dict[str, str] = {}
    for record in records:
        trust_id = record.fields.get("trust_id", "")
        trust_name = record.fields.get("trust_name") or record.fields.get("trust", "")
        if trust_id and trust_name:
            trusts[trust_id] = trust_name
    return {
        "record_count": len(records),
        "event_counts": dict(sorted(events.items())),
        "trusts": [
            {"trust_id": int(trust_id), "name": name}
            for trust_id, name in sorted(
                trusts.items(),
                key=lambda item: int(item[0]) if item[0].isdigit() else 999999,
            )
        ],
    }


def _validate_roster_record(
    record: EvidenceRecord,
    contract: dict[str, Any],
    expected_ids: list[int],
    expected_names: list[str],
    issues: list[AuditIssue],
) -> None:
    if not _require_fields(record, ROSTER_FIELDS, issues):
        return
    expected_count = _int_field(record, "expected_count", issues)
    active_count = _int_field(record, "active_count", issues)
    active_ids = _csv_ints(record, "active_trust_ids", issues)
    active_names = _normalized_names(record.fields.get("active_trust_names"))
    row_expected_ids = _csv_ints(record, "expected_trust_ids", issues)
    if expected_count != len(expected_ids) or row_expected_ids != expected_ids:
        _add_issue(
            issues,
            "roster_expected_mismatch",
            "roster expected IDs do not match the lane",
            record,
        )
    if active_count != len(expected_ids) or active_ids != expected_ids:
        _add_issue(
            issues,
            "roster_active_mismatch",
            "active Trust IDs do not exactly match the locked lane roster",
            record,
        )
    if active_names != expected_names:
        _add_issue(
            issues,
            "roster_name_mismatch",
            "active Trust names do not exactly match the locked lane roster",
            record,
        )
    party_counts = tuple(
        _int_field(record, f"party{index}_count", issues) for index in range(1, 4)
    )
    if party_counts != contract["party_counts"]:
        _add_issue(
            issues,
            "party_count_mismatch",
            f"total party-member counts must be {contract['party_counts']}",
            record,
        )
    if _int_field(record, "real_pc_count", issues) != 1:
        _add_issue(
            issues,
            "pc_count_mismatch",
            "the roster must contain exactly one PC",
            record,
        )
    for key in ("duplicate_count", "unexpected_count"):
        if _int_field(record, key, issues) != 0:
            _add_issue(issues, "roster_contamination", f"{key} must be zero", record)
    for key in ("order_match", "exact_match"):
        if _bool_field(record, key, issues) is not True:
            _add_issue(issues, "roster_not_exact", f"{key} must be true", record)


def validate_evidence(
    parsed: ParsedEvidence,
    *,
    player: str,
    expected_commit: str,
    readiness_only: bool,
    max_age_seconds: int,
    now_epoch: int,
    live_path: Path,
) -> tuple[dict[str, Any], int]:
    issues = list(parsed.issues)
    records = parsed.records
    mode = "unknown"
    session_id = "unknown"
    topology = "unknown"
    newest_epoch: int | None = None

    if max_age_seconds <= 0:
        _add_issue(issues, "invalid_max_age", "max evidence age must be positive")

    sequences: list[int] = []
    epochs: list[int] = []
    for record in records:
        complete = _require_fields(record, COMMON_REQUIRED_FIELDS, issues)
        if not complete:
            continue
        fields = record.fields
        if record.record_type not in ALLOWED_RECORD_TYPES:
            _add_issue(
                issues,
                "unknown_record_type",
                f"unsupported record_type {record.record_type!r}",
                record,
            )
        allowed_events = STRUCTURED_EVENTS.get(record.record_type)
        if allowed_events is not None and record.event not in allowed_events:
            _add_issue(
                issues,
                "unknown_record_event",
                f"unsupported {record.record_type} event {record.event!r}",
                record,
            )
        if fields["state"] not in ALLOWED_STATES:
            _add_issue(
                issues, "invalid_state", f"invalid state {fields['state']!r}", record
            )
        if fields["owner"] != player:
            _add_issue(
                issues, "owner_mismatch", f"owner must be exactly {player}", record
            )
        if not SESSION_PATTERN.fullmatch(fields["session_id"]):
            _add_issue(
                issues,
                "invalid_session_id",
                "session_id contains unsafe characters",
                record,
            )
        if record.record_type != "combat":
            _require_fields(record, {"log_truncated"}, issues)
        commit = fields["server_commit"].lower()
        if not COMMIT_PATTERN.fullmatch(commit):
            _add_issue(
                issues,
                "invalid_server_commit",
                "server_commit must be 40 or 64 lowercase hex characters",
                record,
            )
        elif commit != expected_commit:
            _add_issue(
                issues,
                "server_commit_mismatch",
                f"evidence commit {commit} does not match repository HEAD {expected_commit}",
                record,
            )

        sequence = _int_field(record, "sequence", issues, minimum=1)
        epoch = _int_field(record, "timestamp_epoch", issues, minimum=1)
        _int_field(record, "owner_id", issues, minimum=1)
        _int_field(record, "generation", issues, minimum=1)
        _int_field(record, "zone", issues)
        _int_field(record, "trust_engage_type", issues)
        if sequence is not None:
            sequences.append(sequence)
        if epoch is not None:
            epochs.append(epoch)
            try:
                expected_utc = dt.datetime.fromtimestamp(
                    epoch, dt.timezone.utc
                ).strftime("%Y-%m-%dT%H:%M:%SZ")
            except (OverflowError, OSError, ValueError):
                expected_utc = ""
                _add_issue(
                    issues,
                    "timestamp_out_of_range",
                    "timestamp_epoch is outside the supported UTC range",
                    record,
                )
            if expected_utc and fields["timestamp_utc"] != expected_utc:
                _add_issue(
                    issues,
                    "timestamp_mismatch",
                    "timestamp_utc does not match timestamp_epoch",
                    record,
                )

        if record.record_type == "session_begin":
            _require_fields(record, SESSION_BEGIN_FIELDS, issues)
            if record.event != "session_begin" or fields["state"] != "idle":
                _add_issue(
                    issues,
                    "invalid_session_begin",
                    "session_begin must use event=session_begin and state=idle",
                    record,
                )
        elif record.record_type == "session_state":
            if record.event != fields["state"]:
                _add_issue(
                    issues,
                    "state_event_mismatch",
                    "session_state event must equal its state",
                    record,
                )
            if record.event in {"failed", "idle"}:
                _require_fields(record, {"reason"}, issues)
        elif record.record_type == "roster":
            _require_fields(record, ROSTER_FIELDS, issues)
            if record.event == "spawn_result":
                _require_fields(
                    record,
                    {"trust_id", "trust_name", "spawn_index", "spawn_ok"},
                    issues,
                )
        elif record.record_type == "logger":
            if record.event in {"logger_attached", "logger_attach_failed"}:
                _require_fields(
                    record,
                    {"trust_id", "trust_name", "attach_reason", "attached_count"},
                    issues,
                )
            elif record.event == "log_truncated":
                _require_fields(record, {"log_truncated", "reason"}, issues)
            else:
                _add_issue(
                    issues,
                    "unknown_logger_event",
                    f"unsupported logger event {record.event!r}",
                    record,
                )
        elif record.record_type == "checkpoint":
            _require_fields(record, {"log_truncated"}, issues)
        elif record.record_type == "diagnostic":
            _require_fields(
                record,
                {
                    "trust",
                    "trust_id",
                    "focus_target_targid",
                    "focus_reason",
                    "role_enmity_action",
                    "role_enmity_target_targid",
                    "trust_rest_mode",
                    "trust_rest_start_reason",
                },
                issues,
            )
        elif record.record_type == "combat":
            if record.event == "action_packet":
                _require_fields(record, ACTION_PACKET_FIELDS, issues)
                _validate_action_numbers(record, issues)
            elif record.event == "action_result":
                _require_fields(record, ACTION_RESULT_FIELDS, issues)
                _validate_action_numbers(record, issues)
            elif record.event == "stale_target_skip":
                _require_fields(
                    record,
                    {
                        "action_uid",
                        "decision",
                        "rejection_reason",
                        "outcome",
                        "trust",
                        "trust_id",
                        "source",
                        "action_id",
                        "action_recast_ms",
                        "action_range",
                        "actor_x",
                        "actor_y",
                        "actor_z",
                        "master_x",
                        "master_y",
                        "master_z",
                        "packet_target_x",
                        "packet_target_y",
                        "packet_target_z",
                        "enmity_ce",
                        "enmity_ve",
                        "enmity_total",
                    },
                    issues,
                )
            elif record.event == "progression_bonus":
                _require_fields(
                    record,
                    {
                        "trust",
                        "trust_id",
                        "aep_hp_rank",
                        "aep_mp_rank",
                        "aep_stat_rank",
                        "aep_combat_rank",
                        "aep_magic_rank",
                        "unity_parity_rank",
                        "unity_parity_stat_bonus",
                    },
                    issues,
                )
            else:
                _add_issue(
                    issues,
                    "unknown_combat_event",
                    f"unsupported combat event {record.event!r}",
                    record,
                )
        elif record.record_type == "session_end":
            _require_fields(
                record,
                ROSTER_FIELDS
                | {
                    "completion",
                    "reason",
                    "log_truncated",
                    "pending_timers",
                    "final_pending_timers",
                },
                issues,
            )
            if record.event != "session_end" or fields["state"] != "idle":
                _add_issue(
                    issues,
                    "invalid_session_end",
                    "session_end must use event=session_end and state=idle",
                    record,
                )
            if fields.get("completion") != "cleared":
                _add_issue(
                    issues,
                    "incomplete_session",
                    "accepted archived evidence must end with completion=cleared",
                    record,
                )
            else:
                terminal_counts = {
                    "active_count": 0,
                    "real_pc_count": 1,
                    "party1_count": 1,
                    "party2_count": 0,
                    "party3_count": 0,
                    "duplicate_count": 0,
                    "unexpected_count": 0,
                    "pending_timers": 0,
                    "final_pending_timers": 0,
                }
                for key, expected in terminal_counts.items():
                    if _int_field(record, key, issues) != expected:
                        _add_issue(
                            issues,
                            "terminal_cleanup_mismatch",
                            f"terminal {key} must be {expected}",
                            record,
                        )
                if _csv_ints(record, "active_trust_ids", issues):
                    _add_issue(
                        issues,
                        "terminal_cleanup_mismatch",
                        "terminal active_trust_ids must be empty",
                        record,
                    )
                if _normalized_names(fields.get("active_trust_names")):
                    _add_issue(
                        issues,
                        "terminal_cleanup_mismatch",
                        "terminal active_trust_names must be empty",
                        record,
                    )
            if to_int(fields.get("trust_engage_type")) != 0:
                _add_issue(
                    issues,
                    "terminal_engage_type",
                    "session_end must restore TrustEngageType=0",
                    record,
                )

    if records:
        session_ids = {record.fields.get("session_id", "") for record in records}
        modes = {record.fields.get("evidence_mode", "") for record in records}
        topologies = {record.fields.get("topology", "") for record in records}
        stable_fields = (
            "server_commit",
            "owner",
            "owner_id",
            "generation",
            "zone",
        )
        for key in stable_fields:
            values = {record.fields.get(key, "") for record in records}
            if len(values) != 1:
                _add_issue(
                    issues, "mixed_session_context", f"{key} changes inside the session"
                )
        if len(session_ids) != 1:
            _add_issue(
                issues, "mixed_sessions", "evidence contains more than one session_id"
            )
        else:
            session_id = next(iter(session_ids))
            first = records[0]
            owner_id = to_int(first.fields.get("owner_id"))
            generation = to_int(first.fields.get("generation"))
            session_match = re.fullmatch(
                rf"{re.escape(player)}-{owner_id}-(\d+)-{generation}", session_id
            )
            if not session_match:
                _add_issue(
                    issues,
                    "session_id_context_mismatch",
                    "session_id must encode owner, owner_id, start epoch, and generation",
                    first,
                )
            else:
                started_at = int(session_match.group(1))
                first_epoch = to_int(first.fields.get("timestamp_epoch"))
                if first_epoch is None or not 0 <= first_epoch - started_at <= 60:
                    _add_issue(
                        issues,
                        "session_start_mismatch",
                        "session_id start epoch must precede the begin row by at most 60 seconds",
                        first,
                    )
        if len(modes) != 1:
            _add_issue(
                issues, "mixed_modes", "evidence contains more than one evidence_mode"
            )
        else:
            mode = next(iter(modes))
        if len(topologies) != 1:
            _add_issue(
                issues, "mixed_topologies", "evidence contains more than one topology"
            )
        else:
            topology = next(iter(topologies))

        expected_sequences = list(range(1, len(records) + 1))
        if sequences != expected_sequences:
            _add_issue(
                issues,
                "invalid_sequence",
                "sequence must start at 1 and increase by exactly one in file order",
            )
        if epochs != sorted(epochs):
            _add_issue(
                issues, "timestamp_regression", "timestamps regress inside the session"
            )
        if epochs:
            newest_epoch = max(epochs)
            age = now_epoch - newest_epoch
            if age > max_age_seconds:
                _add_issue(
                    issues,
                    "stale_evidence",
                    f"latest row is {age} seconds old; maximum is {max_age_seconds}",
                )
            if age < -300:
                _add_issue(
                    issues,
                    "future_evidence",
                    "latest row is more than five minutes in the future",
                )

        begins = [record for record in records if record.record_type == "session_begin"]
        ends = [record for record in records if record.record_type == "session_end"]
        spawning_states = [
            record
            for record in records
            if record.record_type == "session_state"
            and record.event == "spawning"
            and record.fields.get("state") == "spawning"
        ]
        if len(begins) != 1 or records[0].record_type != "session_begin":
            _add_issue(
                issues,
                "invalid_session_begin",
                "exactly one session_begin must be the first row",
            )
        if len(ends) > 1 or (ends and records[-1].record_type != "session_end"):
            _add_issue(
                issues,
                "invalid_session_end",
                "session_end may appear once and must be the final row",
            )
        if not spawning_states:
            _add_issue(
                issues,
                "missing_spawning_state",
                "session has no authoritative spawning transition",
            )
        elif begins:
            begin_index = records.index(begins[0])
            spawning_index = records.index(spawning_states[0])
            preflight_indices = [
                index
                for index, record in enumerate(records)
                if record.record_type == "roster"
                and record.event == "preflight"
                and record.fields.get("state") == "idle"
                and begin_index < index < spawning_index
            ]
            cleared_indices = [
                index
                for index, record in enumerate(records)
                if record.record_type == "roster"
                and record.event == "cleared"
                and record.fields.get("state") == "idle"
                and begin_index < index < spawning_index
            ]
            if (
                not preflight_indices
                or not cleared_indices
                or preflight_indices[0] >= cleared_indices[0]
            ):
                _add_issue(
                    issues,
                    "invalid_prepare_sequence",
                    "idle session_begin must be followed by idle preflight and clear before spawning",
                )
        try:
            is_live_input = parsed.path.resolve() == live_path.resolve()
        except OSError:
            is_live_input = False
        if not is_live_input and not ends:
            _add_issue(
                issues,
                "archive_not_closed",
                "non-live evidence requires a terminal session_end",
            )
        if not readiness_only and not ends:
            _add_issue(
                issues,
                "combat_session_not_closed",
                "combat acceptance requires a clean terminal session_end",
            )
    else:
        begins = []
        ends = []
        spawning_states = []

    if mode == MODE_RETAIL:
        for record in records:
            for key in ("focus_reason", "role_enmity_action"):
                if key in record.fields and _int_field(record, key, issues) not in (None, 0):
                    _add_issue(
                        issues,
                        "mode_isolation_failure",
                        f"retail evidence must report {key}=0",
                        record,
                    )
            if record.record_type == "diagnostic":
                rest_mode = _int_field(record, "trust_rest_mode", issues)
                rest_start_reason = _int_field(
                    record, "trust_rest_start_reason", issues
                )
                if rest_mode == 2 or rest_start_reason == 4:
                    _add_issue(
                        issues,
                        "mode_isolation_failure",
                        "retail diagnostics must not expose combat-rest state",
                        record,
                    )

    contract = MODE_CONTRACTS.get(mode)
    if contract is None:
        _add_issue(
            issues, "invalid_evidence_mode", f"unsupported evidence mode {mode!r}"
        )
        expected_ids: list[int] = []
        expected_names: list[str] = []
    else:
        expected_ids = [trust_id for trust_id, _ in contract["roster"]]
        expected_names = [normalize_name(name) for _, name in contract["roster"]]
        expected_identity = {
            trust_id: normalize_name(name) for trust_id, name in contract["roster"]
        }
        if topology != contract["topology"]:
            _add_issue(
                issues,
                "lane_topology_mismatch",
                "topology does not match evidence_mode",
            )
        spawning_index = records.index(spawning_states[0]) if spawning_states else None
        for record_index, record in enumerate(records):
            engage_type = to_int(record.fields.get("trust_engage_type"))
            terminal_idle = (
                spawning_index is not None
                and record_index > spawning_index
                and record.fields.get("state") == "idle"
                and record.event in {"cleared", "idle", "session_end"}
            )
            if not terminal_idle and engage_type != contract["trust_engage_type"]:
                _add_issue(
                    issues,
                    "engage_type_mismatch",
                    f"TrustEngageType must be {contract['trust_engage_type']} in this lane",
                    record,
                )

        for record in records:
            if "trust_id" not in record.fields:
                continue
            trust_id = _int_field(record, "trust_id", issues, minimum=1)
            trust_name = record.fields.get("trust_name") or record.fields.get("trust")
            if (
                trust_id not in expected_identity
                or not trust_name
                or normalize_name(trust_name) != expected_identity.get(trust_id)
            ):
                _add_issue(
                    issues,
                    "trust_identity_mismatch",
                    "row Trust identity is not in the locked lane roster",
                    record,
                )

    if begins and contract:
        begin = begins[0]
        expected_begin_ids = _csv_ints(begin, "expected_trust_ids", issues)
        expected_begin_names = _normalized_names(
            begin.fields.get("expected_trust_names")
        )
        if _int_field(begin, "expected_count", issues) != len(expected_ids):
            _add_issue(
                issues,
                "expected_count_mismatch",
                "expected_count does not match the locked roster",
                begin,
            )
        if expected_begin_ids != expected_ids or expected_begin_names != expected_names:
            _add_issue(
                issues,
                "expected_roster_mismatch",
                "session expected roster does not match the locked lane roster",
                begin,
            )
        party_counts = tuple(
            _int_field(begin, f"expected_party{index}_count", issues)
            for index in range(1, 4)
        )
        if party_counts != contract["party_trust_counts"]:
            _add_issue(
                issues,
                "expected_party_count_mismatch",
                "expected Trust-only party counts are incorrect",
                begin,
            )
        party_offsets = (
            0,
            contract["party_trust_counts"][0],
            sum(contract["party_trust_counts"][:2]),
            len(expected_ids),
        )
        for party_index in range(1, 4):
            start = party_offsets[party_index - 1]
            end = party_offsets[party_index]
            party_ids = _csv_ints(
                begin, f"expected_party{party_index}_trust_ids", issues
            )
            party_names = _normalized_names(
                begin.fields.get(f"expected_party{party_index}_trusts")
            )
            if (
                party_ids != expected_ids[start:end]
                or party_names != expected_names[start:end]
            ):
                _add_issue(
                    issues,
                    "expected_party_roster_mismatch",
                    f"expected party {party_index} Trust roster is incorrect",
                    begin,
                )

        expected_scalars = {
            "actual_gm": 5,
            "visible_gm": 0,
            "max_parties": 3,
        }
        for key, expected in expected_scalars.items():
            if _int_field(begin, key, issues) != expected:
                _add_issue(
                    issues, "authorization_mismatch", f"{key} must be {expected}", begin
                )
        if _int_field(begin, "entitlement", issues) != 1:
            _add_issue(issues, "authorization_mismatch", "entitlement must be 1", begin)
        for key in (
            "authorized",
            "authorization_predicate_available",
            "feature_enabled",
            "aep_setting",
            "aep_effective",
            "unity_setting",
            "defensive_setting",
            "shared_target_setting",
            "role_enmity_setting",
            "combat_rest_setting",
        ):
            if _bool_field(begin, key, issues) is not True:
                _add_issue(
                    issues, "authorization_mismatch", f"{key} must be true", begin
                )

        extension_expected = mode == MODE_ALLIANCE
        if _bool_field(begin, "alliance_active", issues) is not False:
            _add_issue(
                issues,
                "mode_isolation_failure",
                "alliance_active must be false during the idle prepare phase",
                begin,
            )
        for key in ("combat_summoning_setting", "combat_summoning_effective"):
            if _bool_field(begin, key, issues) is not False:
                _add_issue(
                    issues,
                    "mode_isolation_failure",
                    f"{key} must be false for pre-combat readiness",
                    begin,
                )
        campaign_extravaganza = _int_field(
            begin, "campaign_extravaganza_setting", issues
        )
        campaign_expo = _int_field(begin, "campaign_expo_setting", issues)
        if campaign_extravaganza not in {0, 1, 2, 3}:
            _add_issue(
                issues,
                "invalid_campaign_setting",
                "campaign_extravaganza_setting must be 0, 1, 2, or 3",
                begin,
            )
        if campaign_expo not in {0, 1, 2}:
            _add_issue(
                issues,
                "invalid_campaign_setting",
                "campaign_expo_setting must be 0, 1, or 2",
                begin,
            )
        extravaganza_effective = False
        expo_effective = bool(extension_expected and (campaign_expo or 0) != 0)
        campaign_effective = expo_effective
        if (
            _bool_field(begin, "campaign_extravaganza_effective", issues)
            is not extravaganza_effective
        ):
            _add_issue(
                issues,
                "mode_isolation_failure",
                "campaign_extravaganza_effective must remain false while the Lua campaign is hard-disabled",
                begin,
            )
        if _bool_field(begin, "campaign_expo_effective", issues) is not expo_effective:
            _add_issue(
                issues,
                "mode_isolation_failure",
                "campaign_expo_effective must match the QA lane and raw Expo setting",
                begin,
            )
        if _bool_field(begin, "campaign_effective", issues) is not campaign_effective:
            _add_issue(
                issues,
                "mode_isolation_failure",
                "campaign_effective does not match actual gated campaign behavior",
                begin,
            )

        extension_keys = (
            "unity_effective",
            "defensive_effective",
            "shared_target_effective",
            "role_enmity_effective",
            "combat_rest_effective",
        )
        for key in extension_keys:
            if _bool_field(begin, key, issues) is not extension_expected:
                _add_issue(
                    issues,
                    "mode_isolation_failure",
                    f"{key} must be {str(extension_expected).lower()} in {mode}",
                    begin,
                )
        if _bool_field(begin, "qa_extension", issues) is not extension_expected:
            _add_issue(
                issues,
                "mode_isolation_failure",
                f"qa_extension must be {str(extension_expected).lower()} in {mode}",
                begin,
            )
        expected_watermark = (
            "MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE"
            if extension_expected
            else "none"
        )
        if begin.fields.get("qa_watermark") != expected_watermark:
            _add_issue(
                issues,
                "mode_isolation_failure",
                f"qa_watermark must be {expected_watermark!r}",
                begin,
            )

    integrity_records = [
        record for record in records if "log_truncated" in record.fields
    ]
    for record in integrity_records:
        if _bool_field(record, "log_truncated", issues) is not False:
            _add_issue(
                issues,
                "log_truncated",
                "acceptance requires an explicit false log_truncated marker",
                record,
            )

    failed_records = [
        record
        for record in records
        if record.fields.get("state") == "failed"
        or record.event in {"failure", "logger_attach_failed", "log_truncated"}
        or record.fields.get("spawn_ok") == "false"
    ]
    if failed_records:
        _add_issue(
            issues,
            "session_failure",
            "the evidence session contains a failure transition",
            failed_records[0],
        )

    ready_states = [
        record
        for record in records
        if record.record_type == "session_state"
        and record.event == "ready"
        and record.fields.get("state") == "ready"
    ]
    checkpoints = [
        record
        for record in records
        if record.record_type == "checkpoint"
        and record.event == "summon_complete"
        and record.fields.get("state") == "ready"
    ]
    roster_records = [
        record
        for record in records
        if record.record_type == "roster" and record.event == "summon_complete"
    ]
    if not ready_states:
        _add_issue(
            issues,
            "missing_ready_state",
            "session has no authoritative ready transition",
        )
    elif spawning_states and records.index(ready_states[0]) <= records.index(spawning_states[0]):
        _add_issue(
            issues,
            "invalid_state_sequence",
            "authoritative ready must follow authoritative spawning",
            ready_states[0],
        )
    authoritative_state_events = [
        record.event for record in records if record.record_type == "session_state"
    ]
    expected_state_events = ["spawning", "ready"] + (["idle"] if ends else [])
    if authoritative_state_events != expected_state_events:
        _add_issue(
            issues,
            "invalid_state_sequence",
            "authoritative session_state sequence must be exactly "
            + " -> ".join(expected_state_events),
        )
    if not checkpoints:
        _add_issue(
            issues,
            "missing_readiness_checkpoint",
            "session has no ready summon_complete checkpoint",
        )
    if not roster_records:
        _add_issue(
            issues,
            "missing_complete_roster",
            "session has no summon_complete roster snapshot",
        )
    elif contract:
        _validate_roster_record(
            roster_records[-1], contract, expected_ids, expected_names, issues
        )
    if checkpoints and contract:
        checkpoint = checkpoints[-1]
        _require_fields(
            checkpoint,
            SESSION_BEGIN_FIELDS
            | ROSTER_FIELDS
            | {"attached_count", "pending_timers", "combat_acceptance"},
            issues,
        )
        _validate_roster_record(
            checkpoint, contract, expected_ids, expected_names, issues
        )
        if begins:
            begin = begins[0]
            for key in SESSION_BEGIN_FIELDS - {"alliance_active", "log_truncated"}:
                if checkpoint.fields.get(key) != begin.fields.get(key):
                    _add_issue(
                        issues,
                        "readiness_snapshot_mismatch",
                        f"readiness checkpoint changed lane field {key}",
                        checkpoint,
                    )
        extension_expected = mode == MODE_ALLIANCE
        projected_records = [*spawning_states, *ready_states, checkpoint]
        for record in projected_records:
            _require_fields(record, {"alliance_active"}, issues)
            if _bool_field(record, "alliance_active", issues) is not extension_expected:
                _add_issue(
                    issues,
                    "mode_isolation_failure",
                    "alliance_active must enable only for active QA projection states",
                    record,
                )
        if ready_states and records.index(checkpoint) <= records.index(ready_states[0]):
            _add_issue(
                issues,
                "invalid_readiness_sequence",
                "summon_complete checkpoint must follow the authoritative ready transition",
                checkpoint,
            )
        if checkpoint.fields.get("combat_acceptance") != "not_run":
            _add_issue(
                issues,
                "readiness_claims_combat",
                "summon_complete checkpoint must report combat_acceptance=not_run",
                checkpoint,
            )
        if _int_field(checkpoint, "attached_count", issues) != len(expected_ids):
            _add_issue(
                issues,
                "logger_count_mismatch",
                "readiness checkpoint attached_count does not match the roster",
                checkpoint,
            )
        _int_field(checkpoint, "pending_timers", issues)

    attached = [
        record
        for record in records
        if record.record_type == "logger" and record.event == "logger_attached"
    ]
    attached_ids = [
        _int_field(record, "trust_id", issues, minimum=1) for record in attached
    ]
    attached_ids_clean = [value for value in attached_ids if value is not None]
    if Counter(attached_ids_clean) != Counter(expected_ids):
        _add_issue(
            issues,
            "logger_coverage_mismatch",
            "successful logger attachments must cover every locked-roster Trust exactly once",
        )
    if attached:
        if _int_field(attached[-1], "attached_count", issues) != len(expected_ids):
            _add_issue(
                issues,
                "logger_count_mismatch",
                "final attached_count does not match roster size",
                attached[-1],
            )

    progression_records = [
        record
        for record in records
        if record.record_type == "combat" and record.event == "progression_bonus"
    ]
    progression_ids = [
        _int_field(record, "trust_id", issues, minimum=1)
        for record in progression_records
    ]
    progression_ids_clean = [value for value in progression_ids if value is not None]
    for record in progression_records:
        for key in (
            "aep_hp_rank",
            "aep_mp_rank",
            "aep_stat_rank",
            "aep_combat_rank",
            "aep_magic_rank",
            "unity_parity_rank",
        ):
            _int_field(record, key, issues)
        unity_stat_bonus = _int_field(
            record, "unity_parity_stat_bonus", issues, minimum=0
        )
        if mode == MODE_RETAIL and unity_stat_bonus not in (None, 0):
            _add_issue(
                issues,
                "mode_isolation_failure",
                "retail progression rows must report unity_parity_stat_bonus=0",
                record,
            )
    if Counter(progression_ids_clean) != Counter(expected_ids):
        _add_issue(
            issues,
            "progression_vector_mismatch",
            "AEP and Unity progression rows must cover every locked-roster Trust exactly once",
        )

    combat_activity = [
        record
        for record in records
        if (
            record.record_type == "combat"
            and record.event not in LOG_ONLY_COMBAT_EVENTS
        )
    ]
    combat_pass = False
    if readiness_only:
        if combat_activity:
            _add_issue(
                issues,
                "unexpected_combat_evidence",
                "readiness-only evidence must remain noncombat",
                combat_activity[0],
            )
    else:
        packets = [
            record
            for record in records
            if record.record_type == "combat"
            and record.event == "action_packet"
            and record.fields.get("state") == "ready"
        ]
        results = [
            record
            for record in records
            if record.record_type == "combat"
            and record.event == "action_result"
            and record.fields.get("state") == "ready"
        ]
        for packet in packets:
            if (
                packet.fields.get("decision") != "executed"
                or packet.fields.get("rejection_reason") != "none"
                or packet.fields.get("outcome") != "packet_emitted"
            ):
                _add_issue(
                    issues,
                    "invalid_combat_decision",
                    "action_packet must record an executed, unrejected packet_emitted decision",
                    packet,
                )
        for result in results:
            if (
                result.fields.get("decision") != "executed"
                or result.fields.get("rejection_reason") != "none"
                or result.fields.get("outcome") in {None, "", "unknown", "skipped"}
            ):
                _add_issue(
                    issues,
                    "invalid_combat_decision",
                    "action_result must record an executed, unrejected resolved outcome",
                    result,
                )
        hostile_packets = [
            record
            for record in packets
            if record.fields.get("primary_target_objtype") == "4"
            or record.fields.get("current_battle_target_objtype") == "4"
        ]
        hostile_results = [
            record
            for record in results
            if record.fields.get("packet_target_objtype") == "4"
        ]
        if not hostile_packets or not hostile_results:
            _add_issue(
                issues,
                "insufficient_combat_evidence",
                "combat acceptance requires a hostile action_packet and action_result",
            )
        else:
            correlation_fields = (
                "action_uid",
                "trust_id",
                "packet_actor_id",
                "action_category",
                "action_id",
                "source",
            )
            correlated = any(
                all(
                    packet.fields.get(key) == result.fields.get(key)
                    for key in correlation_fields
                )
                for packet in hostile_packets
                for result in hostile_results
            )
            if not correlated:
                _add_issue(
                    issues,
                    "uncorrelated_combat_evidence",
                    "no hostile action_packet has a matching action_result",
                )
            else:
                combat_pass = True

    issue_dicts = [issue.as_dict() for issue in issues]
    readiness_pass = not issues
    if not readiness_only:
        readiness_pass = not [
            issue
            for issue in issues
            if issue.code
            not in {
                "insufficient_combat_evidence",
                "uncorrelated_combat_evidence",
            }
        ]
    accepted = not issues and (readiness_only or combat_pass)
    issue_codes = {issue.code for issue in issues}
    authorization_codes = {
        "authorization_mismatch",
        "invalid_campaign_setting",
        "engage_type_mismatch",
        "invalid_evidence_mode",
        "lane_topology_mismatch",
        "mode_isolation_failure",
        "mixed_modes",
        "mixed_topologies",
    }
    roster_codes = {
        "expected_count_mismatch",
        "expected_party_count_mismatch",
        "expected_party_roster_mismatch",
        "expected_roster_mismatch",
        "missing_complete_roster",
        "missing_readiness_checkpoint",
        "missing_ready_state",
        "party_count_mismatch",
        "pc_count_mismatch",
        "progression_vector_mismatch",
        "roster_active_mismatch",
        "roster_contamination",
        "roster_expected_mismatch",
        "roster_name_mismatch",
        "roster_not_exact",
        "session_failure",
        "trust_identity_mismatch",
    }
    logger_codes = {"logger_count_mismatch", "logger_coverage_mismatch"}
    combat_codes = {
        "insufficient_combat_evidence",
        "invalid_combat_decision",
        "uncorrelated_combat_evidence",
        "unexpected_combat_evidence",
    }
    integrity_codes = (
        issue_codes - authorization_codes - roster_codes - logger_codes - combat_codes
    )
    lane_classification = "mochirii_extension" if mode == MODE_ALLIANCE else mode
    banner = MODE_CONTRACTS.get(mode, {}).get(
        "banner", "INVALID OR UNCLASSIFIED EVIDENCE"
    )
    if readiness_only:
        banners = ["READINESS ONLY — NO COMBAT ACCEPTANCE", banner]
    else:
        banners = [
            "SINGLE-LANE COMBAT EVIDENCE — NO CROSS-LANE PARITY ACCEPTANCE",
            banner,
        ]

    report = {
        "report_schema_version": REPORT_SCHEMA_VERSION,
        "evidence_schema_version": EVIDENCE_SCHEMA_VERSION,
        "generated_at": dt.datetime.fromtimestamp(
            now_epoch, dt.timezone.utc
        ).isoformat(),
        "requested_audit": "readiness" if readiness_only else "combat",
        "status": "pass" if accepted else "fail",
        "exit_code": 0 if accepted else 1,
        "readiness_acceptance": "pass" if readiness_pass else "fail",
        "combat_acceptance": (
            "not_run" if readiness_only else ("pass" if accepted else "fail")
        ),
        "lane_acceptance": (
            "not_run" if readiness_only else ("pass" if accepted else "fail")
        ),
        # A single evidence file can establish only its own lane. Cross-lane
        # parity requires a future comparison of fresh QA and retail sessions.
        "parity_acceptance": "not_run",
        "retail_acceptance": (
            "not_run"
            if readiness_only
            else (
                "not_applicable"
                if mode == MODE_ALLIANCE
                else ("pass" if accepted else "fail")
            )
        ),
        "extension_acceptance": (
            "not_run"
            if readiness_only
            else (
                ("pass" if accepted else "fail")
                if mode == MODE_ALLIANCE
                else "not_applicable"
            )
        ),
        "evidence_mode": mode,
        "topology": topology,
        "lane_classification": lane_classification,
        "banners": banners,
        "source_log": str(parsed.path),
        "max_age_seconds": max_age_seconds,
        "session": {
            "session_id": session_id,
            "server_commit": (
                records[0].fields.get("server_commit", "") if records else ""
            ),
            "owner": records[0].fields.get("owner", "") if records else "",
            "generation": (
                to_int(records[0].fields.get("generation")) if records else None
            ),
            "zone": to_int(records[0].fields.get("zone")) if records else None,
            "newest_timestamp_epoch": newest_epoch,
            "closed": bool(ends),
        },
        "checks": [
            {
                "name": "schema_and_session_integrity",
                "status": "pass" if records and not integrity_codes else "fail",
            },
            {
                "name": "authorization_and_mode_isolation",
                "status": (
                    "pass"
                    if contract and begins and not (issue_codes & authorization_codes)
                    else "fail"
                ),
            },
            {
                "name": "topology_and_roster",
                "status": (
                    "pass"
                    if roster_records and not (issue_codes & roster_codes)
                    else "fail"
                ),
            },
            {
                "name": "logger_coverage",
                "status": (
                    "pass"
                    if Counter(attached_ids_clean) == Counter(expected_ids)
                    else "fail"
                ),
            },
            {
                "name": "aep_and_unity_vectors",
                "status": (
                    "pass"
                    if Counter(progression_ids_clean) == Counter(expected_ids)
                    else "fail"
                ),
            },
            {
                "name": "combat",
                "status": (
                    "not_run" if readiness_only else ("pass" if combat_pass else "fail")
                ),
            },
        ],
        "issues": issue_dicts,
        "evidence_summary": _record_summary(records),
        "legacy": {
            "comment_count": len(parsed.comments),
            "row_count": len(parsed.legacy_rows),
            "descriptive_only": bool(parsed.comments or parsed.legacy_rows),
        },
    }
    return report, report["exit_code"]


def generate_report(
    repo_root: Path,
    runtime_root: Path,
    player: str,
    *,
    input_path: Path | None = None,
    readiness_only: bool = False,
    max_age_seconds: int = 1800,
    now_epoch: int | None = None,
    expected_commit: str | None = None,
) -> AuditResult:
    trust_dir = repo_root / "scripts/actions/spells/trust"
    module_path = repo_root / "modules/custom/lua/trust_retail_parity.lua"
    spell_sql = "\n".join(
        [
            read_text(repo_root / "sql/mob_spell_lists.sql"),
            read_text(repo_root / "modules/custom/sql/trust_retail_parity.sql"),
        ]
    )
    skill_sql = "\n".join(
        [
            read_text(repo_root / "sql/mob_skill_lists.sql"),
            read_text(repo_root / "modules/custom/sql/trust_retail_parity.sql"),
        ]
    )
    live_path = runtime_root / "logs/trust_actions/live" / f"{player}.log"
    log_path = input_path or live_path
    report_dir = runtime_root / "reports"
    report_dir.mkdir(parents=True, exist_ok=True)
    current_epoch = (
        now_epoch
        if now_epoch is not None
        else int(dt.datetime.now(dt.timezone.utc).timestamp())
    )
    parsed = parse_evidence(log_path)
    commit = expected_commit or resolve_repo_commit(repo_root)
    report, exit_code = validate_evidence(
        parsed,
        player=player,
        expected_commit=commit,
        readiness_only=readiness_only,
        max_age_seconds=max_age_seconds,
        now_epoch=current_epoch,
        live_path=live_path,
    )
    safe_session = re.sub(r"[^A-Za-z0-9_.-]", "_", report["session"]["session_id"])
    stamp = dt.datetime.fromtimestamp(current_epoch, dt.timezone.utc).strftime(
        "%Y%m%d-%H%M%S"
    )
    report_stem = f"trust-parity-audit-{safe_session}-{stamp}"
    report_path = report_dir / f"{report_stem}.md"
    json_path = report_dir / f"{report_stem}.json"
    collision = 1
    while report_path.exists() or json_path.exists():
        collision += 1
        report_path = report_dir / f"{report_stem}-{collision}.md"
        json_path = report_dir / f"{report_stem}-{collision}.json"

    trust_scripts = sorted(trust_dir.glob("*.lua"))
    profile_keys = sorted(
        set(
            re.findall(
                r"^\s*([a-z0-9_]+)\s*=\s*\{\s*name\s*=",
                read_text(module_path),
                re.MULTILINE,
            )
        )
    )
    spell_pairs = parse_sql_pairs(spell_sql, "spell")
    skill_pairs = parse_sql_pairs(skill_sql, "skill")
    rows = descriptive_rows(parsed)
    active_trusts = sorted({row.get("trust", "") for row in rows if row.get("trust")})
    active_normalized = {normalize_name(trust) for trust in active_trusts}

    lines = ["# Mochirii Trust Evidence Audit", ""]
    for banner in report["banners"]:
        lines.append(f"> **{banner}**")
    lines += [
        "",
        f"- Status: **{report['status'].upper()}**",
        f"- Requested audit: {report['requested_audit']}",
        f"- Readiness acceptance: {report['readiness_acceptance']}",
        f"- Combat acceptance: {report['combat_acceptance']}",
        f"- Lane acceptance: {report['lane_acceptance']}",
        f"- Cross-lane parity acceptance: {report['parity_acceptance']}",
        f"- Retail acceptance: {report['retail_acceptance']}",
        f"- Extension acceptance: {report['extension_acceptance']}",
        f"- Generated: {report['generated_at']}",
        f"- Evidence mode: {report['evidence_mode']}",
        f"- Topology: {report['topology']}",
        f"- Session ID: {report['session']['session_id']}",
        f"- Server commit: {report['session']['server_commit']}",
        f"- Source log: {log_path}",
        "",
        "## Acceptance Issues",
    ]
    if report["issues"]:
        lines += ["| Code | Line | Detail |", "| --- | ---: | --- |"]
        for issue in report["issues"]:
            detail = str(issue["message"]).replace("|", "\\|")
            lines.append(f"| {issue['code']} | {issue.get('line', '')} | {detail} |")
    else:
        lines.append("- None.")

    lines += [
        "",
        "## Static And Behavioral Diagnostics",
        "",
        f"- Trust scripts: {len(trust_scripts)}",
        f"- Explicit profile keys: {len(profile_keys)}",
        f"- Generated audit profile keys: {max(0, len(trust_scripts) - len(profile_keys))}",
        f"- Parsed Trusts in source log: {len(active_trusts)}",
        "- Static and behavioral diagnostics are informational; they cannot override a failed evidence gate.",
        "",
        "## Active Trusts",
    ]
    lines.extend(
        [f"- {trust}" for trust in active_trusts]
        or ["- None found in latest live log."]
    )

    lines += [
        "",
        "## Roster Coverage",
        "| Trust Script | Profile | Active In Latest Log |",
        "| --- | --- | --- |",
    ]
    for script in trust_scripts:
        key = normalize_name(script.stem)
        lines.append(
            f"| {script.name} | {'explicit' if key in profile_keys else 'generated-audit'} | {'yes' if key in active_normalized else 'no'} |"
        )

    lines += [
        "",
        "## Current Alliance Static Preconditions",
        "| Type | Trust | List | ID | Name | Status |",
        "| --- | --- | ---: | ---: | --- | --- |",
    ]
    for trust, list_id, value_id, name in REQUIRED_SPELL_ROWS:
        lines.append(
            f"| spell | {trust} | {list_id} | {value_id} | {name} | {'ok' if (list_id, value_id) in spell_pairs else 'missing'} |"
        )
    for trust, list_id, value_id, name in REQUIRED_SKILL_ROWS:
        lines.append(
            f"| skill | {trust} | {list_id} | {value_id} | {name} | {'ok' if (list_id, value_id) in skill_pairs else 'missing'} |"
        )

    lines += ["", "## Latest Log Summary"]
    if not rows:
        lines.append("- No Trust action rows found in the latest live log.")
    else:
        by_trust = group_rows(rows, ("trust",))
        lines += [
            "| Trust | Rows | Top Events | Last HP% | Last MP% | Last Target | Last Rest | Last Rest Block |",
            "| --- | ---: | --- | ---: | ---: | --- | --- | --- |",
        ]
        for (trust,), group in sorted(by_trust.items()):
            last = group[-1]
            top = ", ".join(
                f"{name}={count}"
                for name, count in Counter(
                    row.get("event", "unknown") for row in group
                ).most_common(4)
            )
            lines.append(
                f"| {trust} | {len(group)} | {top} | {last.get('trust_hpp', '')} | {last.get('trust_mpp', '')} | {last.get('target_name', '')} | {last.get('trust_rest_mode_name', '')} | {last.get('trust_rest_block', '')} |"
            )

        lines += ["", "## Unresolved Log Names"]
        unresolved: list[tuple[str, str, str]] = []
        for row in rows:
            if re.match(r"^spell_\d+$", row.get("spell_name_resolved", "")):
                unresolved.append(
                    ("spell_name", row["spell_name_resolved"], row.get("trust", ""))
                )
            if re.match(r"^skill_\d+$", row.get("skill_name_resolved", "")):
                unresolved.append(
                    ("skill_name", row["skill_name_resolved"], row.get("trust", ""))
                )
            if row.get("message_name_resolved") == "msg_unknown":
                unresolved.append(
                    ("message_name", row["message_name_resolved"], row.get("trust", ""))
                )
        if not unresolved:
            lines.append("- None found.")
        else:
            lines += [
                "| Field | Value | Count | Trusts |",
                "| --- | --- | ---: | --- |",
            ]
            unresolved_groups: dict[tuple[str, str], list[str]] = defaultdict(list)
            for field, value, trust in unresolved:
                unresolved_groups[(field, value)].append(trust)
            for (field, value), trusts in sorted(
                unresolved_groups.items(), key=lambda item: (-len(item[1]), item[0])
            ):
                lines.append(
                    f"| {field} | {value} | {len(trusts)} | {', '.join(sorted(set(trusts)))} |"
                )

        lines += ["", "## Runtime Action Issues"]
        issues = [
            row
            for row in rows
            if re.search(
                r"invalid|interrupt|out_of_range|too_far|cannot",
                " ".join(
                    [
                        row.get("event", ""),
                        row.get("source", ""),
                        row.get("message_name_resolved", ""),
                    ]
                ),
            )
        ]
        if not issues:
            lines.append("- None found in latest log rows.")
        else:
            lines += [
                "| Trust | Event | Source | Action | Target | Context | Max Distance | Count |",
                "| --- | --- | --- | --- | --- | --- | ---: | ---: |",
            ]
            for keys, group in top_groups(
                group_rows(
                    issues,
                    ("trust", "event", "source", "action_name_resolved", "target_name"),
                ),
                60,
            ):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {context(group)} | {max_distance(group)} | {len(group)} |"
                )

        lines += ["", "## Hostile Magic Stale Target Skips"]
        stale_skips = [row for row in rows if row.get("event") == "stale_target_skip"]
        if not stale_skips:
            lines.append("- None found in latest log rows.")
        else:
            lines += [
                "| Trust | Action ID | Reason | Current Target | Packet Target | Context | Count |",
                "| --- | ---: | --- | --- | --- | --- | ---: |",
            ]
            for keys, group in top_groups(
                group_rows(
                    stale_skips,
                    (
                        "trust",
                        "action_id",
                        "skip_reason",
                        "current_battle_target_name",
                        "packet_target_name",
                    ),
                ),
                60,
            ):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {context(group)} | {len(group)} |"
                )

        lines += ["", "## TP Skill Guard Skips"]
        skips = [
            row
            for row in rows
            if row.get("tp_skill_skip_reason_name") not in (None, "", "none")
        ]
        if not skips:
            lines.append("- None found in latest log rows.")
        else:
            lines += [
                "| Trust | Reason | Skill ID | Target TargID | Current Target | Count |",
                "| --- | --- | ---: | ---: | --- | ---: |",
            ]
            for keys, group in top_groups(
                group_rows(
                    skips,
                    (
                        "trust",
                        "tp_skill_skip_reason_name",
                        "tp_skill_skip_id",
                        "tp_skill_skip_target_targid",
                        "current_battle_target_name",
                    ),
                ),
                60,
            ):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {len(group)} |"
                )

        lines += ["", "## Hostile Distance Diagnostics"]
        hostile_distances: list[tuple[str, str, str, str, str, str]] = []
        support_distances: list[tuple[str, str, str, str, str]] = []
        current_notes: list[tuple[str, str, str, str, str]] = []
        for row in rows:
            if row.get("event") == "combat_diag":
                continue
            current = to_float(row.get("distance_to_current_target"))
            packet = to_float(row.get("distance_to_packet_target"))
            if is_hostile_scope(row):
                if current is not None and current >= 20:
                    hostile_distances.append(
                        (
                            row.get("trust", ""),
                            row.get("event", ""),
                            row.get("action_name_resolved", ""),
                            row.get("current_battle_target_name", ""),
                            "current",
                            distance_bucket(current),
                        )
                    )
                if packet is not None and packet >= 20:
                    hostile_distances.append(
                        (
                            row.get("trust", ""),
                            row.get("event", ""),
                            row.get("action_name_resolved", ""),
                            row.get("packet_target_name", ""),
                            "packet",
                            distance_bucket(packet),
                        )
                    )
            elif is_support_scope(row):
                if (
                    packet is not None
                    and packet >= 20
                    and row.get("packet_target_objtype") != "4"
                ):
                    support_distances.append(
                        (
                            row.get("trust", ""),
                            row.get("event", ""),
                            row.get("action_name_resolved", ""),
                            row.get("packet_target_name", ""),
                            distance_bucket(packet),
                        )
                    )
                if current is not None and current >= 20:
                    current_notes.append(
                        (
                            row.get("trust", ""),
                            row.get("event", ""),
                            row.get("action_name_resolved", ""),
                            row.get("current_battle_target_name", ""),
                            distance_bucket(current),
                        )
                    )
        if not hostile_distances:
            lines.append(
                "- No hostile action rows at 20+ yalms from current or packet target."
            )
        else:
            lines += [
                "| Trust | Event | Action | Target | Distance Field | Bucket | Count |",
                "| --- | --- | --- | --- | --- | --- | ---: |",
            ]
            for keys, count in Counter(hostile_distances).most_common(60):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {keys[5]} | {count} |"
                )

        lines += ["", "## Support Distance Diagnostics"]
        if not support_distances:
            lines.append("- No support packet targets at 20+ yalms.")
        else:
            lines.append(
                "- Support rows use packet-target distance for party/alliance coverage. Current hostile-target distance is tracked separately and is not by itself a movement failure."
            )
            lines += [
                "| Trust | Event | Action | Packet Target | Packet Distance Bucket | Count |",
                "| --- | --- | --- | --- | --- | ---: |",
            ]
            for keys, count in Counter(support_distances).most_common(60):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {count} |"
                )

        lines += ["", "## Support Current-Target Distance Notes"]
        if not current_notes:
            lines.append(
                "- No support rows had a 20+ yalm current hostile-target context."
            )
        else:
            lines.append(
                "- These rows explain why a support action can look far from the current enemy while still correctly targeting self, party, or alliance members."
            )
            lines += [
                "| Trust | Event | Action | Current Target | Current Distance Bucket | Count |",
                "| --- | --- | --- | --- | --- | ---: |",
            ]
            for keys, count in Counter(current_notes).most_common(60):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {count} |"
                )

        lines += ["", "## Role Enmity Decisions"]
        role_rows = [
            row
            for row in rows
            if row.get("role_enmity_action_name") not in (None, "", "none")
        ]
        if not role_rows:
            lines.append("- No role-enmity decisions found in latest log rows.")
        else:
            lines += ["| Action | Trusts | Rows |", "| --- | --- | ---: |"]
            for (action,), group in top_groups(
                group_rows(role_rows, ("role_enmity_action_name",))
            ):
                lines.append(
                    f"| {action} | {', '.join(sorted({row.get('trust', '') for row in group}))} | {len(group)} |"
                )

        lines += ["", "## Support Target Anomalies"]
        support_target_anomalies = [
            row
            for row in rows
            if is_support_result_scope(row)
            and row.get("packet_target_objtype") not in ("", "1", "32", "nil", "none")
        ]
        if not support_target_anomalies:
            lines.append("- None found in latest log rows.")
        else:
            lines += [
                "| Trust | Source | Action | Packet Target | ObjType | Context | Count |",
                "| --- | --- | --- | --- | ---: | --- | ---: |",
            ]
            for keys, group in top_groups(
                group_rows(
                    support_target_anomalies,
                    (
                        "trust",
                        "source",
                        "action_name_resolved",
                        "packet_target_name",
                        "packet_target_objtype",
                    ),
                ),
                60,
            ):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {context(group)} | {len(group)} |"
                )

        lines += ["", "## Alliance Support Scope"]
        support_rows = [
            row
            for row in rows
            if (to_int(row.get("target_count")) or 0) > 1
            or (to_int(row.get("result_count")) or 0) > 1
        ]
        if not support_rows:
            lines.append("- No multi-target action packets/results found.")
        else:
            lines += [
                "| Trust | Source | Category | Action | Max Targets | Max Results | Rows With Fewer Results Than Targets | Count |",
                "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |",
            ]
            for keys, group in top_groups(
                group_rows(
                    support_rows,
                    ("trust", "source", "action_category_name", "action_name_resolved"),
                ),
                60,
            ):
                target_counts = [
                    to_int(row.get("target_count"))
                    for row in group
                    if to_int(row.get("target_count")) is not None
                ]
                result_counts = [
                    to_int(row.get("result_count"))
                    for row in group
                    if to_int(row.get("result_count")) is not None
                ]
                missed = sum(
                    1
                    for row in group
                    if to_int(row.get("target_count")) is not None
                    and to_int(row.get("result_count")) is not None
                    and (to_int(row.get("result_count")) or 0)
                    < (to_int(row.get("target_count")) or 0)
                )
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {max(target_counts) if target_counts else ''} | {max(result_counts) if result_counts else ''} | {missed} | {len(group)} |"
                )

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
            lines += [
                "| Scope | Effect | Rows | Trusts Reporting |",
                "| --- | --- | ---: | --- |",
            ]
            for (scope, effect), trusts in sorted(
                effects.items(), key=lambda item: (-len(item[1]), item[0])
            )[:40]:
                lines.append(
                    f"| {scope} | {effect} | {len(trusts)} | {', '.join(sorted(set(trusts)))} |"
                )

        lines += [
            "",
            "## Latest Active Effects By Entity",
            "| Scope | Entity | Latest Effects |",
            "| --- | --- | --- |",
        ]
        latest_master = next(
            (
                row
                for row in reversed(rows)
                if row.get("master_statuses") and row.get("master_statuses") != "none"
            ),
            None,
        )
        lines.append(
            f"| master | {player} | {format_status(latest_master.get('master_statuses', '') if latest_master else '')} |"
        )
        for (trust,), group in sorted(by_trust.items()):
            latest = next(
                (row for row in reversed(group) if row.get("trust_statuses")), None
            )
            lines.append(
                f"| trust | {trust} | {format_status(latest.get('trust_statuses', '') if latest else '')} |"
            )
        target_groups = group_rows(
            [
                row
                for row in rows
                if row.get("target_name")
                and row.get("target_name") != "none"
                and row.get("target_statuses")
            ],
            ("target_name",),
        )
        for (target,), group in sorted(target_groups.items()):
            lines.append(
                f"| target | {target} | {format_status(group[-1].get('target_statuses', ''))} |"
            )

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
                early.append(
                    (
                        row.get("trust", ""),
                        row.get("spell_name_resolved", ""),
                        row.get("target_name", ""),
                        effect,
                        remaining,
                        duration,
                        window,
                    )
                )
        if not early:
            lines.append("- None found above the duration-based refresh windows.")
        else:
            lines += [
                "| Trust | Spell | Target | Effect | Remaining Seconds | Duration Seconds | Refresh Window Seconds | Count |",
                "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |",
            ]
            for keys, count in Counter(early).most_common(40):
                lines.append(
                    f"| {keys[0]} | {keys[1]} | {keys[2]} | {keys[3]} | {keys[4]} | {keys[5]} | {keys[6]} | {count} |"
                )

    lines += [
        "",
        "## Interpretation",
        "- Evidence acceptance proves only that the requested lane produced a complete, isolated corpus.",
        "- Readiness-only success is noncombat and is never a Trust parity result.",
        "- Static diagnostics and legacy rows remain descriptive and cannot satisfy an acceptance gate.",
    ]
    report["artifacts"] = {
        "markdown": str(report_path),
        "json": str(json_path),
    }
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    json_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return AuditResult(
        report=report,
        rows=rows,
        exit_code=exit_code,
        markdown_path=report_path,
        json_path=json_path,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate and report one Mochirii Trust evidence session."
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--runtime-root", type=Path, default=Path("/home/xartyzx/projects/FFXI-Runtime")
    )
    parser.add_argument("--player", default="Twills")
    parser.add_argument(
        "--input",
        type=Path,
        help="Explicit live or archived evidence log (defaults to the player's live log).",
    )
    parser.add_argument(
        "--readiness-only",
        action="store_true",
        help="Validate noncombat authorization/topology/roster/logger readiness only.",
    )
    parser.add_argument(
        "--max-age-seconds",
        type=int,
        default=1800,
        help="Maximum age of the newest evidence row (default: 1800).",
    )
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,31}", args.player):
        parser.error("--player contains unsafe characters")
    if args.max_age_seconds <= 0:
        parser.error("--max-age-seconds must be positive")

    try:
        result = generate_report(
            args.repo_root.resolve(),
            args.runtime_root.resolve(),
            args.player,
            input_path=args.input.resolve() if args.input else None,
            readiness_only=args.readiness_only,
            max_age_seconds=args.max_age_seconds,
        )
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"trust parity audit invocation failed: {exc}", file=sys.stderr)
        return 2

    print(
        json.dumps(
            {
                "status": result.report["status"],
                "exit_code": result.exit_code,
                "combat_acceptance": result.report["combat_acceptance"],
                "markdown": str(result.markdown_path),
                "json": str(result.json_path),
            },
            sort_keys=True,
        )
    )
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
