# Mochirii Trust Retail Parity

## Goal

Trusts should be as close to player-like retail behavior as this Mochirii checkout can safely support. Each Trust keeps its own identity, role, movement style, TP behavior, and special quirks, but Mochirii may fill in safe job/subjob tools when the user preference is "as close to a player with their job/subjob as possible."

Primary references:

- Official Final Fantasy XI Trust guide: Trust alter egos have distinct roles and behavior.
- BG Wiki Trust pages for observed spell, ability, weapon skill, and special-feature behavior.
- Local Trust controller and existing Trust spell scripts for supported movement, gambit, casting, and TP behavior.

## Current Parity Patch

Trust defensive mode is handled in `src/map/ai/controllers/trust_controller.cpp`. When a hostile mob has enmity on the player or any active Trust, Trusts can engage defensively even if the player has not made a melee swing yet. This keeps the normal Mochirii `TrustEngageType` behavior for ordinary pulls while making Trust parties protect the player and each other from aggro.

Mochirii Trust settings:

- `ALLOW_TRUST_CASTING_WITH_ENMITY = 1` lets players summon Trusts after they already have enmity or are in combat. This is a Mochirii server rule, while the remaining local gates still apply: Trust casting enabled, zone allows Trusts, solo/leader, no party-seeking, party-size/Rhapsodies limits, and battlefield trust permissions.
- `ENABLE_TRUST_CASTING = 1`, `ENABLE_TRUST_QUESTS = 1`, and `ENABLE_TRUST_CUSTOM_ENGAGEMENT = 1` stay enabled. Prefer these native Mochirii controls before adding new custom behavior. Twills is repaired to `TrustEngageType = 1`, matching the custom engagement mode where Trusts attack when the master engages, not only after the first melee swing.
- `ENABLE_TRUST_DEFENSIVE_MODE = true` lets Trusts automatically engage mobs that have enmity on the player or any active Trust party member. This is independent from `!trustengage`; `TrustEngageType` still controls ordinary proactive engagement rules.
- `ENABLE_TRUST_SHARED_TARGETING = true` keeps Trusts coordinated on one focus target. The master's engaged target wins, then defensive threats, then the Trust's current target.
- `ENABLE_TRUST_ROLE_ENMITY = true` lets tank Trusts add conservative enmity nudges on the focus target and lets non-tanks shed a percentage of accidental top enmity.
- `ENABLE_TRUST_ALTER_EGO_POINT_BONUSES = true` applies Twills' stored Alter Ego Point ranks to Trust vitals, base stats, combat skills, and magic skills at summon time.
- `ENABLE_TRUST_UNITY_RANK_STAT_PARITY = true` applies a small Unity-rank-like all-stat bonus to every Trust. This is a Mochirii parity layer: official Final Fantasy XI gives Unity leader alter egos rank-based bonuses, but this checkout does not expose a fully researched retail formula, and local Unity Trust scripts still mark the exact bonus as research-needed. If the summoner has no Unity leader/rank data, the configured default rank is used.

Trust positioning:

- Use the local per-Trust `MOBMOD_TRUST_DISTANCE` / `xi.trust.movementType` controls first. The controller no longer infers long-range positioning from broad jobs such as COR, because Trusts like Luzaf are melee-first despite having a ranged-capable job. Luzaf now explicitly sets `xi.trust.movementType.MELEE`; ranged/support Trusts should be handled with their own script-level movement setting.

Windower QA overlay:

- XivParty is loaded from Windower's `scripts/init.txt` and configured through `Windower/addons/XivParty/data/settings.xml`, matching the addon's documented install/load/settings model.
- The current Mochirii layout positions the main party and two alliance party overlays near the native lower-right party list. Use `//lua reload XivParty` after settings changes, then fine-tune in-game with `//xp setup` if monitor scaling, resolution, or the native UI layout changes.
- The current default Windower QA addon stack is loaded from `Windower\scripts\init.txt` and includes `XIPivot`, `XICamera`, `DistancePlus`, `TParty`, `XivParty`, `pointwatch`, `battlemod`, `Debuffed`, `targetinfo`, `scoreboard`, `Logger`, `DressUp`, `cancel`, `GearSwap`, `xivhotbar`, `MochiriiTrustQA`, `MochiriiScreenshotQA`, `dynamishelper`, `EmpyPopTracker`, `enemybar`, `equipviewer`, `FastCS`, `gametime`, `giltracker`, `highlight`, `indinope`, `InfoBar`, `macrochanger`, `NoCampaignMusic`, `NyzulHelper`, `obiaway`, `ohShi`, `Omen`, `PetTP`, `plasmon`, `Pouches`, `RAWR`, `reive`, `Silence`, `StratHelper`, `Tab`, `Treasury`, `update`, and `vwhl`. XICamera is kept at conservative release defaults for Trust QA: normal camera distance 6, battle distance 8.2, battle range 4, and battle lock on.
- Official plugins loaded for QA are `Config`, `Timers`, `FFXIDB`, `MipmapFix`, `SSOrganizer`, and `WinControl`; `LuaCore` loads as the addon runtime. This matches Windower's plugin/addon split: plugins are DLLs maintained by the launcher, while Lua addons are the preferred extension path.
- Before sending commands or taking screenshots, foreground the `Twills` xiloader/Windower window and run `tools\mochirii\assert_windower_foreground.ps1`. Screenshots count as evidence only when `tools\mochirii\capture_windower_window.ps1` triggers Windower's native `screenshot` command after `IsWindowerClient = true` and reports image dimensions covering the live client after DPI scaling; OS-level captures are not valid Trust QA evidence.
- 2026-06-24 verification: forced reload of the default addon stack produced no fresh runtime/error lines after adding a local PointWatch compatibility guard for Mochirii Exemplar/Master point fields. Evidence: `C:\Users\xtyty\Documents\FFXI-Runtime\logs\windower-addon-reload-20260624-0417.log`.

Valaineral is the first tank target because Twills' Trust party showed him active and he is a clear PLD/WAR baseline.

- Existing Mochirii behavior already covers PLD/WAR tanking, Uriel Blade, Holy Circle, Provoke, Shield Bash, Sentinel, Chivalry, Defender, Rampart, Majesty, Fealty, Divine Emblem, Protect, Shell, Flash, Reprisal, Cure, Enlight, Phalanx, and random 2000 TP weapon skills.
- This patch adds `Palisade` at level 95, matching the Paladin Trust pattern used by AAEV and August.
- This patch adds `Banish III` to Valaineral's Trust spell list.
- Banish III is initially used only against undead targets through a conservative gambit until in-client retail timing confirms broader use.

Qultada is the first COR support target.

- He now opens with `Chaos Roll` and uses `Fighter's Roll` as his normal second roll.
- He uses `Corsair's Roll` when the master has `Dedication` or `Commitment`, matching his EXP/CP bonus behavior.
- He uses `Double-Up` only when the local Corsair utility has applied `DOUBLE_UP_CHANCE` after a valid roll.
- He can use `Evoker's Roll` as a low-MP alternate second roll, guarded so it does not repeatedly replace active `Corsair's Roll` or `Fighter's Roll`.
- He uses `Triple Shot` at level 87.
- He uses `Dark Shot` to dispel and `Light Shot` to enhance active Dia effects. If Dia is not present, the local Light Shot mobskill keeps its previous Sleep fallback.
- Corsair roll calculation now skips PC-only `getMaxGearMod()` gear checks for Trust casters, keeping Qultada's rolls clean while preserving Phantom Roll+ gear behavior for real player Corsairs.

Joachim is the first BRD support target.

