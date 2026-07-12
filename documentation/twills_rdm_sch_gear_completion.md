# Twills RDM/SCH Gear And Completion Manifest

This document records the local, repeatable Twills bootstrap choices for the
Mochirii admin character. The goal is a retail-shaped Red Mage/Scholar QA
character that uses Mochirii-supported APIs and item data instead of direct
blob fabrication.

The Git-safe portable restore snapshot for Twills is
`restore/manifests/twills-state.redacted.json`. The complete restorable Twills
account and character state is preserved only through the encrypted `xidb`
artifact referenced by `restore/manifests/database-backup.manifest.json`; do not
commit plaintext account rows, password hashes, runtime logs, screenshots, or
database dumps.

## Source Basis

- Mochirii local APIs: `player:addItem`, `completeQuest`, `addMission`,
  `completeMission`, `addKeyItem`, `setFame`, and the C++ `twills_admin` DB
  bridge.
- Mochirii local tables: `item_basic`, `item_equipment`, `item_mods`,
  `augments`, `char_profile`, `char_storage`, `chars`, `char_inventory`, and
  packed mission/quest/key item blobs.
- RDM gear source guidance, in priority order:
  - Local Mochirii tables and Twills inventory/augment rows are authoritative for what can be equipped and what has stats.
  - https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets/Red_Mage
  - https://www.bg-wiki.com/ffxi/Community_Red_Mage_Guide
  - https://www.bg-wiki.com/ffxi/Red_Mage
  - https://www.ffxiah.com/
  - https://www.ffxiah.com/forum/topic/55398/anything-you-can-do-i-can-do-better-rdm-guide/
  - FFXIAH is used for current community discussion, item pages, availability, and augment sanity checks; pricing and popularity are not treated as BIS proof without local Mochirii stat support.
- Job point, Refresh III, and Master Level source guidance:
  - https://www.bg-wiki.com/ffxi/Job_Points
  - https://www.bg-wiki.com/ffxi/Red_Mage_Job_Points
  - https://www.bg-wiki.com/ffxi/Refresh_III
  - https://forum.square-enix.com/ffxi/threads/58770
- Inventory, crafting, chocobo, and GearSwap source guidance:
  - https://www.bg-wiki.com/ffxi/Inventory_101
  - https://www.bg-wiki.com/ffxi/Category:Craft
  - https://www.bg-wiki.com/ffxi/Category:Chocobo_Raising
  - https://docs.windower.net/addons/gearswap/
  - https://docs.windower.net/addons/gearswap/reference/
- Mission and quest source guidance:
  - https://www.bg-wiki.com/ffxi/Category:Missions
  - https://www.bg-wiki.com/ffxi/Category:Quests
  - https://www.bg-wiki.com/ffxi/Category:Rhapsodies_of_Vanadiel_Missions

## Implemented Repair Entry Points

- `modules/custom/lua/twills_admin_bootstrap.lua`
  - Boot version: `8`.
  - Runs automatically for `Twills` when `TwillsBootVersion < 9`.
  - Can be forced while Twills is online with `!twillsrepair`.
- `modules/custom/cpp/twills_admin.cpp`
  - Repairs scalar DB state that should be durable on disk: all jobs, job
    points, merits, Alter Ego points, nation ranks, fame, inventory/storage
    caps, craft ranks, guild wallets, chocobucks, fewell, nation, GM level,
    all-job Master Level 50 rows, travel unlocks, veteran currency floors,
    Sylvie Unity rank state, Cornelia Trust spell state, and Twills-only
    undefined learned-spell cleanup.
- `modules/custom/commands/twillsaudit.lua`
  - Read-only GM command for Twills. It reports `[OK]`/`[FIX]` rows for core
    RDM/SCH state, RDM job-point spell definitions, job points, merits, Alter
    Ego Points, all-job Master Levels, spellbook consistency, travel unlocks,
    veteran currencies/Unity, storage, crafts, ranks/fame, chocobo, repair
    markers, important key items, and locally represented mission/quest
    completion.
