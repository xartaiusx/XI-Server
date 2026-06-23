# Twills RDM/SCH Gear And Completion Manifest

This document records the local, repeatable Twills bootstrap choices for the
Mochirii admin character. The goal is a retail-shaped Red Mage/Scholar QA
character that uses LandSandBoat-supported APIs and item data instead of direct
blob fabrication.

## Source Basis

- LandSandBoat local APIs: `player:addItem`, `completeQuest`, `addMission`,
  `completeMission`, `addKeyItem`, `setFame`, and the C++ `twills_admin` DB
  bridge.
- LandSandBoat local tables: `item_basic`, `item_equipment`, `item_mods`,
  `augments`, `char_profile`, `char_storage`, `chars`, `char_inventory`, and
  packed mission/quest/key item blobs.
- RDM gear source guidance:
  - https://www.bg-wiki.com/ffxi/Community_Red_Mage_Guide
  - https://www.bg-wiki.com/ffxi/Red_Mage
  - https://www.ffxiah.com/forum/topic/49688/jack-of-all-trades-a-guide-to-red-mage/
- Mission and quest source guidance:
  - https://www.bg-wiki.com/ffxi/Category:Missions
  - https://www.bg-wiki.com/ffxi/Category:Quests
  - https://www.bg-wiki.com/ffxi/Category:Rhapsodies_of_Vanadiel_Missions

## Implemented Repair Entry Points

- `modules/custom/lua/twills_admin_bootstrap.lua`
  - Boot version: `5`.
  - Runs automatically for `Twills` when `TwillsBootVersion < 5`.
  - Can be forced while Twills is online with `!twillsrepair`.
- `modules/custom/cpp/twills_admin.cpp`
  - Repairs scalar DB state that should be durable on disk: all jobs, job
    points, merits, Alter Ego points, nation ranks, fame, inventory/storage
    caps, nation, and GM level.

## Gear Bundle

The v5 gear grant places gear through LSB's normal `charutils::AddItem` path via
the narrow `twills_admin` C++ bridge so the full kit can land in wardrobe
containers instead of overflowing the 80-slot inventory. The bootstrap first
expands inventory and wardrobes to 80, completes Gobbiebag quest flags, and sets
`TwillsRdmSchGearVersion = 1` after a clean grant to prevent accidental
duplicate reruns.

Core weapons and offhands:
- `crocea_mors`, `daybreak`, `naegling`, `maxentius`, `bunzis_rod`,
  `tauret`, `ternion_dagger_+1`, `ammurapi_shield`, `genmei_shield`,
  `pemphredo_tathlum`, `ghastly_tathlum_+1`.

Armor and role sets:
- Melee/defense: full `malignance_*`, full `nyame_*`, full `ayanmo_*_+2`.
- RDM JSE, highest locally implemented:
  - `atrophy_*_+3`.
  - `lethargy_*_+2`; `+3` rows exist but have no `item_mods` locally.
  - `vitiation_chapeau_+3`, `vitiation_tabard_+2`,
    `vitiation_gloves_+2`, `vitiation_tights_+2`, `vitiation_boots_+3`;
    several `+3/+4` rows exist but have no local `item_mods`.
- Casting and support sets: full `agwus_*`, `bunzis_*`, `jhakri_*_+2`,
  `amalric_*_+1`, `kaykaus_*_+1`.

Accessories:
- `duelists_torque_+2`, `orpheuss_sash`, `hachirin-no-obi`,
  `sailfi_belt_+1`, `sroda_belt`, `yemaya_belt`, two `stikini_ring_+1`,
  `metamorph_ring_+1`, `kishar_ring`, `freke_ring`, `sroda_ring`,
  `ilabrat_ring`, `epaminondass_ring`, `moonlight_ring`, `defending_ring`,
  `regal_earring`, `malignance_earring`, `snotra_earring`,
  `dignitarys_earring`, `telos_earring`, `friomisi_earring`,
  `lugalbanda_earring`, `mimir_earring`.

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

Applied through LSB bundled augment exdata:
- `crocea_mors`: Path C, rank 25.
- `duelists_torque_+2`: Dynamis-D rank 25.
- Full `nyame_*` armor set: Path B, rank 30.

Not yet auto-applied:
- Any `+4` RDM JSE pieces with zero local `item_mods`. They are not granted
  until the local item implementation catches up.

## Mission And Quest Completion

The v5 repair completes only content represented in the local LSB mission and
quest enum tables.

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
  areas are set to the local level-6 cap used by LSB's `setfamelevel` command.
- Key access items include airship/Kazham/Aht Urhgan/Adoulin/Rhapsodies/Trust
  gates that normal completed progression should leave available.

## Verification Checklist

After rebuild and relog:
- Run `!twillsrepair` once if auto-bootstrap did not fire.
- Confirm inventory and wardrobes are 80 and gear appears.
- Confirm RDM99/SCH support job menu access still works in Mog House.
- Confirm `Combat Skills` and `Magic Skills` Alter Ego Points show 50/50.
- If `Magic Skills` still shows 0/50, confirm the rebuilt map executable includes `AlterEgoCategory::MAGIC_SKILLS = 17`; the current client sends category `17` for that row.
- Confirm San d'Oria, Bastok, and Windurst ranks are 10 in the profile.
- Open mission and quest logs to check completed categories that the client
  exposes.
- Equip Crocea Mors/Ammurapi Shield and at least one Sucellos cape to verify
  augmented item display.
- Inspect Crocea Mors, Duelist's Torque +2, and every Nyame piece after relog
  to confirm the bundled augment text renders correctly in-client.

## 2026-06-23 Local Verification

- `TwillsBootVersion = 5` and `TwillsRdmSchGearVersion = 1`.
- `chars.gmlevel = 5` while the visible GM icon/nameflag is off in-client.
- Main Red Mage and Scholar job rows are level 99; `/SCH` remains support-job
  capped when equipped as a subjob.
- All 22 job-point rows have 500 unspent points, 2100 spent points, and all ten
  local categories at rank 20.
- All 296 local merit rows are present at the maximum upgrade count defined by
  this checkout.
- All Alter Ego Point category vars are 50, including `CombatSkills` and
  `MagicSkills`, with a 1350-point wallet.
- The RDM/SCH bundle placed 99 target gear rows plus gil/utility rows through
  the LSB item path; four Sucellos capes and five Telchine pieces have augment
  exdata.
- Current equipped augment repairs:
  - `crocea_mors`: Path C, rank 25.
  - `duelists_torque_+2`: Dynamis-D rank 25.
- Current wardrobe augment repairs:
  - `nyame_helm`, `nyame_mail`, `nyame_gauntlets`, `nyame_flanchard`, and
    `nyame_sollerets`: Path B, rank 30.
- Backup after the current repair/gear pass:
  `C:\Users\xtyty\Documents\FFXI\sql\backups\xidb-20260623-020712-32b34.sql`.
- Backup before the bundled augment pass:
  `C:\Users\xtyty\Documents\FFXI\sql\backups\xidb-20260623-031100-32b34.sql`.
