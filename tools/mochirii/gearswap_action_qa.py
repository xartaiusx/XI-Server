#!/usr/bin/env python3
"""Static QA for Twills RDM/SCH GearSwap coverage.

The harness executes Twills.lua through LuaJIT with GearSwap-compatible stubs.
It models Windower GearSwap set_combine/equip precedence, treats GearSwap's
`empty` sentinel as a valid intentional slot value, ignores overlay-only sets,
and validates the final 16-slot equipment table for every generated RDM/SCH
spell, job ability, weapon skill, and utility command.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

SLOTS = [
    "main",
    "sub",
    "range",
    "ammo",
    "head",
    "body",
    "hands",
    "legs",
    "feet",
    "neck",
    "waist",
    "left_ear",
    "right_ear",
    "left_ring",
    "right_ring",
    "back",
]

EMPTY_SENTINEL = "__GEARSWAP_EMPTY_SLOT__"
MODEL_SENSITIVE_SLOTS = {"main", "sub", "head", "body", "hands", "legs", "feet"}
MODEL_INFO_SLOTS = {"range", "ammo"}
EQUIPMENT_SLOT_TO_GEARSWAP = {
    1: {"main"},
    2: {"sub"},
    3: {"main", "sub"},
    8: {"range", "ammo"},
    16: {"head"},
    32: {"body"},
    64: {"hands"},
    128: {"legs"},
    256: {"feet"},
}
RDM_JOB_ID = 5
SCH_JOB_ID = 20
RDM_LEVEL = 99
SCH_LEVEL = 59

SKILL_NAMES = {
    32: "Divine Magic",
    33: "Healing Magic",
    34: "Enhancing Magic",
    35: "Enfeebling Magic",
    36: "Elemental Magic",
    37: "Dark Magic",
    38: "Summoning Magic",
    39: "Ninjutsu",
    40: "Singing",
    43: "Blue Magic",
    44: "Geomancy",
}

ELEMENT_NAMES = {
    0: "None",
    1: "Fire",
    2: "Ice",
    3: "Wind",
    4: "Earth",
    5: "Thunder",
    6: "Water",
    7: "Light",
    8: "Dark",
}

SQL_CONSTANTS = {
    "@ELEMENT_NONE": 0,
    "@ELEMENT_FIRE": 1,
    "@ELEMENT_ICE": 2,
    "@ELEMENT_WIND": 3,
    "@ELEMENT_EARTH": 4,
    "@ELEMENT_THUNDER": 5,
    "@ELEMENT_WATER": 6,
    "@ELEMENT_LIGHT": 7,
    "@ELEMENT_DARK": 8,
    "@SKILL_NONE": 0,
    "@SKILL_DIVINE": 32,
    "@SKILL_HEALING": 33,
    "@SKILL_ENHANCING": 34,
    "@SKILL_ENFEEBLING": 35,
    "@SKILL_ELEMENTAL": 36,
    "@SKILL_DARK": 37,
    "@SKILL_SUMMONING": 38,
    "@SKILL_NINJUTSU": 39,
    "@SKILL_SINGING": 40,
    "@SKILL_BLUE": 43,
    "@SKILL_GEOMANCY": 44,
}

ROMAN = {
    "i": "I",
    "ii": "II",
    "iii": "III",
    "iv": "IV",
    "v": "V",
    "vi": "VI",
    "vii": "VII",
    "viii": "VIII",
    "ix": "IX",
    "x": "X",
}

SPECIAL_ACTION_NAMES = {
    "addendum_white": "Addendum: White",
    "addendum_black": "Addendum: Black",
    "light_arts": "Light Arts",
    "dark_arts": "Dark Arts",
    "chainspell": "Chainspell",
    "convert": "Convert",
    "composure": "Composure",
    "saboteur": "Saboteur",
    "spontaneity": "Spontaneity",
    "stymie": "Stymie",
    "sublimation": "Sublimation",
    "penury": "Penury",
    "celerity": "Celerity",
    "accession": "Accession",
    "rapture": "Rapture",
    "parsimony": "Parsimony",
    "alacrity": "Alacrity",
    "manifestation": "Manifestation",
    "ebullience": "Ebullience",
}

UTILITY_COMMANDS = [
    "idle",
    "healer",
    "buffer",
    "debuffer",
    "caster",
    "melee",
    "cycle",
    "dt",
    "refresh",
    "enf acc",
    "enf mnd",
    "enf int",
    "enf potency",
    "nuke free",
    "nuke burst",
    "burst",
    "free",
    "weapon daybreak",
    "weapon crocea",
    "weapon naegling",
    "weapon maxentius",
    "weapon bunzi",
    "weapon tauret",
    "validate",
    "status",
    "gearscore",
    "reset",
    "qa all",
    "qa status",
    "qa snapshot",
    "qa visual",
    "qa family",
    "qa families",
    "qa actions",
]

NO_EQUIP_COMMANDS = {
    "validate",
    "status",
    "gearscore",
    "qa all",
    "qa status",
    "qa snapshot",
    "qa visual",
    "qa family",
    "qa families",
    "qa actions",
}

PLAYER_MAGIC_SKILLS = {
    "Divine Magic",
    "Healing Magic",
    "Enhancing Magic",
    "Enfeebling Magic",
    "Elemental Magic",
    "Dark Magic",
}


@dataclass(frozen=True)
class Action:
    category: str
    name: str
    action_type: str
    skill: str = ""
    element: str = "None"
    target_type: str = "SELF"
    no_equip_expected: bool = False
    source: str = ""


def split_sql_values(row: str) -> list[str]:
    values: list[str] = []
    current: list[str] = []
    in_quote = False
    escape = False
    for char in row:
        if in_quote:
            current.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == "'":
                in_quote = False
            continue
        if char == "'":
            in_quote = True
            current.append(char)
        elif char == ",":
            values.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    values.append("".join(current).strip())
    return values


def iter_insert_rows(sql_path: Path, table: str) -> Iterable[list[str]]:
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    marker = f"INSERT INTO `{table}` VALUES"
    position = 0
    while True:
        start = text.find(marker, position)
        if start == -1:
            return
        start = text.find("VALUES", start) + len("VALUES")
        end = text.find(";", start)
        if end == -1:
            return
        chunk = text[start:end]
        position = end + 1
        depth = 0
        in_quote = False
        escape = False
        row_start: int | None = None
        for index, char in enumerate(chunk):
            if in_quote:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == "'":
                    in_quote = False
                continue
            if char == "'":
                in_quote = True
            elif char == "(":
                if depth == 0:
                    row_start = index + 1
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0 and row_start is not None:
                    yield split_sql_values(chunk[row_start:index])
                    row_start = None


def unquote_sql(token: str) -> str:
    token = token.strip()
    if token.upper() == "NULL":
        return ""
    if len(token) >= 2 and token[0] == "'" and token[-1] == "'":
        return token[1:-1].replace("\\'", "'").replace("''", "'")
    return token


def int_token(token: str) -> int:
    token = token.strip()
    if token.upper() == "NULL" or token == "":
        return 0
    if token in SQL_CONSTANTS:
        return SQL_CONSTANTS[token]
    return int(token)


def job_level(jobs_hex: str, job_id: int) -> int:
    jobs_hex = jobs_hex.strip()
    if not jobs_hex.startswith("0x"):
        return 0
    data = bytes.fromhex(jobs_hex[2:])
    index = job_id - 1
    if index < 0 or index >= len(data):
        return 0
    return data[index]


def title_token(token: str) -> str:
    lowered = token.lower()
    if lowered in ROMAN:
        return ROMAN[lowered]
    if len(token) <= 3 and token.isalpha() and token.isupper():
        return token
    return token[:1].upper() + token[1:].lower()


def ffxi_name(raw: str) -> str:
    if raw in SPECIAL_ACTION_NAMES:
        return SPECIAL_ACTION_NAMES[raw]
    raw = raw.replace("_", " ")
    words = []
    for word in raw.split(" "):
        if "-" in word:
            words.append("-".join(title_token(part) for part in word.split("-")))
        else:
            words.append(title_token(word))
    return " ".join(words)


def normalize_item_name(name: str) -> str:
    normalized = name.lower().replace("_", " ")
    normalized = normalized.replace("'", "").replace(".", "")
    return " ".join(normalized.split())


def apply_custom_model_updates(
    repo_root: Path, equipment_rows: dict[int, dict[str, object]]
) -> None:
    custom_sql_root = repo_root / "modules" / "custom" / "sql"
    if not custom_sql_root.exists():
        return
    pattern = re.compile(
        r"UPDATE\s+`?item_equipment`?\s+SET\s+`?MId`?\s*=\s*(\d+)\s+WHERE\s+`?name`?\s+IN\s*\((.*?)\)",
        re.IGNORECASE | re.DOTALL,
    )
    for sql_path in sorted(custom_sql_root.glob("*.sql")):
        text = sql_path.read_text(encoding="utf-8", errors="ignore")
        for match in pattern.finditer(text):
            model_id = int(match.group(1))
            names = {unquote_sql(token) for token in split_sql_values(match.group(2))}
            for row in equipment_rows.values():
                if row["name"] in names and int(row["model_id"]) == 0:
                    row["model_id"] = model_id
                    row["model_source"] = str(sql_path.relative_to(repo_root))


def build_item_visual_lookup(repo_root: Path) -> dict[str, dict[str, object]]:
    basic_rows: dict[int, dict[str, str]] = {}
    for row in iter_insert_rows(repo_root / "sql" / "item_basic.sql", "item_basic"):
        if len(row) < 4:
            continue
        item_id = int_token(row[0])
        basic_rows[item_id] = {
            "name": unquote_sql(row[2]),
            "sortname": unquote_sql(row[3]),
        }

    equipment_rows: dict[int, dict[str, object]] = {}
    for row in iter_insert_rows(
        repo_root / "sql" / "item_equipment.sql", "item_equipment"
    ):
        if len(row) < 9:
            continue
        item_id = int_token(row[0])
        equipment_rows[item_id] = {
            "item_id": item_id,
            "name": unquote_sql(row[1]),
            "model_id": int_token(row[5]),
            "equipment_slot": int_token(row[8]),
            "model_source": "sql/item_equipment.sql",
        }

    apply_custom_model_updates(repo_root, equipment_rows)

    lookup: dict[str, dict[str, object]] = {}
    for item_id, equipment in equipment_rows.items():
        basic = basic_rows.get(item_id, {})
        names = {
            str(equipment["name"]),
            basic.get("name", ""),
            basic.get("sortname", ""),
        }
        payload = {
            "item_id": item_id,
            "name": basic.get("name") or equipment["name"],
            "sortname": basic.get("sortname", ""),
            "model_id": equipment["model_id"],
            "equipment_slot": equipment["equipment_slot"],
            "model_source": equipment["model_source"],
        }
        for name in names:
            if name:
                lookup[normalize_item_name(name)] = payload
    return lookup


def visual_model_entries(
    rows: list[dict[str, object]], item_lookup: dict[str, dict[str, object]]
) -> dict[str, dict[str, object]]:
    entries: dict[str, dict[str, object]] = {}
    for row in rows:
        if row.get("status") != "PASS":
            continue
        slots = row.get("slots") or {}
        if not isinstance(slots, dict):
            continue
        for slot, raw_value in slots.items():
            if slot not in MODEL_SENSITIVE_SLOTS:
                continue
            value = str(raw_value or "")
            if not value or value == "__empty__":
                continue
            item = item_lookup.get(normalize_item_name(value))
            if not item:
                continue
            equipment_slot = int(item["equipment_slot"])
            valid_slots = EQUIPMENT_SLOT_TO_GEARSWAP.get(equipment_slot, set())
            if slot not in valid_slots:
                continue
            entries[value] = item
    return entries


def lua_string(value: object) -> str:
    text = str(value)
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_visual_manifest(
    manifest_path: Path,
    entries: dict[str, dict[str, object]],
    repo_root: Path,
) -> None:
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "-- Generated by tools/mochirii/gearswap_action_qa.py.",
        "-- Do not edit by hand; regenerate after Twills GearSwap visible gear changes.",
        "return {",
        "    schema_version = 1,",
        '    generated_by = "tools/mochirii/gearswap_action_qa.py",',
        "    items = {",
    ]
    for item_name in sorted(entries):
        item = entries[item_name]
        lines.append(
            "        ["
            + lua_string(item_name)
            + "] = { item_id = "
            + str(item["item_id"])
            + ", model_id = "
            + str(item["model_id"])
            + ", equipment_slot = "
            + str(item["equipment_slot"])
            + ", model_source = "
            + lua_string(item["model_source"])
            + " },"
        )
    lines.extend(["    },", "}", ""])
    manifest_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def visual_model_findings(
    rows: list[dict[str, object]], item_lookup: dict[str, dict[str, object]]
) -> tuple[list[dict[str, object]], list[dict[str, object]], int]:
    failures: list[dict[str, object]] = []
    info: list[dict[str, object]] = []
    checked = 0
    for row in rows:
        if row.get("status") != "PASS":
            continue
        slots = row.get("slots") or {}
        if not isinstance(slots, dict):
            continue
        for slot, raw_value in slots.items():
            value = str(raw_value or "")
            if not value or value == "__empty__":
                continue
            item = item_lookup.get(normalize_item_name(value))
            if not item:
                if slot in MODEL_SENSITIVE_SLOTS:
                    failures.append(
                        {
                            "kind": "VISUAL_MODEL",
                            "category": "visible_model",
                            "name": value,
                            "phase": f"{row.get('kind')}:{row.get('phase')}:{slot}",
                            "status": "FAIL",
                            "missing_slots": [],
                            "error": "visible slot item is not resolvable in local item_basic/item_equipment data",
                        }
                    )
                continue
            equipment_slot = int(item["equipment_slot"])
            valid_slots = EQUIPMENT_SLOT_TO_GEARSWAP.get(equipment_slot, set())
            if slot not in valid_slots:
                continue
            checked += 1
            model_id = int(item["model_id"])
            finding = {
                "kind": "VISUAL_MODEL",
                "category": "visible_model",
                "name": value,
                "phase": f"{row.get('kind')}:{row.get('phase')}:{slot}",
                "status": (
                    "FAIL"
                    if slot in MODEL_SENSITIVE_SLOTS and model_id == 0
                    else "INFO"
                ),
                "missing_slots": [],
                "error": f"itemId={item['item_id']} MId={model_id} source={item['model_source']}",
            }
            if slot in MODEL_SENSITIVE_SLOTS and model_id == 0:
                failures.append(finding)
            elif slot in MODEL_INFO_SLOTS and model_id == 0:
                info.append(finding)
    return failures, info, checked


def spell_target_type(skill: str, valid_targets: int) -> str:
    if skill in {"Enfeebling Magic", "Elemental Magic", "Dark Magic", "Divine Magic"}:
        return "MONSTER"
    if valid_targets & 1:
        return "SELF"
    return "PLAYER"


def build_spell_actions(repo_root: Path) -> list[Action]:
    actions: list[Action] = []
    for row in iter_insert_rows(repo_root / "sql" / "spell_list.sql", "spell_list"):
        if len(row) < 24:
            continue
        name = unquote_sql(row[1])
        jobs = row[2]
        skill = SKILL_NAMES.get(int_token(row[8]), "Magic")
        element = ELEMENT_NAMES.get(int_token(row[5]), "None")
        valid_targets = int_token(row[7])
        rdm_level = job_level(jobs, RDM_JOB_ID)
        sch_level = job_level(jobs, SCH_JOB_ID)
        usable = (0 < rdm_level <= RDM_LEVEL) or (0 < sch_level <= SCH_LEVEL)
        if not usable:
            continue
        english = ffxi_name(name)
        if english.startswith("Trust: ") or skill not in PLAYER_MAGIC_SKILLS:
            continue
        actions.append(
            Action(
                category="spell",
                name=english,
                action_type="Magic",
                skill=skill,
                element=element,
                target_type=spell_target_type(skill, valid_targets),
                source="sql/spell_list.sql",
            )
        )
    return sorted(
        {(a.name, a.skill): a for a in actions}.values(),
        key=lambda a: (a.skill, a.name),
    )


def build_ability_actions(repo_root: Path) -> list[Action]:
    actions: list[Action] = []
    for row in iter_insert_rows(repo_root / "sql" / "abilities.sql", "abilities"):
        if len(row) < 5:
            continue
        name = unquote_sql(row[1])
        job = int_token(row[2])
        level = int_token(row[3])
        usable = (job == RDM_JOB_ID and level <= RDM_LEVEL) or (
            job == SCH_JOB_ID and level <= SCH_LEVEL
        )
        if not usable:
            continue
        actions.append(
            Action(
                category="job_ability",
                name=ffxi_name(name),
                action_type="JobAbility",
                skill="Ability",
                target_type="SELF",
                source="sql/abilities.sql",
            )
        )
    return sorted({a.name: a for a in actions}.values(), key=lambda a: a.name)


def build_weapon_skill_actions(repo_root: Path) -> list[Action]:
    actions: list[Action] = []
    for row in iter_insert_rows(
        repo_root / "sql" / "weapon_skills.sql", "weapon_skills"
    ):
        if len(row) < 16:
            continue
        jobs = row[2]
        if job_level(jobs, RDM_JOB_ID) <= 0:
            continue
        actions.append(
            Action(
                category="weapon_skill",
                name=ffxi_name(unquote_sql(row[1])),
                action_type="WeaponSkill",
                skill="WeaponSkill",
                element=ELEMENT_NAMES.get(int_token(row[5]), "None"),
                target_type="MONSTER",
                source="sql/weapon_skills.sql",
            )
        )
    return sorted({a.name: a for a in actions}.values(), key=lambda a: a.name)


def build_utility_actions() -> list[Action]:
    return [
        Action(
            category="command",
            name=command,
            action_type="Command",
            no_equip_expected=command in NO_EQUIP_COMMANDS,
            source="Twills.lua self_command",
        )
        for command in UTILITY_COMMANDS
    ]


def lua_quote(value: str) -> str:
    return json.dumps(value)


def lua_action_table(actions: list[Action]) -> str:
    lines = ["local action_specs = {"]
    for action in actions:
        lines.append(
            "    {category=%s, name=%s, action_type=%s, skill=%s, element=%s, target_type=%s, no_equip_expected=%s},"
            % (
                lua_quote(action.category),
                lua_quote(action.name),
                lua_quote(action.action_type),
                lua_quote(action.skill),
                lua_quote(action.element),
                lua_quote(action.target_type),
                "true" if action.no_equip_expected else "false",
            )
        )
    lines.append("}")
    return "\n".join(lines)


def lua_bis_table(bis_specs: list[dict[str, str]]) -> str:
    lines = ["local bis_specs = {"]
    for spec in bis_specs:
        lines.append(
            "    {family=%s, label=%s, path=%s},"
            % (
                lua_quote(spec.get("family", "")),
                lua_quote(spec.get("label", "")),
                lua_quote(spec.get("path", "")),
            )
        )
    lines.append("}")
    return "\n".join(lines)


def build_lua_runner(
    gearswap_path: Path, actions: list[Action], bis_specs: list[dict[str, str]]
) -> str:
    slots_lua = ", ".join(lua_quote(slot) for slot in SLOTS)
    addon_path = str(gearswap_path.parent.parent).replace("\\", "/") + "/"
    return f"""