- `D:\Steam\steamapps\common\FFXINA\Windower\addons\GearSwap\data\Twills.lua`
  - GearSwap v12 profile for healer/buffer and damage/debuffer modes.
  - Uses only locally implemented item stats from this checkout's item tables.
  - Role commands now equip practical idle/engaged baselines; action-specific
    swaps still handle fast cast, cures, status removal, enhancing duration,
    Phalanx, Refresh, Hachirin-no-Obi/day/weather, Orpheus distance,
    MND/INT enfeebles, nuking/magic-burst mode, and weaponskills.
  - Live QA writes set, equipment, generated visual-model, action-family, and
    return-to-baseline evidence under `FFXI-Runtime/logs/gearswap_qa` through
    `//gs c qa all`, `//gs c qa visual`, and `//gs c qa families`.
- `D:\Steam\steamapps\common\FFXINA\Windower\addons\GearSwap\data\Twills-visual-models.lua`
  - Generated from local Mochirii `item_basic` and `item_equipment` rows by
    `tools/mochirii/gearswap_action_qa.py`; do not edit by hand.
  - Unknown visible items, missing manifests, and visible-slot `MId=0` rows are
    QA failures because they can cause invisible or invalid displayed gear.

## Gear Bundle

The v8 gear grant places gear through Mochirii's normal `charutils::AddItem` path via
the narrow `twills_admin` C++ bridge so the full kit can land in wardrobe
containers instead of overflowing the 80-slot inventory. The bootstrap first
expands inventory, Mog Safe, Mog Locker, Mog Satchel, Mog Sack, Mog Case, and
wardrobes to 80, completes Gobbiebag quest flags, and sets
`TwillsRdmSchGearVersion = 3` after a clean grant to prevent accidental
duplicate reruns.

Core weapons and offhands:
- `crocea_mors`, `daybreak`, `naegling`, `maxentius`, `bunzis_rod`,
  `tauret`, `ternion_dagger_+1`, `ammurapi_shield`, `genmei_shield`,
  `pemphredo_tathlum`, `ghastly_tathlum_+1`, `staunch_tathlum_+1`,
  `regal_gem`, and `sapience_orb`.

Armor and role sets:
- Melee/defense: full `malignance_*`, full `nyame_*`, full `ayanmo_*_+2`,
  `carmine_greaves_+1`, and `chironic_hose`.
- RDM JSE, highest locally implemented:
  - `atrophy_*_+3`.
  - `lethargy_*_+2`; `+3` rows exist but have no `item_mods` locally.
  - `vitiation_chapeau_+3`, `vitiation_tabard_+2`,
    `vitiation_gloves_+2`, `vitiation_tights_+2`, `vitiation_boots_+3`;
    several `+3/+4` rows exist but have no local `item_mods`.
- Casting and support sets: full `agwus_*`, `bunzis_*`, `jhakri_*_+2`,
  `amalric_*_+1`, `kaykaus_*_+1`.

Accessories:
- `duelists_torque_+2`, `incanters_torque`, `anu_torque`,
  `baetyl_pendant`, `loricate_torque_+1`, `fotia_gorget`,
  `orpheuss_sash`, `hachirin-no-obi`, `sailfi_belt_+1`, `carriers_sash`,
  `bishops_sash`, `olympus_sash`, `acuity_belt_+1`, `sroda_belt`,
  `yemaya_belt`, `fotia_belt`, two `stikini_ring_+1`,
  `metamorph_ring_+1`, `sironas_ring`, `prolix_ring`, `archon_ring`,
  `kishar_ring`, `freke_ring`, `sroda_ring`, two `chirich_ring_+1`,
  `ilabrat_ring`, `epaminondass_ring`, `moonlight_ring`, `defending_ring`,
  `regal_earring`, `malignance_earring`, `sherida_earring`,
  `etiolation_earring`, `mendicants_earring`, `andoaa_earring`,
  `beatific_earring`, `snotra_earring`, `dignitarys_earring`,
  `telos_earring`, `friomisi_earring`, `lugalbanda_earring`,
  `mimir_earring`, `weatherspoon_ring_+1`, `coiste_bodhar`, and
  `pukulatmuj_+1`.

