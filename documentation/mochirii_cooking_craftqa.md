# Mochirii Cooking Craft QA

This page documents the Cooking-first endgame crafting workflow for Mochirii.
It exists to test local Final Fantasy XI Cooking recipes through the normal
server synthesis path with Twills as the required QA/admin character.

## Source Priority

Use local Mochirii data first: `synth_recipes`, `item_basic`,
`item_equipment`, enabled content tags, and the server synthesis code. Use
Final Fantasy XI craft and food references only to classify and sanity-check the
local manifest:

- BG Wiki Craft: https://www.bg-wiki.com/ffxi/Category%3ACraft
- BG Wiki Cooking: https://www.bg-wiki.com/ffxi/Cooking
- BG Wiki Food: https://www.bg-wiki.com/ffxi/Category%3AFood
- FFXIAH item pages: https://www.ffxiah.com/
- LandSandBoat modules: https://landsandboat-server.mintlify.app/modules/overview
- Official Synthesis History guidance: https://we-are-vanadiel.finalfantasyxi.com/post/?id=695&lang=en
- Windower Craft: https://docs.windower.net/addons/craft/
- Windower Craft source: https://github.com/Windower/Lua/tree/live/addons/craft

FFXIAH is secondary corroboration for item context. It is not the authority for
whether a recipe or food effect exists on Mochirii.

## Safety Rules

- Final saved outputs must be produced by normal synthesis: crystal,
  ingredients, `synthutils::startSynth`, `ANIMATION_SYNTH`, normal synth timing,
  HQ/success/failure handling, and inventory commit.
- Retail-like synthesis history means the native client last-10 Synthesis
  History and `/lastsynth`. The CraftQA TSV is the full evidence ledger; it is
  not a fake permanent retail history table. Windower `craft repeat` is allowed
  only after native synthesis history exists because the official addon repeats
  synthesis through /lastsynth.
- `!craftqa` may stage crystals and ingredients, but it must not insert final
  crafted results directly.
- Do not use FASTSYNTH, injected synth-done packets, or direct result-item SQL.
- Use Twills only for Cooking QA. Do not use Codexgm, MochiChef, or any other
  account/character for this pass. Twills remains Alchemy 110 for strict
  retail-shaped craft parity, so Cooking is capped at 70 unless a future pass
  explicitly accepts a Cooking-specialist QA exception.
- Back up MariaDB before running repair, staging, or batch crafting commands.
- Keep runtime evidence under `/root/projects/FFXI-Runtime/crafting/cooking/`
  and out of git.

## Manifest

Generate the local endgame Cooking manifest from the live database:

```bash
python3 tools/mochirii/crafting/cooking_endgame_manifest.py
```

The manifest targets active normal Cooking recipes with `Cook >= 90` and adds
recursive local Cooking prerequisite recipes when a target ingredient is itself a
Cooking result. The default output is:

- `/root/projects/FFXI-Runtime/crafting/cooking/latest/cooking_endgame_manifest.json`
- `/root/projects/FFXI-Runtime/crafting/cooking/latest/cooking_endgame_manifest.md`

Generate Windower Craft recipe overrides from the same live database and the
live Windower item resources:

```bash
python3 tools/mochirii/crafting/windower_craft_recipes.py --write-live
```

This writes `recipes_mochirii_cooking.lua`, keeps upstream recipes in
`recipes_upstream.lua`, and makes `recipes.lua` merge upstream recipes plus
Mochirii Cooking overrides. Any Windower item-resource mismatch is blocked in
the runtime report instead of generating a broken recipe.

The live Craft addon keeps official Windower logic, with one local compatibility
patch recorded in runtime manifests: string-literal `:format(...)` calls from
the upstream source are parenthesized so the addon compiles under LuaJIT.

## Commands

`!craftqa` is GM-only and intentionally narrow:

- `!craftqa cooking status`
- `!craftqa cooking repair`
- `!craftqa cooking stage <recipeId> [attempts]`
- `!craftqa cooking craft <recipeId>`
- `!craftqa cooking historyproof <recipeId>`
- `!craftqa cooking verbose on|off`
- `!craftqa cooking batch endgame [maxAttempts]`
- `!craftqa cooking pause`
- `!craftqa cooking resume`
- `!craftqa cooking report`

`repair` restores Twills to strict retail-shaped craft caps: Alchemy 110,
Cooking 70, Fishing 110, Synergy 80, and all other synthesis crafts 70. It also
keeps storage ready, preserves the Cooking guild-point floor used for QA
evidence, and retains locally supported Cooking key items without claiming
Twills is a Cooking 110 specialist.

`stage` adds only crystals and ingredients for the requested number of attempts.
Recipes above Cooking 70 are blocked while Twills remains Alchemy-specialized.

`craft` starts one normal synthesis for the recipe. Wait for the synth to finish
before starting another manual craft.

`historyproof` stages two attempts of materials and pauses any active batch. The
first history-proof synth must be started through the native client synthesis UI,
because server-started `synthutils::startSynth` crafts normally but does not seed
the client-local Synthesis History. When the native first synth completes, run
`/lastsynth`; CraftQA observes whether the client starts the same recipe from
native synthesis history and records `history_lastsynth_verified` in the TSV.

`verbose on|off` toggles GM-only CraftQA evidence chat. It is off by default and
must not replace native synthesis result and obtained-item messages. Normal batch
runs should keep it off to avoid duplicate chat noise.

`batch endgame` is intentionally blocked while Twills remains Alchemy 110 /
Cooking 70. Use `report` to classify the manifest instead of pretending Twills
can complete endgame Cooking under strict retail caps.

`report` classifies every manifest target as `saved`, `blocked_retail_cap`,
`craftable_unsaved`, or `unsupported`. Existing saved items from the earlier
Cooking 110 QA window are evidence only; they are not proof that Twills can
retail-legitimately craft every endgame Cooking recipe while Alchemy-specialized.

## Verification

Before calling the workflow complete:

1. Run the manifest generator and confirm there are no missing local rows and
   that Twills coverage is classified with `blocked_retail_cap` for recipes
   above Cooking 70.
2. Run Lua syntax checks for `modules/custom/commands/craftqa.lua`.
3. Rebuild `xi_map` after C++ module changes.
4. Restart `xi_map` so the compiled module is active.
5. Log in as Twills, run `!craftqa cooking repair`, then stage and
   craft a small known recipe before a full batch.
6. Use native Windower screenshots for in-game proof of synthesis animation,
   normal wait, and the resulting item.
7. Confirm logs show normal synth handling and no FASTSYNTH/direct-result path.
8. Run `!craftqa cooking historyproof <recipeId>`, perform the first synth through
   the native client synthesis UI, wait for completion, then run native
   `/lastsynth`. Acceptance is a TSV `history_lastsynth_verified` row for the
   same recipe.
9. Open the in-client Synthesis History menu and capture a native Windower
   screenshot showing the recipe in the recent-history list.
10. Capture chat evidence for native synthesis success/failure/result messages.
    Only enable `verbose` if the native result messages are insufficient for GM
    QA evidence.
