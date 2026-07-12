#!/usr/bin/env python3
"""Generate a Mochirii endgame Cooking synthesis manifest from the live DB."""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

FOOD_CATEGORIES = {
    0: "special_none",
    26: "tank_or_back_slot",
    33: "medicine",
    37: "cursed_special",
    48: "pet_broth",
    51: "fish",
    52: "meat_eggs",
    53: "seafood",
    54: "vegetables",
    55: "soups",
    56: "breads_rice",
    57: "sweets",
    58: "drinks",
    59: "ingredients",
}

TWILLS_RETAIL_COOKING_CAP = 70

KEY_ITEM_NAMES = {
    0: "None",
    2040: "Raw Fish Handling",
    2041: "Noodle Kneading",
    2042: "Patissier",
    2043: "Stewpot Mastery",
    2044: "Way of the Culinarian",
    2046: "Culinarian's Aurum Tome",
}

SQL = r"""
SELECT
    r.ID, r.Desynth, r.KeyItem, r.Cook, r.Crystal, r.HQCrystal,
    r.Ingredient1, r.Ingredient2, r.Ingredient3, r.Ingredient4,
    r.Ingredient5, r.Ingredient6, r.Ingredient7, r.Ingredient8,
    r.Result, r.ResultHQ1, r.ResultHQ2, r.ResultHQ3,
    r.ResultQty, r.ResultHQ1Qty, r.ResultHQ2Qty, r.ResultHQ3Qty,
    r.ResultName, COALESCE(r.content_tag, ''),
    COALESCE(result_item.name, ''), COALESCE(result_item.aH, 255)
FROM synth_recipes r
LEFT JOIN item_basic result_item ON result_item.itemid = r.Result
WHERE r.Cook > 0 AND r.Desynth = 0
ORDER BY r.Cook DESC, r.ResultName, r.ID;
"""

ITEM_SQL = r"""
SELECT itemid, name, aH, stackSize FROM item_basic;
"""

TWILLS_CHAR_SQL = r"""
SELECT charid FROM chars WHERE charname = 'Twills' LIMIT 1;
"""

TWILLS_INVENTORY_SQL = r"""
SELECT itemId, COALESCE(SUM(quantity), 0) AS quantity
FROM char_inventory
WHERE charid = {charid}
GROUP BY itemId;
"""

TWILLS_CRAFT_SQL = r"""
SELECT skillid, value, rank
FROM char_skills
WHERE charid = {charid} AND skillid BETWEEN 48 AND 57
ORDER BY skillid;
"""


@dataclass
class Recipe:
    id: int
    cook: int
    result_name: str
    result_item_id: int
    result_item_name: str
    category: str
    crystal: int
    hq_crystal: int
    ingredients: list[int]
    results: list[dict[str, int]]
    key_item: int
    key_item_name: str
    content_tag: str
    target_kind: str
    local_supported: bool
    missing_item_ids: list[int]
    source_links: dict[str, str]


def run_mariadb(mysql: str, database: str, sql: str) -> list[list[str]]:
    proc = subprocess.run(
        [mysql, "--batch", "--raw", "--skip-column-names", database],
        input=sql,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"mariadb failed: {proc.stderr.strip()}")

    rows: list[list[str]] = []
    for line in proc.stdout.splitlines():
        if line.strip():
            rows.append(line.split("\t"))
    return rows


def int_at(row: list[str], index: int) -> int:
    value = row[index]
    return int(value) if value else 0


def unique(values: Iterable[int]) -> list[int]:
    out: list[int] = []
    for value in values:
        if value and value not in out:
            out.append(value)
    return out


def ffxiah_item_url(item_id: int) -> str:
    return f"https://www.ffxiah.com/item/{item_id}"


def bg_search_url(name: str) -> str:
    return "https://www.bg-wiki.com/index.php?search=" + name.replace(" ", "+")