Skipped or not used in GearSwap because this checkout currently has no
meaningful `item_mods` for them:
- `forfend_+1`, `embla_sash`, `meili_earring`, `dedition_earring`,
  `pixie_hairpin_+1`, `moonshade_earring`, and `leyline_gloves`.

## GearSwap Modes

The local Windower profile autoloads GearSwap and uses `Twills.lua` v12.

- `//gs c healer` or `//gs c buffer`
  - Healer/buffer bias: idle DT/refresh, fast cast, cure potency, enhancing
    duration, barspells, Phalanx, Refresh, Haste, Stoneskin, Aquaveil, and
    Regen support.
- `//gs c damage` or `//gs c debuffer`
  - Damage/debuffer bias: enfeebling magic accuracy/potency, elemental nuking,
    magic burst style casting, Sanguine Blade, Savage Blade, Black Halo, TP,
    and defensive engaged sets.
- `//gs c idle`
  - Reports the active mode and re-equips the current idle/engaged set.

## XIVHotbar v11 Layout

The RDM battle hotbars are redesigned around practical RDM/SCH play:

- Row 1: GearSwap modes, idle toggles, weapon modes, validation, and status.
- Row 2: core Red Mage debuffs, Dispel, and crowd-control spells.
- Row 3: nuke mode, elemental nukes, weapon skills, and attack.
- Row 4: Scholar Arts, Addenda, and stratagems available through the ML50 support-job cap.
- Row 5: Red Mage job abilities, Sublimation, Refresh III, Haste II, Phalanx II, Temper II, Aquaveil, and Stoneskin.
- Row 6: Cure, Regen, Reraise, Erase, and status-removal recovery.

General field hotbars retain travel, Trust QA, audit/repair, addon reload, screenshot QA, and utility commands.

## Exhaustive GearSwap QA

Twills RDM/SCH coverage is now verified by two complementary checks:

- Static resolver: `python3 tools/mochirii/gearswap_action_qa.py --repo-root .`
  - Enforces the Git-safe BIS family contract in `restore/manifests/twills-rdm-sch-bis-matrix.json`.
  - Loads the Git-safe `restore/windower-golden-state/addons/GearSwap/data/Twills.lua` profile through LuaJIT with GearSwap-compatible stubs.
  - Models GearSwap `set_combine` and `equip` precedence the same way Windower documents it: later/right-most slot values win.
  - Generates a local RDM/SCH action matrix from `sql/spell_list.sql`, `sql/abilities.sql`, `sql/weapon_skills.sql`, and Twills GearSwap utility commands.
  - Filters non-player Trust summon spells and non-RDM/SCH magic so the matrix remains scoped to Twills as RDM/SCH 99/59.
  - Treats `range=empty` as a valid intentional slot, while ignoring overlay-only tables such as `sets.weapons.*`, `sets.utility.*`, `sets.role.*`, and `sets.gearscore.*`.
  - Fails if any final action phase has missing equip slots, unknown Windower resource names, missing inventory evidence from the latest Twills audit, or unsupported active items.
  - Writes JSON and Markdown evidence under `/home/xartyzx/projects/FFXI-Runtime/logs/gearswap_qa/`, which must not be committed.

- Live GearSwap QA: `//gs c qa all`
  - Writes `C:/Github Repo's/FFXI/Runtime/logs/gearswap_qa/Twills-live-sets.tsv`.
  - Writes `C:/Github Repo's/FFXI/Runtime/logs/gearswap_qa/Twills-live-equipment.tsv`.
  - Use `//gs c qa status` to print the static and live QA evidence paths in chat.
  - Use `//gs c qa snapshot` when only the current equipment snapshot is needed.

