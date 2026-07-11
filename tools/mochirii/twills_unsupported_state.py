#!/usr/bin/env python3
"""Report exact Twills state tied to incomplete Mochirii content.

This tool is intentionally dry-run only. It never writes to MariaDB.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from typing import Any

REGISTRY_PATH = Path("documentation/data/mochirii_content_parity.json")
KEY_ITEM_PATH = Path("scripts/enum/key_item.lua")
ATMA_PATH = Path("scripts/globals/abyssea/atma.lua")
SAFE_COLUMN = re.compile(r"^[a-z][a-z0-9_]*$")


def run_sql(database: str, sql: str) -> list[list[str]]:
    result = subprocess.run(
        ["mariadb", "--batch", "--raw", "--skip-column-names", database, "-e", sql],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def sql_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "''") + "'"


def load_registry(repo_root: Path) -> dict[str, Any]:
    return json.loads((repo_root / REGISTRY_PATH).read_text(encoding="utf-8"))


def parse_key_items(repo_root: Path) -> dict[str, int]:
    text = (repo_root / KEY_ITEM_PATH).read_text(encoding="utf-8")
    return {
        name: int(item_id)
        for name, item_id in re.findall(
            r"^\s*([A-Z][A-Z0-9_]+)\s*=\s*(\d+),", text, re.MULTILINE
        )
    }


def empty_atma_names(repo_root: Path) -> list[str]:
    text = (repo_root / ATMA_PATH).read_text(encoding="utf-8")
    rows = re.findall(r"\[xi\.ki\.(ATMA_OF_[A-Z0-9_]+)\]\s*=\s*\{([^}]*)\}", text)
    return sorted(name for name, body in rows if not body.strip())


def blob_has_bit(blob: bytes, bit_id: int) -> bool:
    byte_index = bit_id >> 3
    if byte_index >= len(blob):
        return False
    return bool(blob[byte_index] & (1 << (bit_id & 7)))


def policy_action(policy: str, state_type: str) -> str:
    if policy == "quarantine_rewards":
        return f"quarantine_{state_type}"
    if policy == "reset_cycle_state":
        return f"reset_{state_type}"
    return f"review_{state_type}"


def collect(repo_root: Path, database: str, character: str) -> dict[str, Any]:
    registry = load_registry(repo_root)
    systems = registry["systems"]
    character_rows = run_sql(
        database,
        "SELECT charid, HEX(COALESCE(keyitems, '')) FROM chars "
        f"WHERE charname = {sql_string(character)} LIMIT 1",
    )
    if not character_rows:
        raise RuntimeError(f"character not found: {character}")

    char_id = int(character_rows[0][0])
    key_item_blob = bytes.fromhex(character_rows[0][1]) if character_rows[0][1] else b""

    currency_to_systems: dict[str, list[dict[str, Any]]] = {}
    item_to_systems: dict[int, list[dict[str, Any]]] = {}
    explicit_key_items: dict[str, list[dict[str, Any]]] = {}
    for system in systems:
        for column in system.get("unsupportedCurrencies", []):
            if not SAFE_COLUMN.fullmatch(column):
                raise ValueError(f"unsafe currency column in registry: {column}")
            currency_to_systems.setdefault(column, []).append(system)
        for item_id in system.get("activeRdmRewardItemIds", []):
            item_to_systems.setdefault(int(item_id), []).append(system)
        for key_item_name in system.get("keyItemNames", []):
            explicit_key_items.setdefault(key_item_name, []).append(system)

    currency_rows: list[dict[str, Any]] = []
    if currency_to_systems:
        columns = sorted(currency_to_systems)
        values = run_sql(
            database,
            f"SELECT {', '.join(f'`{column}`' for column in columns)} "
            f"FROM char_points WHERE charid = {char_id} LIMIT 1",
        )
        if values:
            for column, raw_value in zip(columns, values[0], strict=True):
                for system in currency_to_systems[column]:
                    currency_rows.append(
                        {
                            "system": system["key"],
                            "column": column,
                            "value": int(raw_value),
                            "action": policy_action(system["repairPolicy"], "currency"),
                        }
                    )

    inventory_rows: list[dict[str, Any]] = []
    if item_to_systems:
        item_ids = sorted(item_to_systems)
        rows = run_sql(
            database,
            "SELECT ci.location, ci.slot, ci.itemId, ib.name, ci.quantity, "
            "HEX(COALESCE(ci.extra, '')) FROM char_inventory ci "
            "JOIN item_basic ib ON ib.itemid = ci.itemId "
            f"WHERE ci.charid = {char_id} AND ci.itemId IN ({', '.join(map(str, item_ids))}) "
            "ORDER BY ci.location, ci.slot",
        )
        for location, slot, item_id_raw, name, quantity, extra_hex in rows:
            item_id = int(item_id_raw)
            for system in item_to_systems[item_id]:
                inventory_rows.append(
                    {
                        "system": system["key"],
                        "location": int(location),
                        "slot": int(slot),
                        "itemId": item_id,
                        "name": name,
                        "quantity": int(quantity),
                        "extraHex": extra_hex,
                        "action": policy_action(system["repairPolicy"], "item"),
                    }
                )

    key_item_ids = parse_key_items(repo_root)
    key_item_rows: list[dict[str, Any]] = []
    for name, owner_systems in explicit_key_items.items():
        if name not in key_item_ids:
            raise ValueError(f"unknown key item in registry: {name}")
        item_id = key_item_ids[name]
        if blob_has_bit(key_item_blob, item_id):
            for system in owner_systems:
                key_item_rows.append(
                    {
                        "system": system["key"],
                        "keyItem": name,
                        "keyItemId": item_id,
                        "action": policy_action(system["repairPolicy"], "key_item"),
                    }
                )

    for name in empty_atma_names(repo_root):
        item_id = key_item_ids.get(name)
        if item_id is not None and blob_has_bit(key_item_blob, item_id):
            key_item_rows.append(
                {
                    "system": "abyssea",
                    "keyItem": name,
                    "keyItemId": item_id,
                    "action": "quarantine_key_item_until_effect_implemented",
                }
            )

    return {
        "schemaVersion": 1,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "mode": "dry-run-only",
        "database": database,
        "character": character,
        "charId": char_id,
        "currencies": sorted(
            currency_rows, key=lambda row: (row["system"], row["column"])
        ),
        "inventory": sorted(
            inventory_rows,
            key=lambda row: (row["system"], row["location"], row["slot"]),
        ),
        "keyItems": sorted(
            key_item_rows, key=lambda row: (row["system"], row["keyItemId"])
        ),
        "titles": [],
        "missions": [],
        "quests": [],
        "applySupported": False,
    }


def write_report(output_dir: Path, payload: dict[str, Any]) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    json_path = output_dir / f"twills-unsupported-state-dry-run-{stamp}.json"
    md_path = output_dir / f"twills-unsupported-state-dry-run-{stamp}.md"
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Twills Unsupported-State Dry Run",
        "",
        f"- Character: `{payload['character']}` (`{payload['charId']}`)",
        "- Apply supported: `false`",
        f"- Currency rows: `{len(payload['currencies'])}`",
        f"- Inventory rows: `{len(payload['inventory'])}`",
        f"- Key-item rows: `{len(payload['keyItems'])}`",
        "",
        "## Currencies",
        "",
        "| System | Column | Value | Proposed action |",
        "| --- | --- | ---: | --- |",
    ]
    for row in payload["currencies"]:
        lines.append(
            f"| {row['system']} | `{row['column']}` | {row['value']} | `{row['action']}` |"
        )

    lines.extend(
        [
            "",
            "## Inventory",
            "",
            "| System | Location | Slot | Item | Quantity | Proposed action |",
            "| --- | ---: | ---: | --- | ---: | --- |",
        ]
    )
    for row in payload["inventory"]:
        lines.append(
            f"| {row['system']} | {row['location']} | {row['slot']} | "
            f"`{row['name']}` ({row['itemId']}) | {row['quantity']} | `{row['action']}` |"
        )

    lines.extend(
        [
            "",
            "## Key Items",
            "",
            "| System | Key item | ID | Proposed action |",
            "| --- | --- | ---: | --- |",
        ]
    )
    for row in payload["keyItems"]:
        lines.append(
            f"| {row['system']} | `{row['keyItem']}` | {row['keyItemId']} | `{row['action']}` |"
        )

    lines.extend(
        [
            "",
            "No mutation is implemented by this tool. Titles, missions, and quests remain empty until the registry has exact provenance mappings.",
        ]
    )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--database", default="xidb")
    parser.add_argument("--character", default="Twills")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()

    payload = collect(args.repo_root.resolve(), args.database, args.character)
    if args.output_dir:
        json_path, md_path = write_report(args.output_dir.resolve(), payload)
        print(json_path)
        print(md_path)
    else:
        print(
            json.dumps(
                {
                    "currencies": len(payload["currencies"]),
                    "inventory": len(payload["inventory"]),
                    "keyItems": len(payload["keyItems"]),
                    "applySupported": payload["applySupported"],
                },
                sort_keys=True,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