local gearswap_path = {lua_quote(str(gearswap_path))}
local gearswap_addon_path = {lua_quote(addon_path)}
local slot_order = {{ {slots_lua} }}
empty = {lua_quote(EMPTY_SENTINEL)}
world = {{ day_element = 'Light', weather_element = 'None' }}
player = {{ name = 'Twills', status = 'Idle', main_job = 'RDM', sub_job = 'SCH', main_job_level = 99, sub_job_level = 59 }}
buffactive = {{}}
windower = {{
    addon_path = gearswap_addon_path,
    ffxi = {{
        get_mob_by_target = function(_target)
            return {{ distance = 81 }}
        end,
    }},
    add_to_chat = function(_color, _message) end,
    send_command = function(_command) end,
}}
function add_to_chat(_color, _message) end
function send_command(_command) end

local current_equipped = nil
local last_equipped = nil

local function copy_table(source)
    local result = {{}}
    if type(source) ~= 'table' then
        return result
    end
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

function set_combine(...)
    local result = {{}}
    for index = 1, select('#', ...) do
        local set = select(index, ...)
        if type(set) == 'table' then
            for key, value in pairs(set) do
                result[key] = value
            end
        end
    end
    return result
end

function equip(...)
    local combined = set_combine(...)
    current_equipped = set_combine(current_equipped or {{}}, combined)
    last_equipped = copy_table(current_equipped)