Acceptance for GearSwap changes:

- `0` static harness failures.
- `0` non-informational missing-slot rows.
- `0` missing inventory items and `0` unknown Windower resources in the latest Twills audit.
- `//gs validate sets`, `//gs validate inv`, `//gs c qa all`, `//gs c status`, and `//gs c gearscore` all run without fresh Lua errors.
- Native Windower screenshots, not OS screenshots, are used for any game-client UI proof.

## Augment Policy

Applied through supported standard exdata:
- Four `sucelloss_cape` variants:
  - Enfeebling: MND+30, Mag. Acc./Mag. Dmg.+20, Fast Cast+10.
  - TP: DEX+30, Accuracy/Ranged Accuracy+20, Attack/Ranged Attack+20,
    Dual Wield+10.
  - Weapon skill: STR+30, Accuracy/Ranged Accuracy+20,
    Attack/Ranged Attack+20, Weapon Skill Damage+10%.
  - Nuking: INT+30, Mag. Acc./Mag. Dmg.+20, Mag. Atk. Bns.+10.
- Five `telchine_*` variants with Enhancing Magic Effect Duration+10.

Applied through Mochirii bundled augment exdata:
- `crocea_mors`: Path C, rank 25.
- `duelists_torque_+2`: Dynamis-D rank 25.
- Full `nyame_*` armor set: Path B, rank 30.

Not yet auto-applied:
- Any `+4` RDM JSE pieces with zero local `item_mods`. They are not granted
  until the local item implementation catches up.

## Storage And Retail Utility Gates

The v9 repair keeps the visible GM icon hidden while preserving `gmlevel = 5`.
Storage and access gates are repaired through local APIs and the narrow C++
bridge:

- Inventory, Mog Safe, Mog Locker, Mog Satchel, Mog Sack, Mog Case, and
  Wardrobes 1-8 are raised to 80 where supported by the current schema.
- Gobbiebag I-X are completed through the Jeuno quest log.
- Mog Locker is unlocked, set to all-areas access, and granted a long lease.
- Essential key items include airship/Kazham/Aht Urhgan/Adoulin access,
  Chocobo License, Trainer's Whistle, Mog Garden access, Trust permits,
  Rhapsodies gates, map/warp/mount helpers, and `CIPHER_BRACELET`.
- Completion titles that exist in this checkout are added through title APIs;
  unsupported title/content state is documented instead of raw fabricated.

## Professions

The v9 repair follows retail-shaped craft limits:

- Alchemy: 110 Expert.
- Fishing: 110 Expert.
- Synergy: 80 Artisan.
- Woodworking, Smithing, Goldsmithing, Clothcraft, Leathercraft, Bonecraft, and
  Cooking: 70 Craftsman.

Both `char_skills.value` and `char_skills.rank` are repaired. Guild wallets,
fewell, and chocobucks are also filled for local QA. Practical profession tools
are placed through the item path, including Ebisu +1, Lu Shang +1, common
lures, Alchemy apron/torque/stall, and support-craft aprons/torques/stalls.

## Custom Chocobo

The v9 repair registers a custom field chocobo and raised-chocobo record:

- Name: `Mochi Galloper`.
- Color: black.
- Adult raised stage at the Southern San d'Oria stable.
- Top local strength and endurance values, high discernment/receptivity, high
  affection/satisfaction, full energy, no negative conditions.
- Abilities: Gallop and Canter.
- Field registration uses black color with large talons, full tail, and large
  beak traits.

## Mission And Quest Completion

The v9 repair completes only content represented in local Mochirii mission,
quest, Assault, RoE, key-item, title, zone-visitation, and learned-weapon-skill
APIs. Unsupported systems such as Campaign mission progression and deeper Sortie
clear state are reported explicitly instead of raw blob fabrication.

Mission handling:
- For mission logs with normal completed bits, the repair adds and completes
  every local mission ID.
