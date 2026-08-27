# Mochirii Trust Retail Parity

## Goal

Trusts should be as close to player-like retail behavior as this Mochirii checkout can safely support. Each Trust keeps its own identity, role, movement style, TP behavior, and special quirks, but Mochirii may fill in safe job/subjob tools when the user preference is "as close to a player with their job/subjob as possible."

Primary references:

- Official Final Fantasy XI Trust guide: Trust alter egos have distinct roles and behavior.
- BG Wiki Trust pages for observed spell, ability, weapon skill, and special-feature behavior.
- Local Trust controller and existing Trust spell scripts for supported movement, gambit, casting, and TP behavior.

## Evidence Lanes And Alliance Capability

Retail control remains the default behavior: one player and no more than five
Trusts in one party, with upstream party-size, Rhapsodies, duplicate, zone,
battlefield, leader, and enmity gates intact. Twills' 17-Trust alliance is a
permanent Mochirii QA capability, not retail behavior and never retail
acceptance.

The full-alliance capability is active only when all of these are true:

- `ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE = true` and
  `MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES = 3`;
- the character is exactly `Twills`, actual GM level is exactly `5`, visible GM
  level is `0`, and `MochiriiTrustAllianceAccess=1` is persisted;
- the explicit `twills_full_alliance_qa` session is in `spawning` or `ready`.

The shared C++ predicate owns that decision for direct spawning, party reloads,
packets, Lua, and Trust AI. Direct Lua spawning cannot bypass the ordinary
six-member limit, and a ready QA roster is locked against additional summons.
Virtual indices `0-17` map to parties `0-2`, slots `0-5`; index `18` and above
is rejected rather than masked or clamped.

Mochirii-only defensive scanning, shared targeting, role-enmity injection,
combat resting, Unity-wide bonuses, and custom engagement behavior are gated by
the active QA predicate. Retail-control mode restores upstream controller
behavior. Alter Ego Point bonuses remain available in both lanes. Twills repair
grants/audits the alliance entitlement but never permanently sets
`TrustEngageType`; clear, login, logout, zoning, timeout, and failure restore it
to `0`.

Trust positioning:

- Use the local per-Trust `MOBMOD_TRUST_DISTANCE` / `xi.trust.movementType` controls first. The controller no longer infers long-range positioning from broad jobs such as COR, because Trusts like Luzaf are melee-first despite having a ranged-capable job. Luzaf now explicitly sets `xi.trust.movementType.MELEE`; ranged/support Trusts should be handled with their own script-level movement setting.

Windower QA overlay:

- XivParty is loaded from Windower's `scripts/init.txt` and configured through `Windower/addons/XivParty/data/settings.xml`, matching the addon's install/load/settings model.
- The current 2560x1600 `mochirii_xiv` layout uses `alignBottom=true`: party `0.88,0.985`, alliance1 `0.88,0.853`, alliance2 `0.88,0.808`, with Twills scale `0.72`. The main panel replaces the native party region, its right-aligned buff grid keeps all 32 icons inside the panel, and the smaller alliance panes stack upward at consistent 12-pixel gaps without cropping. If resolution changes, adjust through `//xp setup` or the settings file, mirror the live, runtime-golden, and tracked-restore copies, then verify both solo and full-alliance states after `//lua reload XivParty`.
- The current default Windower QA addon stack is intentionally lean and loaded exactly once from `Windower\scripts\init.txt`: `XIPivot`, `XICamera`, `shortcuts`, `battlemod`, `DressUp`, `findAll`, `craft`, `GearSwap`, `XivParty`, `xivhotbar`, and `MochiriiScreenshotQA`. The official plugin baseline currently loaded by startup is `Config`, with `LuaCore` as the addon runtime. Do not document or re-enable larger addon/plugin stacks unless they are installed, active, and verified in the live client.
- Submit normal commands through `C:\Github Repo's\FFXI\Runtime\client-tools\Invoke-WindowerCommand.ps1`; its acknowledged UUID bridge runs without stealing foreground focus. Pass `-AllowMutation` only for a deliberately reviewed mutating GM command, and use `-RequireForeground` only for a documented DirectInput fallback. Screenshots count as evidence only when `capture_windower_window.ps1` triggers Windower's native screenshot, reports full client dimensions, and restores the previously active window.
- Pre-combat readiness order is explicit and lane-isolated: load/reload the UI,
  run `!trustparty summonretail`, wait for `ready`, inspect `!trustparty mode`,
  capture native proof, and run the Python audit with `--readiness-only`; then
  `!trustparty clear` and repeat with `!trustparty summonqa`. Clear again before
  shutdown. A readiness pass must report `combat_acceptance=not_run`; the QA
  report must also display `MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE`. Do not
  run `combattest`, engage a mob, or claim Trust parity during readiness QA.
- The 2026-07-06 report is a legacy descriptive snapshot only: it observed 17
  QA Trusts and useful action diagnostics, but predates the schema-v2 session
  contract and cannot satisfy readiness or combat acceptance.

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

- `!trustparty summonretail` starts the locked retail-control session with
  Valaineral, Yoran-Oran (UC), Ulmia, Lilisette II, and Shantotto II.
- `!trustparty summonqa` starts the Twills-only alliance session with exact
  Trust-party counts `5/6/6`: August, Yoran-Oran (UC), Koru-Moru, Qultada, and
  Cornelia; Valaineral, Monberaux, Joachim, Ulmia, Lilisette II, and Matsui-P;
  Amchuchu, Sylvie (UC), Apururu (UC), Shantotto II, Star Sibyl, and Selh'teus.