end

local function clean(value)
    if value == nil then
        return ''
    end
    if value == empty then
        return '__empty__'
    end
    if type(value) == 'table' then
        return value.name or value.en or value.english or '<table>'
    end
    return tostring(value):gsub('[\\r\\n\\t|]', ' ')
end

local function missing_slots(set)
    local missing = {{}}
    if type(set) ~= 'table' then
        for _, slot in ipairs(slot_order) do
            missing[#missing + 1] = slot
        end
        return missing
    end
    for _, slot in ipairs(slot_order) do
        if set[slot] == nil or set[slot] == '' then
            missing[#missing + 1] = slot
        end
    end
    return missing
end

local function slot_payload(set)
    local pieces = {{}}
    if type(set) == 'table' then
        for _, slot in ipairs(slot_order) do
            pieces[#pieces + 1] = slot .. '=' .. clean(set[slot])
        end
    end
    return table.concat(pieces, '|')
end

local function emit(kind, category, name, phase, set, error_message, no_equip_expected)
    local missing = missing_slots(set)
    local status = (#missing == 0 or no_equip_expected) and 'PASS' or 'FAIL'
    if error_message and error_message ~= '' then
        status = 'ERROR'
    end
    print(table.concat({{
        'QA', kind, category or '', name or '', phase or '', status,
        table.concat(missing, ','), error_message or '', tostring(no_equip_expected or false), slot_payload(set),
    }}, '\t'))
end

local function safe_call(kind, category, name, phase, func, spell, no_equip_expected)
    current_equipped = nil
    last_equipped = nil
    local ok, err = pcall(func, spell)
    if ok then
        emit(kind, category, name, phase, last_equipped, '', no_equip_expected and last_equipped == nil)
    else
        emit(kind, category, name, phase, last_equipped, tostring(err), false)
    end
end

local function make_spell(spec)
    return {{
        english = spec.name,
        name = spec.name,
        type = spec.action_type,
        action_type = spec.action_type == 'Magic' and 'Magic' or spec.action_type,
        skill = spec.skill,
        element = spec.element,
        target = {{ name = spec.target_type == 'SELF' and 'Twills' or 'QA Target', type = spec.target_type, distance = 9, isallymember = spec.target_type ~= 'MONSTER' }},
    }}
end

dofile(gearswap_path)
get_sets()

{lua_action_table(actions)}

{lua_bis_table(bis_specs)}

local function run_action(spec)
    local spell = make_spell(spec)
    if spec.action_type == 'Magic' then
        safe_call('ACTION', spec.category, spec.name, 'precast', precast, spell, false)
        safe_call('ACTION', spec.category, spec.name, 'midcast', midcast, spell, false)
        safe_call('ACTION', spec.category, spec.name, 'aftercast', aftercast, spell, false)
    elseif spec.action_type == 'JobAbility' then
        safe_call('ACTION', spec.category, spec.name, 'precast', precast, spell, false)
        safe_call('ACTION', spec.category, spec.name, 'aftercast', aftercast, spell, false)
    elseif spec.action_type == 'WeaponSkill' then
        safe_call('ACTION', spec.category, spec.name, 'precast', precast, spell, false)
        safe_call('ACTION', spec.category, spec.name, 'aftercast', aftercast, spell, false)
    elseif spec.action_type == 'Command' then
        safe_call('ACTION', spec.category, spec.name, 'self_command', function() self_command(spec.name) end, spell, spec.no_equip_expected)
    end
end

for _, spec in ipairs(action_specs) do
    run_action(spec)
end

local function resolve_bis_path(path)
    local chunk, compile_error = loadstring('return ' .. path)
    if not chunk then
        return nil, compile_error
    end
    local ok, value = pcall(chunk)
    if not ok then
        return nil, value
    end
    return value, ''
end

for _, spec in ipairs(bis_specs) do
    local value, err = resolve_bis_path(spec.path)
    emit('BIS', spec.family, spec.path, 'matrix', value, err, false)
end

local function skip_set(path)
    return path:match('^sets%%.weapons') ~= nil or
        path:match('^sets%%.utility') ~= nil or
        path:match('^sets%%.gearscore') ~= nil or
        path:match('^sets%%.role') ~= nil
end

local function has_equipment_shape(value)
    if type(value) ~= 'table' then
        return false
    end
    local count = 0
    for _, slot in ipairs(slot_order) do
        if value[slot] ~= nil then
            count = count + 1
        end
    end
    return count >= 8
end

local visited = {{}}
local function walk(path, value)
    if type(value) ~= 'table' or visited[value] then
        return
    end
    visited[value] = true
    if not skip_set(path) and has_equipment_shape(value) then
        emit('SET', 'set', path, 'defined', value, '', false)
    end
    for key, child in pairs(value) do
        if type(child) == 'table' then
            walk(path .. '.' .. tostring(key), child)
        end
    end
end

walk('sets', sets)
"""


def parse_lua_output(output: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line in output.splitlines():
        if not line.startswith("QA\t"):
            continue
        parts = line.split("\t")
        while len(parts) < 10:
            parts.append("")
        _, kind, category, name, phase, status, missing, error, no_equip, slots = parts[
            :10
        ]
        slot_values: dict[str, str] = {}
        if slots:
            for piece in slots.split("|"):
                if "=" in piece:
                    slot, value = piece.split("=", 1)
                    slot_values[slot] = value
        rows.append(
            {
                "kind": kind,
                "category": category,
                "name": name,
                "phase": phase,
                "status": status,
                "missing_slots": [item for item in missing.split(",") if item],
                "error": error,
                "no_equip_expected": no_equip == "true",
                "slots": slot_values,
            }
        )
    return rows


def load_audit(audit_path: Path | None) -> dict[str, object]:
    if not audit_path or not audit_path.exists():
        return {}
    return json.loads(audit_path.read_text(encoding="utf-8"))


def collect_items(rows: list[dict[str, object]]) -> set[str]:
    items: set[str] = set()
    for row in rows:
        slots = row.get("slots") or {}
        if not isinstance(slots, dict):
            continue
        for value in slots.values():
            if value and value != "__empty__":
                items.add(str(value))
    return items


def write_outputs(output_root: Path, report: dict[str, object]) -> tuple[Path, Path]:
    output_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    json_path = output_root / f"twills-gearswap-action-qa-{stamp}.json"
    md_path = output_root / f"twills-gearswap-action-qa-{stamp}.md"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    summary = report["summary"]
    failures = report["failures"]
    lines = [
        "# Twills RDM/SCH GearSwap Action QA",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Summary",
        "",
    ]
    for key in sorted(summary):
        lines.append(f"- {key}: {summary[key]}")
    lines.extend(["", "## Failures", ""])
    if failures:
        for failure in failures[:100]:
            lines.append(
                f"- {failure['kind']} {failure['category']} `{failure['name']}` {failure['phase']}: "
                f"{failure['status']} missing={','.join(failure['missing_slots']) or '-'} error={failure['error'] or '-'}"
            )
        if len(failures) > 100:
            lines.append(
                f"- ... {len(failures) - 100} more failures omitted from markdown; see JSON."
            )
    else:
        lines.append("- None")
    lines.extend(
        [
            "",
            "## Evidence Rules",
            "",
            "- `range=__empty__` is accepted as an intentional GearSwap empty ranged slot.",
            "- `sets.weapons.*`, `sets.utility.*`, `sets.role.*`, and `sets.gearscore.*` are overlays/metadata and are not final action sets.",
            "- Every action row is produced by executing Twills.lua with GearSwap-compatible `set_combine` and `equip` stubs.",
            "- Visible slots (`main`, `sub`, `head`, `body`, `hands`, `legs`, `feet`) fail when their local item model id is `0`.",
            "",
        ]
    )
    md_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Twills RDM/SCH GearSwap action coverage."
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--gearswap", type=Path, default=None)
    parser.add_argument(
        "--audit-json",
        type=Path,
        default=Path(
            "/home/xartyzx/projects/FFXI-Runtime/audits/twills-full-state-latest.json"
        ),
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("/home/xartyzx/projects/FFXI-Runtime/logs/gearswap_qa"),
    )
    parser.add_argument("--bis-matrix", type=Path, default=None)
    parser.add_argument("--write-visual-manifest", type=Path, default=None)
    parser.add_argument("--no-write-report", action="store_true")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    gearswap_path = (
        args.gearswap
        or repo_root
        / "restore"
        / "windower-golden-state"
        / "addons"
        / "GearSwap"
        / "data"
        / "Twills.lua"
    )
    if not gearswap_path.exists():
        raise SystemExit(f"GearSwap file not found: {gearswap_path}")

    actions = (
        build_spell_actions(repo_root)
        + build_ability_actions(repo_root)
        + build_weapon_skill_actions(repo_root)
        + build_utility_actions()
    )
    bis_matrix_path = (
        args.bis_matrix
        or repo_root / "restore" / "manifests" / "twills-rdm-sch-bis-matrix.json"
    )
    bis_matrix = (
        json.loads(bis_matrix_path.read_text(encoding="utf-8"))
        if bis_matrix_path.exists()
        else {"families": []}
    )
    bis_specs = []
    for family in bis_matrix.get("families", []):
        for set_path in family.get("setPaths", []):
            bis_specs.append(
                {
                    "family": family.get("family", ""),
                    "label": family.get("label", ""),
                    "path": set_path,
                }
            )
    runner = build_lua_runner(gearswap_path.resolve(), actions, bis_specs)
    with tempfile.NamedTemporaryFile(
        "w", suffix=".lua", encoding="utf-8", delete=False
    ) as handle:
        handle.write(runner)
        runner_path = Path(handle.name)

    try:
        proc = subprocess.run(
            ["luajit", str(runner_path)], check=False, text=True, capture_output=True
        )
    finally:
        runner_path.unlink(missing_ok=True)

    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)

    rows = parse_lua_output(proc.stdout)
    audit = load_audit(args.audit_json)
    gearswap_audit = audit.get("gearswap", {}) if isinstance(audit, dict) else {}
    present_inventory = (
        set(gearswap_audit.get("present", []))
        if isinstance(gearswap_audit, dict)
        else set()
    )
    missing_from_audit = (
        set(gearswap_audit.get("missing_from_inventory", []))
        if isinstance(gearswap_audit, dict)
        else set()
    )
    unknown_from_audit = (
        set(gearswap_audit.get("unknown_in_resources", []))
        if isinstance(gearswap_audit, dict)
        else set()
    )
    used_items = collect_items(rows)
    inventory_missing = sorted(
        item
        for item in used_items
        if present_inventory and item not in present_inventory
    )
    item_visual_lookup = build_item_visual_lookup(repo_root)
    visual_manifest_entries = visual_model_entries(rows, item_visual_lookup)
    if args.write_visual_manifest:
        write_visual_manifest(
            args.write_visual_manifest.resolve(), visual_manifest_entries, repo_root
        )
    visual_failures, visual_info, visual_checked = visual_model_findings(
        rows, item_visual_lookup
    )
    failures: list[dict[str, object]] = [row for row in rows if row["status"] != "PASS"]
    failures.extend(visual_failures)
    failures.extend(
        {
            "kind": "INVENTORY",
            "category": "item",
            "name": item,
            "phase": "audit",
            "status": "FAIL",
            "missing_slots": [],
            "error": "item not present in latest Twills GearSwap audit inventory evidence",
        }
        for item in inventory_missing
    )

    action_rows = [row for row in rows if row["kind"] == "ACTION"]
    set_rows = [row for row in rows if row["kind"] == "SET"]
    bis_rows = [row for row in rows if row["kind"] == "BIS"]
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "gearswap_path": str(gearswap_path),
        "audit_path": str(args.audit_json) if args.audit_json else None,
        "summary": {
            "actions": len(actions),
            "action_phase_rows": len(action_rows),
            "defined_set_rows": len(set_rows),
            "bis_matrix_rows": len(bis_rows),
            "bis_families": len(bis_matrix.get("families", [])),
            "failures": len(failures),
            "missing_slot_rows": sum(
                1
                for row in rows
                if row.get("missing_slots") and not row.get("no_equip_expected")
            ),
            "no_equip_expected_rows": sum(
                1 for row in rows if row.get("no_equip_expected")
            ),
            "inventory_missing": len(inventory_missing),
            "audit_missing_from_inventory": len(missing_from_audit),
            "audit_unknown_resources": len(unknown_from_audit),
            "used_items": len(used_items),
            "visual_manifest_items": len(visual_manifest_entries),
            "visual_model_checked_rows": visual_checked,
            "visible_model_failures": len(visual_failures),
            "visual_model_info_rows": len(visual_info),
            "passed": len(failures) == 0
            and len(missing_from_audit) == 0
            and len(unknown_from_audit) == 0,
        },
        "bis_matrix_path": str(bis_matrix_path),
        "visual_manifest_path": str(args.write_visual_manifest) if args.write_visual_manifest else None,
        "bis_matrix": bis_matrix,
        "actions": [action.__dict__ for action in actions],
        "rows": rows,
        "failures": failures,
        "visual_model_info": visual_info,
        "inventory_missing": inventory_missing,
        "audit_missing_from_inventory": sorted(missing_from_audit),
        "audit_unknown_resources": sorted(unknown_from_audit),
    }

    if not args.no_write_report:
        json_path, md_path = write_outputs(args.output_root, report)
        print(f"json_report={json_path}")
        print(f"markdown_report={md_path}")
    print(json.dumps(report["summary"], sort_keys=True))
    return 0 if report["summary"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