- For CoP and later expansion entries that use current-mission progression
  semantics, the repair advances the log to the terminal/current marker. CoP
  cannot go beyond local `MAX_MISSIONID - 1`, so `THE_LAST_VERSE` remains the
  terminal marker while earlier CoP progression is treated as complete.
- Assault and Campaign are skipped because those logs are separate systems, not
  normal story mission logs.

Quest handling:
- The repair completes every quest ID represented in `xi.quest.id` with an ID
  below the local `MAX_QUESTID`.
- Rewards that are not automatic from `completeQuest` are handled separately
  where they matter for admin QA, such as Gobbiebag capacity, maps, warps,
  mounts, spells, trusts, and progression key items.

Progression gates:
- All three nation ranks are set to 10, with San d'Oria as Twills' active
  nation.
- Standard fame areas are set to the local level-9 threshold value. Abyssea fame
  areas are set to the local level-6 cap used by Mochirii's `setfamelevel` command.
- Key access items include airship/Kazham/Aht Urhgan/Adoulin/Rhapsodies/Trust
  gates that normal completed progression should leave available.

## Verification Checklist

After rebuild and relog:
- Run `!twillsrepair` once if auto-bootstrap did not fire.
- Before accepting any in-client result, foreground the `Twills`/xiloader
  window and capture a Windower-native screenshot with
  `tools\mochirii\capture_windower_window.ps1`. Do not use OS-level screenshots
  for Twills verification, and do not treat command-send success alone as
  verification.
- Confirm inventory, Mog Safe, Mog Locker, Mog Satchel, Mog Sack, Mog Case,
  and Wardrobes 1-8 are 80 and gear appears.
- Confirm Mog Locker all-areas access, Mog Garden access, and mount/chocobo
  access.
- Confirm RDM99/SCH support job menu access still works in Mog House.
- Confirm Scholar is level 99 like the other jobs, while Twills' all-job
  ML50 state keeps active RDM/SCH at the retail support cap of 99/59.
- Confirm `Combat Skills` and `Magic Skills` Alter Ego Points show 50/50.
- If `Magic Skills` still shows 0/50, first confirm Twills has `AlterEgoPoints_MagicSkills = 50` in `char_vars`, then confirm the rebuilt map executable includes the current `0x08e_alter_ego_points` display-slot fix: Combat Skills is serialized to visible row `0`, Magic Skills to visible row `1`, while the client command category mapping still accepts `17`.
- Confirm San d'Oria, Bastok, and Windurst ranks are 10 in the profile.
- Confirm Alchemy 110, Fishing 110, Synergy 80, and all other synthesis crafts
  70 with matching ranks.
- Confirm the black Gallop/Canter chocobo is available from the stable/mount
  path where the local client exposes it.
- Open mission and quest logs to check completed categories that the client
  exposes.
- Equip Crocea Mors/Ammurapi Shield and at least one Sucellos cape to verify
  augmented item display.
- Inspect Crocea Mors, Duelist's Torque +2, and every Nyame piece after relog
  to confirm the bundled augment text renders correctly in-client.
- Run `//gs reload`, `//gs c healer`, and `//gs c damage`; use GearSwap's
  validation output to catch missing local item names before combat QA.

## 2026-07-08 v9 Long-Time Content Verification

- `TwillsBootVersion = 9`; `TwillsRdmSchGearVersion = 3`; `gmlevel = 5` remains the intentional hidden-admin QA exception.
- Fresh compact in-client `!twillsaudit` proof shows `Native DB audit: 22 OK, 0 FIX` and `Long-time content audit: 13 OK, 0 FIX`.
- Direct DB/runtime evidence is stored outside Git at `FFXI-Runtime/audits/twills-v9-longtime-audit-latest.json` and `.md`; native Windower screenshot proof is stored under `FFXI-Runtime/screenshots/`.
- Abyssea: locally defined Atma `145/145`, Abyssite `110/110`, and Lunar Abyssite `3/3` are present through supported `addKeyItem` paths.
- Escha/Odyssey/Ambuscade/Dynamis gates: `TRIBULENS`, `RADIALENS`, Eschan KIs, Reisenjima Sanctorium orb, `MOGLOPHONE`, all three `MOGLOPHONE_II` KIs, both Ambuscade primers, and all local CoP Dynamis slivers are present.
- Progression bitsets after the v9 pass: Assault `52` bits, stable Records of Eminence `429/429` through API audit, claimed Deeds `99`, titles `1094`, zones `296`, and active learned weapon skills `63`.
- Campaign progression remains explicitly unsupported locally because the Campaign mission table is intentionally empty; the repair does not fabricate raw campaign blob state.
- Sortie progression remains currency-backed and explicitly unsupported for deeper clear state because the current local key-item/progression enum does not expose a durable Sortie completion model.

