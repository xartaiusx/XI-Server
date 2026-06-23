# Server-Wide AI Bots

This branch adds a native LandSandBoat module for a full-simulation FFXI bot world. Bots are server-authored actors backed by dedicated `server_bot_*` tables; they do not run real clients and do not write normal character rows.

## Source Basis

- LandSandBoat modules: Lua for behavior, SQL for durable data, C++ only for hooks and DB bridge.
- LSB Trust AI and Garrison allied NPCs: follow, roam, engagement, dynamic MOB allies, no-drop actors, despawn control.
- FFXI Trusts and Adventuring Fellows: role identity, support behavior, independent progression/familiarity ideas.
- MaNGOS/CMaNGOS Playerbots: open-world population, strategy stacks, random bots, economy participation, and chat control. Borrow concepts only; do not port code or player-command semantics.
- EQEmu bots: explicit enable/disable, dedicated bot tables, command permissions, group/role controls.
- Sword Art Online game AI concepts: independent party formation, tactical sequence memory, and role-based autonomous combat behavior.
- Windower remains outside runtime scope; use it only for optional GM/QA overlays or observation.

## Runtime Shape

- `modules/custom/lua/server_bots.lua` is the behavior manager.
- `modules/custom/cpp/server_bots.cpp` exposes DB reads/writes, runtime flags, audit/ledger/perf helpers, and `OnCharZoneIn`.
- `modules/custom/sql/server_bots.sql` owns profiles, spawn rules, camps, routes, strategies, ledgers, personas, command permissions, runtime flags, and performance snapshots.
- `modules/custom/commands/serverbot.lua` is the GM console.
- `modules/custom/commands/bot.lua` is a disabled compatibility notice. Players use Trusts for companion gameplay.

The Lua manager falls back to bootstrap profiles/rules if `dbtool.py update` has not run yet, then switches to DB-backed data automatically once the SQL tables exist.

## Build And Migration Discipline

- Run `python tools/dbtool.py backup` before bot schema or Twills admin repair changes. Twills repair now maxes all job-point rows/categories, all merit rows, and all Alter Ego Point category ranks for the local admin test profile while keeping GM5 privileges hidden from the visible GM icon/nameflag.
- Run `python tools/dbtool.py update` twice after SQL changes; the second run must be clean/idempotent.
- Re-run CMake configure and rebuild after changing `modules/init.txt` or any `modules/custom/cpp/*.cpp` file. C++ modules are compile-time, while Lua modules reload only with the map process.
- Keep Lua behavior, SQL durable data, and C++ engine/DB bridge code separated. Do not move combat target scanning back into a broad Lua `zone:getMobs()` pass.

## Defaults

- `ENABLE_SERVER_BOTS = 1`
- `SERVER_BOT_DENSITY = 'moderate'`
- `SERVER_BOT_VISIBLE_AI_TAG = false`
- `SERVER_BOT_GLOBAL_CAP = 350`
- `SERVER_BOT_MAX_PER_ZONE = 24`
- `SERVER_BOT_IDLE_DESPAWN_SECONDS = 300`
- `SERVER_BOT_FULL_SIM_ENABLED = true`
- `SERVER_BOT_COMBAT_ENABLED = true`
- `SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED = false`
- `SERVER_BOT_ECONOMY_ENABLED = true`
- `SERVER_BOT_AH_ENABLED = false`
- `SERVER_BOT_LLM_CHAT_ENABLED = false`
- `SERVER_BOT_PLAYER_COMMANDS_ENABLED = false`
- `SERVER_BOT_AUTONOMOUS_PARTIES_ENABLED = true`
- `SERVER_BOT_MAX_BOT_PARTY_SIZE = 6`
- `SERVER_BOT_PARTY_FORMATION_INTERVAL_SECONDS = 60`
- `SERVER_BOT_MAX_ACTIVE_PARTIES_PER_ZONE = 3`
- `SERVER_BOT_COMBAT_ACTOR_MODE = 'simulated_npc'`
- `SERVER_BOT_MAX_COMBAT_BOTS_PER_ZONE = 8`
- `SERVER_BOT_TICK_BUDGET_MS = 4`

Moderate density is 12 city bots, 6 town bots, and 8 leveling-zone bots, capped by zone/global limits.

## Implemented Behavior