- He now favors `March` plus `Madrigal` as his normal support pair.
- He casts highest available `Elegy` on engaged targets; his local Trust spell list already includes Battlefield/Carnage Elegy.
- He uses `Ballad` when party MP is low and `Paeon` when party HP is low.
- His existing Mochirii status removal, curing, ranged attacks, and BRD/WHM spell list remain intact.

Ulmia is the second BRD support target because she pairs naturally with Joachim and was active during Mochirii combat-summon verification.

- She now uses `Sentinel's Scherzo` as a danger-window support song when party HP is low.
- She uses `Mage's Ballad` when party MP is low.
- She favors `March` as her baseline haste support song.
- She keeps `Minuet` and `Madrigal` as offensive filler songs.
- Her existing Mochirii no-auto-attack and mid-range positioning behavior remains intact.

Kupipi is the first WHM healer target because she is a foundational starter Trust and gives the clearest healer baseline for future parity work.

- Local Mochirii data already gives her Cure I-VI, status removals, Erase, Slow, Paralyze, Flash, Starlight, Moonlight, Protectra I-V, and Shellra I-V.
- This patch makes the mob pool WHM/SCH and adds a Mochirii player-like WHM/SCH extension: `Light Arts`, `Addendum: White`, guarded `Penury`, `Celerity`, `Accession`, `Sublimation`, Storm I spells, Helix I spells in the spell list, `Klimaform`, Regen I-IV, `Haste`, `Dia`, `Addle`, `Repose`, `Auspice`, `Boost-MND`, Curaga/Cura family spells, Raise/Arise family spells, Reraise family spells through `Reraise IV`, elemental/status Bar-spells, `Afflatus Solace`, `Divine Seal`, `Divine Caress`, rare panic `Asylum`, `Benediction`, `Sacrosanctity`, and self-survival `Aquaveil`, `Stoneskin`, and `Blink`.
- This patch adds single-target `Protect` I-V and `Shell` I-V to her Trust spell list so she can refresh missing/dispelled defenses without always relying on AoE -ra spells. Single-target `Protect V` and `Shell V` use level 76 to match local spell data.
- Her runtime gambits prioritize emergency healing, Sleep wakeup, `Divine Caress` before hard status removal, Raise/Reraise recovery, defensive refreshes, Haste, and conservative Dia/Addle/Repose/Slow/Paralyze enfeebling.
- Latest Kupipi combat log analysis showed good WHM/SCH opener behavior (`Protect V`, `Shell V`, `Afflatus Solace`, `Light Arts`, `Addendum: White`, `Haste`, `Regen IV`, `Aquaveil`, `Dia II`, `Slow`, `Stoneskin`, `Boost-MND`, `Paralyze`) but poor sustain: she continued optional casts and Scholar abilities after dropping near empty MP. The current pass adds MP gates to non-emergency buffs, enfeebles, defensive self-buffs, Curaga, Reraise, and stratagem use. Emergency cures and `Benediction` remain available.
- The follow-up 2026-06-23 Escha-Ru'Aun log showed the next sustain issue: generic `HIGHEST` Cure gambits made Kupipi spend Cure VI on moderate damage, and missing Protect/Shell refreshes consumed too much MP inside combat. The V4 pass replaces her broad Cure gambits with a tiered Cure II-VI ladder using HP percent plus missing-HP thresholds, gates Protect/Shell refreshes to high MP, and gates Slow/Paralyze/Flash so enfeebling cannot spend recovery MP.
- Backline caster Trusts can logically rest for MP/HP recovery, starting out of combat at `TRUST_CASTER_REST_MPP_START` or `TRUST_CASTER_REST_HPP_START` and standing at `TRUST_CASTER_REST_MPP_STOP`. Mochirii intentionally does not force native kneel/healing animation packets for Trusts; XivParty displays a compact resting marker beside Trust names from the live rest-state TSV instead.
- The rest controller treats caster resting as sticky and no longer stops at low MP just because HP is full. Rest stops only at configured MP/HP floors or valid interrupts such as threat, movement, owner distance, combat safety, or renewed action priority.
- Backline caster Trusts may also rest during combat when `ENABLE_TRUST_CASTER_COMBAT_RESTING` is enabled, but only if they are personally unthreatened, have no immediate MP recovery source already active or ready, are within the follow-distance break, have not been recently hit, and the master/Trust party is above `TRUST_CASTER_COMBAT_REST_PARTY_HPP_MIN`.
- Combat rest uses role floors instead of full recovery: WHM/SCH-style healers such as Kupipi stand at `TRUST_CASTER_COMBAT_REST_HEALER_STOP_MPP`, support casters stand at `TRUST_CASTER_COMBAT_REST_SUPPORT_STOP_MPP`, and nukers stand at `TRUST_CASTER_COMBAT_REST_NUKER_STOP_MPP`. This lets a healer recover emergency-cure MP without sitting through the entire fight.
- Curaga is intentionally guarded by a large HP-missing threshold because `PARTY_MULTI` exists in the local gambit enum but is not implemented in the current target-selection branch.
- `Esuna` is in her spell list for player-like WHM completeness, but is not auto-used yet because the local spell script is caster-centered and needs a custom Trust-safe party-targeting helper before it can be reliable.
- `Sacrifice` is deferred even though it is a normal WHM spell because this checkout's mob spell container does not currently classify it into a clean Trust-castable spell bucket.
- `Devotion` and `Martyr` are intentionally deferred; local healer Trusts already mark them as needing conditional behavior, and the current generic gambit action path can mis-target party-member JAs that are not self-targeted.
- Auto-attacks are disabled so she behaves like a backline healer.
- `Convert` and RDM-like behavior are still intentionally not added because Kupipi is modeled as WHM/SCH, not RDM.