## 2026-06-23 Local Verification

- `TwillsBootVersion = 9` and `TwillsRdmSchGearVersion = 3` after the final
  v9 repair pass.
- `chars.gmlevel = 5` while the visible GM icon/nameflag is off in-client.
- Main Red Mage and Scholar job rows are level 99; every job is locally stored
  as Master Level 50 in `char_master_levels`, so active RDM/SCH is expected to
  display and function at 99/59 after relog.
- All 22 job-point rows have 500 unspent points, 2100 spent points, and all ten
  local categories at rank 20.
- RDM's 2100 spent JP state is intentional. The 550 JP gift tier unlocks
  `Addle II`, `Distract III`, and `Frazzle III`; the 1200 JP gift tier unlocks
  `Refresh III` and `Temper II`. Keeping all categories at 20/20 is the
  retail-shaped Job Master state required before Master Levels. The custom SQL
  module `modules/custom/sql/rdm_master_spells.sql` fills the missing local
  `spell_list` definitions for these RDM job-point spells; Twills still learns
  them through the normal Mochirii job-point gift/repair path.
- All 296 local merit rows are present at the maximum upgrade count defined by
  this checkout.
- All Alter Ego Point category vars are 50, including `CombatSkills` and
  `MagicSkills`, with a 1350-point wallet.
- 2026-06-24 follow-up: the DB already had `AlterEgoPoints_MagicSkills = 50`.
  The remaining 0/50 menu symptom was fixed in the outgoing Alter Ego Points
  packet by populating the visible Magic Skills row slot.
- The RDM/SCH bundle placed 99 target gear rows plus gil/utility rows through
  the Mochirii item path; four Sucellos capes and five Telchine pieces have augment
  exdata.
- Current equipped augment repairs:
  - `crocea_mors`: Path C, rank 25.
  - `duelists_torque_+2`: Dynamis-D rank 25.
- Current wardrobe augment repairs:
  - `nyame_helm`, `nyame_mail`, `nyame_gauntlets`, `nyame_flanchard`, and
    `nyame_sollerets`: Path B, rank 30.
- The original June backup paths were retired during workspace consolidation.
  Current logical and encrypted database backups live only under
  `/home/xartyzx/projects/FFXI-Runtime/backups` and
  `/home/xartyzx/projects/FFXI-Runtime/portable-restore/artifacts`.

## 2026-06-24 v8 Implementation Notes

- Historical: `TwillsBootVersion` target was `8` for this pass; current target is `9` as of 2026-07-08.
- `TwillsRdmSchGearVersion` target is now `3`.
- The C++ bridge repairs strict retail craft caps, matching craft ranks, guild
  wallets, fewell, chocobucks, locker/satchel/sack storage, and `char_pet`.
- The C++ bridge also repairs all 22 Master Level rows to ML50, travel unlock
  masks/blobs, veteran currency floors, Sylvie Unity rank 1 parity state,
  Cornelia Trust spell state, and Twills-only undefined learned-spell cleanup.
- The Lua repair now grants supported completion titles, profession tools,
  travel unlocks that have local teleport APIs, limited-time Trust repair, and
  a black Gallop/Canter chocobo through local Mochirii APIs.