def recipe_from_row(row: list[str], item_names: dict[int, str]) -> Recipe:
    ingredients = [int_at(row, i) for i in range(6, 14) if int_at(row, i) != 0]
    result_ids = [int_at(row, i) for i in range(14, 18)]
    result_qtys = [int_at(row, i) for i in range(18, 22)]
    result_pairs: list[dict[str, int]] = []
    seen_results: set[int] = set()
    for tier, item_id in enumerate(result_ids):
        if item_id and item_id not in seen_results:
            result_pairs.append({"tier": tier, "item_id": item_id, "quantity": result_qtys[tier] or 1})
            seen_results.add(item_id)

    all_item_ids = unique([int_at(row, 4), int_at(row, 5), *ingredients, *result_ids])
    missing = [item_id for item_id in all_item_ids if item_id and item_id not in item_names]
    ah_category = int_at(row, 25)
    result_name = row[22]
    result_item_id = int_at(row, 14)

    return Recipe(
        id=int_at(row, 0),
        cook=int_at(row, 3),
        result_name=result_name,
        result_item_id=result_item_id,
        result_item_name=row[24] or item_names.get(result_item_id, ""),
        category=FOOD_CATEGORIES.get(ah_category, f"ah_{ah_category}"),
        crystal=int_at(row, 4),
        hq_crystal=int_at(row, 5),
        ingredients=ingredients,
        results=result_pairs,
        key_item=int_at(row, 2),
        key_item_name=KEY_ITEM_NAMES.get(int_at(row, 2), f"KeyItem {int_at(row, 2)}"),
        content_tag=row[23],
        target_kind="endgame" if int_at(row, 3) >= 90 else "prerequisite",
        local_supported=len(missing) == 0,
        missing_item_ids=missing,
        source_links={
            "bg_wiki_search": bg_search_url(result_name),
            "ffxiah_item": ffxiah_item_url(result_item_id) if result_item_id else "",
        },
    )


def collect_targets(recipes: list[Recipe]) -> list[Recipe]:
    by_result: dict[int, list[Recipe]] = defaultdict(list)

    for recipe in recipes:
        by_result[recipe.result_item_id].append(recipe)

    selected: dict[int, Recipe] = {}
    queue: deque[int] = deque()

    for recipe in recipes:
        if recipe.cook >= 90:
            selected[recipe.id] = recipe
            queue.extend(recipe.ingredients)

    while queue:
        ingredient_id = queue.popleft()
        for prereq in by_result.get(ingredient_id, []):
            if prereq.id in selected:
                continue

            selected[prereq.id] = prereq
            queue.extend(prereq.ingredients)

    return sorted(selected.values(), key=lambda recipe: (-recipe.cook, recipe.result_name, recipe.id))



def get_twills_state(mysql: str, database: str) -> dict:
    rows = run_mariadb(mysql, database, TWILLS_CHAR_SQL)
    if not rows:
        return {"charid": None, "inventory_item_ids": [], "craft_skills": {}, "found": False}

    charid = int(rows[0][0])
    inventory_rows = run_mariadb(mysql, database, TWILLS_INVENTORY_SQL.format(charid=charid))
    craft_rows = run_mariadb(mysql, database, TWILLS_CRAFT_SQL.format(charid=charid))

    return {
        "charid": charid,
        "found": True,
        "inventory_item_ids": sorted(int(row[0]) for row in inventory_rows if int(row[1]) > 0),
        "craft_skills": {row[0]: {"value": int(row[1]), "rank": int(row[2])} for row in craft_rows},
    }


def coverage_status(recipe: Recipe, owned_item_ids: set[int]) -> str:
    if not recipe.local_supported:
        return "unsupported"

    if recipe.cook > TWILLS_RETAIL_COOKING_CAP:
        return "blocked_retail_cap"

    result_ids = {entry["item_id"] for entry in recipe.results if entry["item_id"]}
    if result_ids and result_ids.issubset(owned_item_ids):
        return "saved"

    return "craftable_unsaved"