GM QA:

- `!trustparty status` lists active Trusts and whether Mochirii has a parity profile for them.
- `!trustparty summonqa` resets the QA alliance, summons the locked 17-Trust roster, waits until all expected Trusts are active, and then applies the repair pass automatically. Do not run `!trustparty repair` or `!trustparty audit active` while the summon sequence is still in progress; the command guard will refuse them until the roster is complete.
- `!trustparty repair` refreshes supported active Trust spell lists and applies runtime gambits without requiring a full party recast. Use it only after normal Trust summoning is complete or after `!trustparty summonqa` prints the completion message.
- `!trustparty audit active`, `!trustparty audit all`, and `!trustparty audit <trust>` report profile coverage, role model, support scope, range goal, buff/debuff maintenance policy, identity rules, status, and deferred work for active Trusts or the local roster.
- Current QA alliance Trusts have explicit profile annotations for support scope, range, buff policy, and identity. The rest of the roster receives generated audit profiles so every local Trust script stays visible in audits until its source-backed parity pass is complete.
- Lua Trust scripts and module commands can hot-reload through the local file watcher, but already-summoned Trusts keep their existing gambit list. Use `!trustparty repair` for additive runtime fixes after the party is fully settled, and dismiss/resummon Qultada or Joachim to verify revised roll/song priority from a clean spawn.
- SQL-backed Trust spell lists are cached by `xi_map` at startup. Restart `xi_map` before validating newly added `mob_spell_lists` rows such as Valaineral's Banish III.
- C++ controller changes require rebuilding and restarting `xi_map`.
- Use the Windower QA command bridge for text commands only. Avoid `/attack` without a confirmed target because it can leave the client in a modal target-selection prompt where physical game-control keys appear unresponsive while chat text still works.

Trust action logs:

- `ENABLE_TRUST_ACTION_LOG = true` enables the Mochirii Trust action logger.
- `TRUST_ACTION_LOG_PLAYER = 'Twills'` limits the trace to Twills' Trust party by default. Set it to an empty string only when intentionally tracing every player's Trusts.
- `TRUST_ACTION_LOG_DIR = '/root/projects/FFXI-Runtime/logs/trust_actions'` writes logs to the live WSL runtime root outside the repo working tree.
- `live/Twills.log` is truncated on each real Twills client login, not on normal zoning.
- `archive/Twills-YYYYMMDD-HHMMSS.log` is created for each login session and keeps the same action lines for later analysis.
- The logger attaches to every active Trust it sees through normal Trust magic, `!trustparty status`, `!trustparty repair`, and the Mochirii Trust QA summon helper. It records spell start/use/interruption/exit, ability start/use/exit, weapon skill start/exit, logical rest start/stop/tick, and target changes from `COMBAT_TICK`.
- `live/Twills-resting.tsv` is rewritten as Trust rest state changes. XivParty reads this file and shows the rest marker only while the corresponding Trust is logically resting.
- Each action row includes Alter Ego Point ranks and Unity parity fields (`aep_*`, `unity_parity_*`) so summon-time stat upgrades can be verified alongside combat behavior.
- C++ action/result logging records melee, ranged, spells, abilities, weapon skills, mobskills, result resolution, message IDs, critical/miss/no-effect state, targets, target/result counts, distance to master/current target/packet target, role-enmity action, gambit context, AEP ranks, and Unity parity.
- Local report generation resolves known action names such as `Utsusemi: Ichi`, `Blade: Rin`, `Monberaux Mix: Panacea-1`, and Amchuchu Vallation/Valiance messages from local data and report overrides.
- Buff and debuff maintenance must use `STATUS_MISSING_OR_EXPIRING` or `CASTER_STATUS_MISSING_OR_EXPIRING`. The refresh window is duration-based: effects up to 60 seconds refresh in the last 5 seconds, effects up to 180 seconds in the last 15 seconds, effects up to 600 seconds in the last 30 seconds, and longer effects in the last 60 seconds.
- `tools\mochirii\trust_parity_audit.ps1` generates the canonical post-fight report under `C:\Users\xtyty\Documents\FFXI-Runtime\reports`. Review unresolved names, runtime action issues, distance diagnostics, role-enmity decisions, alliance support scope, active effects, entity effect state, and potential early buff/debuff refreshes after every combat test.
- 2026-06-25 post-guard report snapshot: `C:\Users\xtyty\Documents\FFXI-Runtime\reports\trust-parity-audit-20260625-015612.md` shows 122 local Trust scripts, 24 explicit profiles, 98 generated audit profiles, 17 active Trusts, no unresolved log names, no runtime action issues, no TP skill guard skips, no confirmed early buff/debuff refreshes, and `tank_assist` only on Amchuchu/August/Valaineral after `summonqa` waited for all expected Trusts before repairing.
- LuaJIT syntax validation is now available locally. Use `luajit -bl` on Mochirii custom Lua before runtime testing.
- When testing caster sustain, look for `rest_start` after combat ends with low MP, rising `trust_mpp` values on later action rows, and `rest_stop` before movement or renewed engagement.

## Expansion Rules

1. Add one Trust at a time.
2. Start from official Final Fantasy XI and BG Wiki behavior, then compare against the local `scripts/actions/spells/trust/*.lua`, `mob_spell_lists`, `mob_skill_lists`, and `mob_pools` rows.
3. Prefer existing Mochirii gambit patterns from similar Trusts before inventing new conditions.
4. Only add spells/abilities that exist locally and can be executed through supported Trust controller paths.
5. Do not call PC-only gear, inventory, merit, or mission APIs from Trust code unless the binding is already proven safe for non-PC entities.
6. Document any conservative behavior that needs in-client verification before widening it.
7. Trusts should become faithful, player-like versions of their retail alter egos. If adding a normal player job/subjob tool that is not retail-observed for that Trust, label it as a Mochirii player-like extension and keep it conservative until in-client testing proves it safe.
8. Every Trust script under `scripts/actions/spells/trust` should have a parity profile row, audit status, implemented-safe action list, and deferred unsupported-action notes before it is considered complete.