- GearSwap autoload is configured in the local Windower `init.txt`; XivParty
  remains the party/alliance overlay and `xivbar` remains disabled by default.
- 2026-06-24 GearSwap client pass:
  - Backed up the previous profile as
    `C:\Program Files (x86)\Steam\steamapps\common\FFXINA\Windower\addons\GearSwap\data\Twills.lua.bak-20260624-055431`.
  - Replaced `Twills.lua` with explicit `healer/buffer` and
    `damage/debuffer` modes using only items currently present in Twills'
    inventory or wardrobes.
  - Windower log verification showed `Twills RDM/SCH GearSwap loaded`,
    `Twills GearSwap mode: damage/debuffer`, and
    `Twills GearSwap mode: healer/buffer` with no GearSwap Lua errors.
  - Follow-up correction: because Twills is RDM/SCH and does not have Dual
    Wield, the damage, nuking, and Sanguine Blade sets use `Ammurapi Shield`
    instead of offhand `Daybreak`. `Daybreak` remains the healer/buffer main
    weapon.
- The guide-preferred items listed as skipped above were intentionally omitted
  from GearSwap use because local `item_mods` are zero in this checkout.

## 2026-06-24 Read-Only DB Audit

The in-client `!twillsaudit` command is registered and ready, but the final
client command pass was blocked because Windows foreground focus was on
`LockApp` / `Windows Default Lock Screen`. The foreground guard refused to type
into the wrong surface.

Read-only DB checks matching the C++ audit helper passed:
- Core RDM/SCH: GM5, hidden GM icon state preserved separately, San d'Oria
  nation, RDM/SCH active as `99/59`, RDM level 99, Scholar level 99, and RDM
  Master Level 50.
- Job Points: all 22 jobs have 2100 spent JP, 500 held JP, and all ten local
  JP categories at 20/20.
- RDM JP spells: `Addle II`, `Distract III`, `Frazzle III`, `Refresh III`, and
  `Temper II` are all learned, and all five now have local `spell_list`
  definitions.
- Merits: all 296 local merit rows are at the implemented maximum upgrade
  count.
- Alter Ego Points: wallet is 1350 and all 11 categories, including Combat
  Skills and Magic Skills, are 50/50.
- Storage: inventory, Safe, Locker, Satchel, Sack, Case, and Wardrobes 1-8 are
  all 80.
- Professions: Fishing 110, Alchemy 110, Synergy 80, and the other synthesis
  crafts at 70 with matching local ranks.
- Ranks/fame: San d'Oria, Bastok, and Windurst rank 10; major fame values are
  set to the local cap value.
- Chocobo: black adult chocobo with max strength/endurance, Gallop + Canter,
  and no negative conditions.
- Historical repair markers: boot v8, gear v3, and `TrustEngageType = 1`; current repair marker is boot v9.

## 2026-06-24 Alter Ego Skill Display Fix

The DB/audit state was already correct for Twills, but the client initially showed
the new Alter Ego Points `Combat Skills` and `Magic Skills` rows as `0/50`.
The issue was the server-to-client display packet, not Twills' stored points:

- `char_points.alter_ego_points = 1350`.
- `AlterEgoPoints_CombatSkills = 50`.
- `AlterEgoPoints_MagicSkills = 50`.
- `!twillsaudit` reported `Alter Ego Points: wallet=1350, categories=11/11
  at 50`.

Square Enix added `Combat Skills` and `Magic Skills` to Alter Ego Points in
the May 2026 update. The `0x008E` Alter Ego Points packet uses the same
client `Kind` indexes as the `0x00C1` client upgrade command; HP/MP and stats
occupy `0x08` through `0x10`, so the skill rows must be sent in the next
kind-indexed slots rather than only in visible row slots `0/1`.

Local fix:
- `AlterEgoCategory::COMBAT_SKILLS = 17`.
- `AlterEgoCategory::MAGIC_SKILLS = 18`.
- `src/map/packets/s2c/0x08e_alter_ego_points.cpp` now populates the skill
  rows through those authoritative kind indexes and also keeps the old `0/1`
  aliases filled during the transition.