- Both summon commands run every preflight before changing the current roster
  or evidence log, then use a generation-bound `idle -> spawning -> ready`
  state machine. Any spawn failure, timeout, cancellation, death, login,
  logout, or zone boundary invalidates stale timers and returns fail-closed to
  idle after clearing the partial roster.
- `!trustparty clear` is idempotent, invalidates pending timers first, closes
  the evidence session, dismisses Trusts, and restores `TrustEngageType=0`.
- `!trustparty mode`, `status`, `audit`, and `composition` are read-only.
  `mode` reports authorization, state, generation, session ID, evidence lane,
  topology, exact roster, engagement type, logger state, and pending timers.
- `!trustparty repair` refreshes supported active Trust spell lists and applies
  runtime gambits but never selects a lane, rotates evidence, or changes
  engagement type. It refuses while spawning.
- `!trustparty combattest` consumes an already-ready exact roster and never
  changes the evidence lane or engagement type. It is intentionally unused
  during pre-combat readiness work.
- `!trustparty audit active`, `!trustparty audit all`, and `!trustparty audit <trust>` report profile coverage, role model, support scope, range goal, buff/debuff maintenance policy, identity rules, status, and deferred work for active Trusts or the local roster.
- Current QA alliance Trusts have explicit profile annotations for support scope, range, buff policy, and identity. The rest of the roster receives generated audit profiles so every local Trust script stays visible in audits until its source-backed parity pass is complete.
- Lua Trust scripts and module commands can hot-reload through the local file watcher, but already-summoned Trusts keep their existing gambit list. Use `!trustparty repair` for additive runtime fixes after the party is fully settled, and dismiss/resummon Qultada or Joachim to verify revised roll/song priority from a clean spawn.
- SQL-backed Trust spell lists are cached by `xi_map` at startup. Restart `xi_map` before validating newly added `mob_spell_lists` rows such as Valaineral's Banish III.
- C++ controller changes require rebuilding and restarting `xi_map`.
- Use the Windower QA command bridge for text commands only. Avoid `/attack` without a confirmed target because it can leave the client in a modal target-selection prompt where physical game-control keys appear unresponsive while chat text still works.

Trust action logs:

- `ENABLE_TRUST_ACTION_LOG = true` enables the Mochirii Trust action logger.
- `TRUST_ACTION_LOG_PLAYER = 'Twills'` is an exact, fail-closed owner gate. Only Twills' Trust party is logged; an empty value or any mismatched name disables session evidence instead of tracing other players.
- `TRUST_ACTION_LOG_DIR = '/home/xartyzx/projects/FFXI-Runtime/logs/trust_actions'` writes logs to the live WSL runtime root outside the repo working tree.
- Formal evidence is schema version 2 and session-bound. Every record carries the
  exact session ID, full server commit, evidence mode, topology, state,
  generation, strictly increasing sequence, and UTC time. Lua and C++ route by
  that exact session rather than scanning for the newest archive.
- Each explicit mode transition receives its own collision-safe archive.
  Login, logout, zoning, timeout, failure, cancellation, and clear write an
  explicit session end when possible, then rotate to idle state. Legacy logs
  remain descriptive-only and cannot satisfy readiness or combat acceptance.
- Formal summoning attaches the logger synchronously to each returned Trust and
  cannot enter `ready` unless the exact roster has exactly one attachment per
  Trust. Delayed ordinary-spell attachment retries carry the current generation
  so stale callbacks cannot contaminate a later session.
- `live/Twills-resting.tsv` is rewritten as Trust rest state changes. XivParty reads this file and shows the rest marker only while the corresponding Trust is logically resting.
- Each action row includes Alter Ego Point ranks and Unity parity fields (`aep_*`, `unity_parity_*`) so summon-time stat upgrades can be verified alongside combat behavior.
- C++ action/result logging records melee, ranged, spells, abilities, weapon skills, mobskills, result resolution, message IDs, critical/miss/no-effect state, targets, target/result counts, distance to master/current target/packet target, role-enmity action, gambit context, AEP ranks, and Unity parity.
- Local report generation resolves known action names such as `Utsusemi: Ichi`, `Blade: Rin`, `Monberaux Mix: Panacea-1`, and Amchuchu Vallation/Valiance messages from local data and report overrides.
- Buff and debuff maintenance must use `STATUS_MISSING_OR_EXPIRING` or `CASTER_STATUS_MISSING_OR_EXPIRING`. The refresh window is duration-based: effects up to 60 seconds refresh in the last 5 seconds, effects up to 180 seconds in the last 15 seconds, effects up to 600 seconds in the last 30 seconds, and longer effects in the last 60 seconds.
- `tools/mochirii/trust_parity_audit.py` is the only parser and report generator;
  the PowerShell entrypoint only forwards arguments and preserves its exit code.
  It always writes JSON and Markdown reports under the runtime root. Empty,
  malformed, stale, mixed-session, mixed-mode, wrong-commit, wrong-roster,
  readiness-only, logger-only, and progression-only evidence fails the default
  combat gate.
- `--readiness-only` validates authorization, exact roster/topology, logger
  attachment, isolation, `ready`, and summon completion. It reports
  `READINESS ONLY — NO COMBAT ACCEPTANCE`, `combat_acceptance=not_run`, and cannot
  satisfy the default combat gate. Retail and QA sessions never satisfy or
  contaminate one another.
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