def write_outputs(manifest: dict, out_dir: Path) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "cooking_endgame_manifest.json"
    md_path = out_dir / "cooking_endgame_manifest.md"
    json_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    lines = [
        "# Mochirii Cooking Endgame Manifest",
        "",
        f"Generated: {manifest['generated_at']}",
        f"Database: {manifest['database']}",
        f"Targets: {manifest['summary']['targets']}",
        f"Endgame recipes: {manifest['summary']['endgame_recipes']}",
        f"Prerequisite recipes: {manifest['summary']['prerequisite_recipes']}",
        f"Unsupported local rows: {manifest['summary']['unsupported_local_rows']}",
        f"Twills coverage: saved={manifest['summary'].get('twills_saved', 0)}, "
        f"blocked_retail_cap={manifest['summary'].get('twills_blocked_retail_cap', 0)}, "
        f"craftable_unsaved={manifest['summary'].get('twills_craftable_unsaved', 0)}, "
        f"unsupported={manifest['summary'].get('twills_unsupported', 0)}",
        "",
        "| Kind | ID | Cook | Result | Status | Category | Key Item | Results |",
        "| --- | ---: | ---: | --- | --- | --- | --- | --- |",
    ]

    for recipe in manifest["recipes"]:
        results = ", ".join(f"T{entry['tier']}:{entry['item_id']}x{entry['quantity']}" for entry in recipe["results"])
        lines.append(
            f"| {recipe['target_kind']} | {recipe['id']} | {recipe['cook']} | {recipe['result_name']} | "
            f"{recipe.get('twills_status', 'unknown')} | {recipe['category']} | {recipe['key_item_name']} | {results} |"
        )

    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default="xidb")
    parser.add_argument("--mysql", default="mariadb")
    parser.add_argument("--out-dir", default="/home/xartyzx/projects/FFXI-Runtime/crafting/cooking/latest")
    parser.add_argument("--stdout", action="store_true", help="Print JSON to stdout instead of writing files")
    args = parser.parse_args()

    item_rows = run_mariadb(args.mysql, args.database, ITEM_SQL)
    item_names = {int(row[0]): row[1] for row in item_rows}
    recipe_rows = run_mariadb(args.mysql, args.database, SQL)
    all_recipes = [recipe_from_row(row, item_names) for row in recipe_rows]
    targets = collect_targets(all_recipes)
    twills_state = get_twills_state(args.mysql, args.database)
    owned_item_ids = set(twills_state["inventory_item_ids"])
    recipe_dicts = []
    for recipe in targets:
        row = asdict(recipe)
        row["twills_status"] = coverage_status(recipe, owned_item_ids) if twills_state["found"] else "twills_not_found"
        recipe_dicts.append(row)

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": args.database,
        "selection_rule": "active normal Cooking recipes with Cook >= 90 plus recursive local Cooking prerequisite recipes",
        "summary": {
            "all_active_cooking_recipes": len(all_recipes),
            "targets": len(targets),
            "endgame_recipes": sum(1 for recipe in targets if recipe.target_kind == "endgame"),
            "prerequisite_recipes": sum(1 for recipe in targets if recipe.target_kind == "prerequisite"),
            "unsupported_local_rows": sum(1 for recipe in targets if not recipe.local_supported),
            "twills_saved": sum(1 for recipe in recipe_dicts if recipe["twills_status"] == "saved"),
            "twills_blocked_retail_cap": sum(1 for recipe in recipe_dicts if recipe["twills_status"] == "blocked_retail_cap"),
            "twills_craftable_unsaved": sum(1 for recipe in recipe_dicts if recipe["twills_status"] == "craftable_unsaved"),
            "twills_unsupported": sum(1 for recipe in recipe_dicts if recipe["twills_status"] in {"unsupported", "twills_not_found"}),
        },
        "twills": {
            "charid": twills_state["charid"],
            "retail_specialization": "Alchemy 110",
            "cooking_cap": TWILLS_RETAIL_COOKING_CAP,
            "craft_skills": twills_state["craft_skills"],
        },
        "recipes": recipe_dicts,
    }

    if args.stdout:
        print(json.dumps(manifest, indent=2, sort_keys=True))
    else:
        json_path, md_path = write_outputs(manifest, Path(args.out_dir))
        print(f"Wrote {json_path}")
        print(f"Wrote {md_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