Verification completed:
- `xi_map` rebuilt successfully after the packet change.
- Mochirii restarted in Local mode with the rebuilt `xi_map.exe`.
- DB rows still show both skill categories at `50`.
- Fresh map startup has no AEP packet/module errors.

- Twills was verified in-client after relog: `Combat Skills` and `Magic Skills`
  both display as `50/50` in the Alter Ego Points menu.

## 2026-06-24 Deep Audit Priorities

Current verified strengths from the live database and latest `!twillsaudit`:

- Twills is active on the local QA account (`charid = 2`).
- Twills is active Red Mage/Scholar with `mjob = 5`, `sjob = 20`, `99/59`,
  GM5, no mentor/GM marker, San d'Oria nation, and `job_master = 1`.
- Every job is Master Level 50 in `char_master_levels`; all 22 jobs are level
  99 in `char_jobs`.
- All 22 job-point rows have 2100 spent JP, 500 held JP, and all ten local JP
  categories at 20/20.
- All 296 local merits are at their implemented maximum upgrade count.
- Alter Ego Points wallet is 1350 and all 11 stored categories are 50/50;
  the client menu now shows Combat Skills and Magic Skills as 50/50 too.
- Inventory, Safe, Locker, Satchel, Sack, Case, and Wardrobes 1-8 are all 80.
- Fishing 110, Alchemy 110, Synergy 80, and the other synthesis crafts 70 are
  present with matching ranks.
- The custom black `Mochi Galloper` chocobo is adult, high-affection, has max
  strength/endurance, and has Gallop + Canter.
- GearSwap references are backed by items currently in Twills' inventory or
  wardrobes. Apparent missing names such as `Aya. Cosciales +2` and
  `Telchine Chas.` are Windower display abbreviations for locally owned items.

V8 final refinements now implemented in code:

1. Travel and teleport repair now fills Home Points, Survival Guides, outposts,
   Runic Portals, Cavernous Maws, Campaign teleports, Abyssea confluxes,
   Adoulin waypoints, and Escha portals through local tables/APIs.
2. Veteran currency repair applies high retail-shaped floors with
   `GREATEST(current, floor)` semantics so higher existing values are preserved.
3. Unity repair sets Twills to Sylvie and seeds `unity_system` so Sylvie
   evaluates as rank 1/max for Unity-parity Trust stat logic.
4. Cornelia is learned when the limited-time Trust policy is enabled and the
   spell exists locally.
5. Twills-only learned spell rows missing from local `spell_list` are pruned.
6. Mission completion repair now checks current/completed state before adding
   mission rows, reducing old mission-current warning spam.
7. GearSwap v11 adds smarter conditional handling for Hachirin-no-Obi,
   Orpheus's Sash, enhancing-duration subsets, idle DT/refresh, enfeebling
   accuracy/potency modes, nuking/magic-burst mode, and weaponskill swaps.

Pending in-client verification after Twills logs back in:
- Run `!twillsrepair`, relog, then run `!twillsaudit`.
- Confirm the audit reports no undefined spells, Cornelia learned, all 22
  Master Level rows at ML50, Sylvie Unity rank 1, complete travel categories,
  and veteran currency floors.
- Run `//gs reload`, `//gs validate sets`, `//gs validate inv`, and `//gs c status` against the v11 GearSwap profile.

## GearSwap Visual-Model Audit

Twills GearSwap QA validates visible equipment model ids. Final action sets fail when `main`, `sub`, `head`, `body`, `hands`, `legs`, or `feet` resolve to a local equipment row with `MId=0`, because Mochirii sends `item_equipment.MId` as the rendered model id. Ammo, ranged, and accessory rows with `MId=0` are informational unless they affect a visible character model. Use `//gs c qa visual` for a live Windower snapshot under `FFXI-Runtime/logs/gearswap_qa`.