- Active-zone materialization on player zone-in.
- Persisted active bot state from a prior map process is reset to inactive on first runtime materialization, so empty zones do not look active after restart.
- DB-driven profiles, spawn rules, camps, route points, personas, strategy stacks, and command permissions.
- Ambient NPC actors for towns/cities and noncombat population.
- Fight-capable dynamic MOB actor scaffolding for eligible leveling profiles/zones using player allegiance, `NO_DROPS`, scripted roam, no normal respawn, explicit despawn, and audit rows.
- Dynamic MOB actors are behind `SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED` and disabled by default after West Ronfaure crash evidence showed the current Lua `zone:getMobs()` combat scanner is unsafe with dynamic MOB actors.
- Current verified leveling-zone behavior uses safe NPC actors with `role_state = adventuring`; combat strategy ticks write `combat_deferred` audit rows until the C++ combat bridge is verified.
- `SERVER_BOT_COMBAT_ACTOR_MODE` must remain `simulated_npc` until the replacement C++ safe scanner/bridge passes West Ronfaure plus one additional low-risk leveling-zone soak.
- Autonomous bot-only party formation is enabled for eligible leveling-zone bots. Parties are never owned by players, never join player parties, and persist their current party marker through `server_bot_state.bot_party_key` plus `server_bot_state.strategy_state`.
- Strategy ticks for `ambient`, `travel`, `grind`, `party_assist`, `tank`, `healer`, `support`, `ranged`, `black_mage`, `rest`, `vendor`, `auction`, `return_home`, and `panic_disable`.
- Conservative combat engagement: bots only select spawned, alive, unengaged MOB-allegiance targets near the active camp; player claims are avoided by skipping engaged targets not already claimed by the bot actor.
- Simulated XP/gil/inventory progression written to bot state and ledgers, without granting player rewards or writing real character inventory.
- Optional AH behavior is ledger-first and disabled by default until in-client economy behavior is verified.
- Optional LLM chat is flag-gated; without a provider bridge it logs fallback and uses templates.

## GM Commands

- `!serverbot status`
- `!serverbot reload`
- `!serverbot spawn <profile> [count]`
- `!serverbot despawn <zone|all>`
- `!serverbot trace [zone]`
- `!serverbot profile [profile]`
- `!serverbot rule [zone]`
- `!serverbot camp [zone|camp]`
- `!serverbot strategy [strategy]`
- `!serverbot audit [limit]`
- `!serverbot economy [limit]`
- `!serverbot perf [limit]`
- `!serverbot pause`
- `!serverbot resume`
- `!serverbot enable`
- `!serverbot disable`
- `!serverbot llm on|off`
- `!serverbot panic`

## Player Commands

`!bot` is intentionally deprecated for this project branch. It only tells players that server bots are autonomous world adventurers and that Trusts remain the player companion system.

## Verified Checkpoints

- Southern San d'Oria city materialization: 12 active city bots, active heartbeat rows, audit/performance rows under budget.
- West Ronfaure safe leveling materialization: 8 active leveling bots, NPC actor mode, `combat_deferred` audit rows, zero over-budget performance rows, and stable `xi_map` after the dynamic MOB gate was disabled.
- West Ronfaure autonomous party verification: 8 active leveling bots split into bot-only parties, `party_assist` audit rows recorded, and `server_bot_state.bot_party_key` populated after the C++ bridge rebuild.
- 2026-06-23 post-AEP-rebuild Southern San d'Oria verification: `dbtool.py update` was clean twice, all four LSB processes started through the Mochirii scripts, the `ServerBots: native bridge loaded` log line appeared, latest stderr logs contained only the standard LSB admin/root privilege warning, 12 city bots were active in zone 230, `runtime_enabled=1`, `runtime_paused=0`, `panic_disable=0`, `llm_enabled=0`, and performance snapshots stayed at 0 ms elapsed against the 4 ms tick budget.
- Automated foreground/input QA can activate the `Twills` FFXI window and capture screenshots, but did not produce `pause`/`resume` audit rows through synthetic key entry. Treat GM command execution as still requiring manual in-client entry or a purpose-built server-side QA harness.
- West Ronfaure crash evidence is preserved at `C:\Users\xtyty\Documents\FFXI\dmp\xi_map.exe_22-6_18-7-57.*`; checkpoint evidence is preserved at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\safe-west-ronfaure-bots-20260622-1821.json`.

## Verification Checklist

1. Reconfigure/rebuild after adding the C++ module.
2. Run `python tools/dbtool.py update` twice and confirm idempotency.
3. Start `xi_connect`, `xi_search`, `xi_world`, and `xi_map`; confirm no `server_bots` module errors.
4. Enter a city and verify untagged ambient bots spawn, patrol, talk, audit, and idle-despawn.
5. Enter a seeded leveling zone and verify safe NPC actors spawn, patrol camps, respect caps, and audit strategy ticks.
6. Before any command-entry or screenshot check, run
   `tools\mochirii\assert_windower_foreground.ps1` and require
   `IsWindowerClient = true`. If Windower is not foregrounded, do not send
   commands or capture screenshots; mark the client gate blocked.
7. Use every `!serverbot` command above. Manual in-client entry is currently the reliable acceptance path; synthetic Windows key injection is not accepted as proof unless the corresponding audit row appears.
8. Confirm `!bot` refuses player orders and explains the Trust boundary.
9. Confirm `!twillsrepair` repairs Twills and that Twills can verify GM commands plus Trust/Mog House, Merit Point, Job Point, Alter Ego Point/category, and master-related access after relog.
10. Inspect `server_bot_audit_log`, `server_bot_state`, `server_bot_parties`, `server_bot_party_members`, `server_bot_strategy_memory`, `server_bot_encounter_ledger`, `server_bot_economy_ledger`, `server_bot_inventory_ledger`, and `server_bot_performance_snapshots`.
11. Benchmark 1, 6, 12, and 24 bots in a zone before raising caps.
12. Keep `SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED`, `SERVER_BOT_AH_ENABLED`, and `SERVER_BOT_LLM_CHAT_ENABLED` off until those integrations have separate combat/provider/economy review.
