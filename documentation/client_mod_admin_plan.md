# Mochirii Client, Mod Stack, Admin, And Trust QA Plan

This plan tracks the local Final Fantasy XI client and Mochirii GM bootstrap gates used by this branch. Runtime manifests, screenshots, downloaded archives, secrets, and database dumps live outside the repo. Current server/runtime evidence lives under `/root/projects/FFXI-Runtime` in WSL; the Windows path `C:\Users\xtyty\Documents\FFXI-Runtime` is only the small Windower launcher/screenshot trigger bridge required by the D: client.

Portable restore status is tracked separately in `documentation/portable_restore.md`
and `restore/manifests`. Use those manifests before moving Windower, XIPivot,
direct-DAT, or database backup material into Git; client files, DAT files,
downloaded mod archives, launcher binaries, logs, screenshots, and secrets remain
outside the repository.

## Source Basis

- Square Enix PlayOnline/Final Fantasy XI launcher remains the authority for official client updates and Rules and Policies prompts.
- The checked-out Mochirii source and live runtime are the authority for server process layout, xiloader compatibility, modules, SQL migrations, and in-client behavior verification.
- Windower official docs and `Windower/Lua` are the authority for Windower profile/addon behavior. Official plugin DLLs stay launcher-managed; Lua addons are the preferred extension path for QA helpers.
- XIPivot and XiView are installed only from their GitHub releases.
- XICamera is installed from Hokuten85's GitHub release asset for Windower 4 only; do not use the Ashita assets in this Windower profile.
- Ashenbubs, Amelila/RadialArcana/Kireek, and other large DAT packs must be sourced from the current author/Nexus/project pages. XIPivot remains the preferred redirection layer for texture packs. Real client DAT replacement is accepted only for layers that do not apply reliably through XIPivot, after backup, manifest, hash, Windower-native screenshot, logout, and relog verification.
- NTCore 4GB Patch, dgVoodoo2, and ReShade are compatibility experiments after DAT/UI stability, not baseline requirements.
- XIPivot's own documentation notes that some early-loaded menu/font/UI DATs cannot be redirected after Windower loads the addon. For Mochirii, that means future DAT work should prefer XIPivot first, but direct replacement is accepted for XiView/TideFont-style UI assets only with backups, hash manifests, and Windower-native foreground screenshots.

## Completed Gates

- Official client launch is healthy again after reinstall/update and manual Rules and Policies acceptance.
- Direct xiloader login was verified before Windower.
- The local Mochirii Windower profile launches xiloader with the secret JSON file under the runtime secrets folder.
- Twills was created through the normal client flow with San d'Oria as home nation.
- Twills was elevated server-side to GM5 with the visible GM marker disabled, San d'Oria rank 10, active RDM99/SCH99 with the retail Master Level support cap applied as `/SCH59`, genkai 99, all jobs unlocked, broad spells/trusts/maps/warps/mounts/attachments/weaponskills/skills bootstrap applied, and all jobs stored as Master Level 50 in `char_master_levels`.
- Twills has a versioned repair path through `modules/custom/lua/twills_admin_bootstrap.lua`, `modules/custom/cpp/twills_admin.cpp`, and `!twillsrepair`; v9 repairs `LIMIT_BREAKER`, `JOB_BREAKER`, `MASTER_BREAKER`, `HEART_OF_THE_BUSHIN`, Trust permits, Rhapsodies key items, `CIPHER_BRACELET`, GM5 privileges with no visible GM icon, all jobs Master Level 50, Scholar 99, effective RDM/SCH99/59 active state, 75 available merit points with max-merit capacity, all 296 merit rows at their table-defined maximum upgrades, all 22 job-point rows at 500 unspent JP, 2100 spent JP, all ten categories at rank 20, capped capacity points, 1350 Alter Ego Points, and all 11 Alter Ego Combat Skills, Magic Skills, HP, MP, and stat categories at rank 50.
- The v9 repair also fills retail-shaped travel unlocks, applies veteran currency floors without lowering higher values, sets Unity leader/rank parity to Sylvie rank 1, learns Cornelia when the limited-time Trust policy is enabled, prunes Twills-only undefined spell rows, and keeps repair markers at boot v9 / gear v3 / `TrustEngageType = 1`. Its long-time content pass grants locally defined Abyssea Atma/Abyssite, Escha/Odyssey/Ambuscade/Dynamis gate key items, completes local Assault and stable Records of Eminence through supported APIs, claims current Deeds bits, expands zone visitation, titles, and active learned weapon-skill state, and explicitly reports Campaign and deeper Sortie progression as unsupported by the current local schema.
- `!twillsaudit` reports the current Twills state without mutating it. It checks DB-only gates through the C++ `twills_admin` bridge and live Lua gates through supported local APIs, then prints concise `[OK]`/`[FIX]` summary rows in-client and to the map log to avoid oversized chat packets.
- Red Mage is intentionally kept at 2100 spent JP, not reduced to exactly 1200. Retail-shaped ML50 requires Job Master status, while the 550/1200 JP thresholds are gift unlock tiers. The local `modules/custom/sql/rdm_master_spells.sql` module defines missing server rows for `Addle II`, `Distract III`, `Frazzle III`, and `Refresh III` so Twills' learned RDM job-point spells can be offered and cast by the server.
- Alter Ego Points packet repair is part of the local build. The current client uses category `17` for the Magic Skills upgrade command path, while the visible `0x08e` menu payload displays Magic Skills in row slot `1`. Keep both pieces: `src/map/enums/alter_ego_points.h` preserves the command category, and `src/map/packets/s2c/0x08e_alter_ego_points.cpp` serializes Combat Skills to display slot `0` and Magic Skills to display slot `1`.
- Master Levels are locally implemented for persistent per-job level, job-info packet display, support-job cap, HP/MP/stat bonuses, and combat/magic skill bonuses. Exemplar point earning is still not implemented; capped jobs use `exemplar_points = 0` at ML50 until a full exemplar progression system is added.
- Unsupported missions and quests were not fabricated; a manifest records implemented/skipped/missing content.
- Full world/account/character backup exists at `C:\Users\xtyty\Documents\FFXI-Runtime\world-snapshots\20260622-172102`.
- Baseline visual stack is installed and verified:
  - XIPivot Windower `v0.4.7`
  - XICamera Windower 4 addon `v0.7.10`, installed from the release ZIP with GitHub-published SHA-256 verification. Local defaults are `cameraDistance = 6`, `battleDistance = 8.2`, `horizontalPanSpeed = 3`, `autoCalcVertSpeed = true`, `battleRange = 4`, and `battleRangeLocked = true`.
  - XiView `v2.5.3` widescreen was staged through XIPivot, then real-DAT replaced for working UI/master-star behavior.
  - XiView HD March 2026, TideFont, level/merit/job-point UI, mission/rank-up UI, ROM 3/25 UI, clear geo bubbles, bard notes, and selected UI DATs use the documented real-DAT fallback where XIPivot could not apply early-loaded UI assets reliably.
  - Ashenbubs textures are XIPivot-managed as a single active Prime overlay only. `AshenbubsHD-Basic` is no longer active, and `AshenbubsHD-June2026-Updates` was merged into `AshenbubsHD-Prime` on 2026-06-24. The merge backed up the 12 overwritten Prime files and hash-verified all 1,836 update files at `C:\Users\xtyty\Documents\FFXI-Runtime\mod-backups\XIPivot\ashenbubs-prime-merge-20260624-175432`.
  - Inactive Ashenbubs Basic and standalone June 2026 update folders were moved out of `Windower\addons\XIPivot\data\DATs` to `C:\Users\xtyty\Documents\FFXI-Runtime\mod-backups\XIPivot\inactive-overlays-20260624-175517` so XIPivot stays clean and cannot accidentally load both Basic and Prime.
  - The real-DAT mirror has a rollback backup at `C:\Users\xtyty\Documents\FFXI-Runtime\backups\real-client-active-dat-stack-before-apply-20260622-234443` and manifest at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-applied-20260622-234443.json`.
  - Windower Lua QA addons loaded by default through `Windower\scripts\init.txt`: `XIPivot`, `shortcuts`, `battlemod`, `DressUp`, `findAll`, `craft`, `GearSwap`, `XivParty`, `xivhotbar`, and `MochiriiScreenshotQA`. The global `Windower\settings.xml` `<autoload>` block remains intentionally empty so the profile script is the only startup source of truth.
  - Windower Lua addons installed but not autoloaded until intentionally configured include `xivbar`, `organizer`, `XICamera`, and the broader historical QA overlay set. Keep them manual unless a test specifically needs them. The official Windower `craft` addon is autoloaded for Cooking QA and merges generated Mochirii Cooking recipe overrides from the live database.
  - `GearSwap` autoloads the local `Twills.lua` RDM/SCH v10 profile with practical idle/engaged baselines and action-specific healer/buffer/damage/debuffer swaps. `XivParty` remains the active party/alliance overlay; `xivbar` is intentionally disabled by default.
  - Windower official plugin baseline in current `init.txt`: `Config` only. Add other official plugins through Windower's supported launcher/update path when a verification pass requires them.
- `C:\Users\xtyty\Desktop\Windower.lnk` is the canonical local client launch path. It targets the installed Windower executable and launches the local Mochirii profile; do not bypass it with ad hoc executable paths during QA.
- Server identity is `Mochirii`.
- Manual server control shortcuts are installed on the desktop:
  - `Start Mochirii FFXI Server (WSL).lnk` starts MariaDB and the Mochirii services through the Windows runtime bridge.
  - `Stop Mochirii FFXI Server (WSL).lnk` stops the Mochirii services and MariaDB.
  - `Open Mochirii MariaDB (WSL).lnk` opens the `xidb` MariaDB shell without enabling MariaDB autostart.
- Local same-machine QA mode remains available through the WSL runtime control scripts, but the desktop intentionally keeps one Start shortcut, one Stop shortcut, and one database shortcut.
- Windows Firewall allows the Mochirii Final Fantasy XI-facing ports/executables on all profiles. MariaDB is bound to `127.0.0.1` and has an inbound block rule so the database is not exposed publicly.
- Router/NAT still needs manual forwarding before external players can join: forward TCP `54001`, `54002`, `54230`, and `54231` to this PC's LAN address. The current LAN address observed during setup was `172.16.0.36`; use a DHCP reservation or static LAN IP before inviting testers.
- No Mochirii Startup-folder entry, scheduled task, service, or Run-key autostart is configured; server launch is manual through the desktop shortcut.
- Public-mode local testing can black-screen if the router does not support NAT hairpin to the WAN IP. Use manual Local mode for same-PC verification, and Public mode for external testers after router port forwarding.
- Current 2026-07-02 WSL/runtime verification:
  - WSL repo branch: `codex/twills-endgame-completion`, created after PR #14 was merged to `main`.
  - MariaDB is active; `mochirii-xi-connect`, `mochirii-xi-search`, `mochirii-xi-world`, and `mochirii-xi-map` are disabled/inactive until manually started.
  - Fresh Twills audit: `/root/projects/FFXI-Runtime/audits/twills-full-state-20260702-041334.md` shows 19 supported completion checks OK, 0 FIX, and 5 WARN rows for unsupported raw blobs that should not be fabricated directly; GearSwap inventory audit remains 0 missing and 0 unknown resources.
  - XIPivot collision report: `/root/projects/FFXI-Runtime/manifests/xipivot-overlay-collisions-20260702-031101.tsv`.
  - Direct DAT verification: `/root/projects/FFXI-Runtime/manifests/direct-dat-verification-20260702-031340.tsv`; XIView is fully active, XITide backups/source are preserved, and `ROM\119\51` is intentionally held by XIView to preserve the working UI/master-star baseline.
  - The Windows Windower bridge was restored at `C:\Users\xtyty\Documents\FFXI-Runtime\client-tools` with local secrets kept outside git so `C:\Users\xtyty\Desktop\Windower.lnk` can launch the Mochirii profile.
- Local downloads now include:
  - AshenbubsHD Basic and Prime November 2021 archives, plus the June 2026 Ashenbubs update pack and XITide March 2026.
  - `ALL-Dat-Mods.rar`, whose included manifest lists Amelila, RadialArcana, and Kireek zone, gear, monster, NPC, spell, and misc DAT content.
  - XiView 3.4 HD March 2026 A/B, XI menu music, geo bubble, bard note, mission/rank-up, level/merit/job point, and ROM 3/25 UI DAT packs.
  - Official utility downloads: NTCore 4GB Patch, dgVoodoo2 `2.87.2`, ReShade `6.7.3`, XIPivot Windower `v0.4.7`, and xiloader `v2.1.1`.
- `pointwatch` is installed and loaded. A local compatibility guard in `Windower\addons\pointwatch\pointwatch.lua` coerces Mochirii Exemplar/Master/point fields to numbers before its display format strings. This resolved the prior format spam while preserving the recommended progression overlay.
- Windower official plugin live verification is recorded at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-official-plugins-live-verification.json`.
- Windower addon/plugin hardening verification is recorded at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\client-mod-windower-current-state-20260624-0420.json`.
- A forced live reload of the recommended default addon stack on 2026-06-24 produced no fresh `error`, `failed`, `runtime`, or traceback lines. Evidence log: `C:\Users\xtyty\Documents\FFXI-Runtime\logs\windower-addon-reload-20260624-0417.log`.
- Current 2026-06-23 local verification after the AEP rebuild:
  - `dbtool.py update` ran twice and reported the database up to date both times.
  - MariaDB plus `xi_connect`, `xi_search`, `xi_world`, and `xi_map` started cleanly through the Mochirii control scripts.
  - Twills logged in through `C:\Users\xtyty\Desktop\Windower.lnk`.
  - Latest `xi_*` stderr logs contained only the standard admin/root privilege warning, not module/server errors. The only recent map warning that remains known is the benign duplicate-login packet warning. The prior Alter Ego category warning was resolved by the rebuild and later verified in-client from the Alter Ego Points menu.
  - Automated Windows key injection foregrounded the `Twills` window successfully, but command acceptance still requires Windower-native screenshot proof or matching server/Windower log output for the same timestamp.
- Current 2026-06-23 active-window gate update:
  - `tools\mochirii\assert_windower_foreground.ps1` returned
    `IsWindowerClient = true` for process `xiloader`, title `Twills`.
  - A read-only foreground screenshot was captured only after that gate passed:
    `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\active-windower-twills-20260623-033704.png`.
  - The screenshot shows Twills in Escha Ru'Aun with no visible GM icon; command
    injection remains blocked until the supported Windows automation bridge is
    available or commands are entered manually in the foreground client.
- Trusts are the active behavior focus for party/alliance combat testing, logging, role parity, and player-like job/subjob refinement.
- 2026-06-25 tooling and repo hygiene update:
  - Installed and verified LuaJIT, Lua, Lua Language Server, and StyLua through winget. LuaJIT is the preferred syntax-check CLI for server Lua because this checkout embeds LuaJIT-compatible semantics.
  - Verified existing Git, CMake, Ninja, clang-format 22, Python, Node, npm, and GitHub CLI installs. GitHub CLI is installed but not locally authenticated; use the GitHub connector for PR inspection unless `gh auth login` is completed.
  - Removed ignored root `.pdb`/`.ilk` debug artifacts and the stale root `windower-native-screenshot.jpg`, reclaiming about 1.49 GB without removing runnable server executables or source files.
  - GitHub connector inspection found no open recent pull requests for the authenticated user in `xartaiusx/XI-Server`. The private repository is not visible through the unauthenticated public API, so broader PR closure still requires connector support for all repo PRs or local `gh` authentication.
  - Rebuilt and restarted `xi_map`; after restart, `xi_connect`, `xi_search`, `xi_world`, and `xi_map` were all running and responsive.

## Current Safe Baseline

- Launch only through `C:\Users\xtyty\Desktop\Windower.lnk`.
- Foreground the `Twills`/xiloader window before input or screenshots.
- Treat active-window proof as a hard QA gate. Before any automated or manual
  command-entry/screenshot acceptance pass, run
  `tools\mochirii\assert_windower_foreground.ps1`. It must return
  `IsWindowerClient = true`; otherwise do not send commands, do not capture
  screenshots as evidence, and mark the client-side gate blocked until Windower
  is foregrounded.
- Treat Windower-native screenshots as the required proof for every
  client-visible check. Use `tools\mochirii\capture_windower_window.ps1` after
  the foreground guard. The helper writes a trigger file for the loaded
  `MochiriiScreenshotQA` Windower addon, which runs Windower's native
  `screenshot` command, waits for the new file under `Windower\screenshots`,
  validates that the captured image dimensions cover the live client after DPI
  scaling,
  and optionally copies that native screenshot under
  `C:\Users\xtyty\Documents\FFXI-Runtime`.
  Inspect the captured image before accepting UI, addon, menu, gear, Trust,
  point, or command-entry results.
- Do not use OS-level screenshots for in-game verification. Snipping Tool,
  Print Screen, desktop capture, `CopyFromScreen`, and cropped snippets are not
  valid Mochirii client QA evidence.
- A successful key-send script is not proof that an in-game command ran. Accept
  command verification only when a Windower-native screenshot shows the expected
  chat/UI result or the map/Windower logs show the command output for the same
  timestamp.
- Keep the real-DAT mirrored UI stack active unless rolling back from the recorded backup.
- Keep Ashenbubs textures active through one XIPivot folder only: `AshenbubsHD-Prime`, which includes the June 2026 update files. Do not re-add `AshenbubsHD-Basic` or a separate `AshenbubsHD-June2026-Updates` overlay.
- Keep XIPivot installed and preferred for future texture overlay experiments, but do not assume UI/master-star DATs apply through XIPivot without in-client proof.
- The current active XIPivot overlay list is `Mochirii-GeoBubblesClear`, `Mochirii-BardNotesHD`, `Mochirii-LevelMeritJobPoints`, `Mochirii-MissionRankUps`, `AshenbubsHD-Prime`, and `ALL-Dat-Mods`. A collision report from 2026-07-02 confirms custom UI/FX overlays win over Ashenbubs Prime and the catch-all DAT pack where paths overlap.
- Keep these Windower addons loaded by `Windower\scripts\init.txt` for the current lean Mochirii QA profile: `XIPivot`, `shortcuts`, `battlemod`, `DressUp`, `findAll`, `craft`, `GearSwap`, `XivParty`, `xivhotbar`, and `MochiriiScreenshotQA`.
- `MochiriiScreenshotQA` is v1.0.1 or newer. Native screenshot requests now carry a unique id, the helper removes stale trigger files before and after capture, and the addon ignores duplicate request contents so a leftover trigger cannot create repeated screenshots.
- XivParty includes a Mochirii login-race guard in `player.lua` so early party-buff packets cannot crash the addon before per-character `Settings` is initialized.
- XivParty layout persistence is accepted only when the live settings file and the Windows runtime golden-state settings file match the on-screen layout values, then survive `//lua reload XivParty` and a desktop-Windower relaunch. For the current Twills resolution, keep party `0.765,0.815`, alliance1 `0.765,0.675`, alliance2 `0.765,0.535`, and Twills scale `0.72`; capture proof with native Windower screenshots only.
- Keep `bind sysrq screenshot jpg` in `Windower\scripts\init.txt` for manual native screenshots. Do not add `hide` to the default binding because UI/addon verification needs Windower overlays visible.
- Keep XICamera installed but manual unless camera testing is the active task; when enabled, use conservative defaults unless verifying camera behavior specifically.
- Keep Windower plugin autoload lean. The current profile loads `Config`; add `Timers`, `FFXIDB`, `MipmapFix`, `SSOrganizer`, or `WinControl` only through Windower's supported launcher/update path when a verification pass requires them.
- Keep `Windower\settings.xml` global `<autoload>` empty. Do not re-add broad launcher-managed addon lists there; it causes duplicate startup behavior and can load disabled overlays such as `xivbar`.
- Keep `xivbar` and `organizer` installed but manual. This preserves the recommended tools without adding extra bar or inventory automation behavior to Trust QA by default.
- Keep the current Windower overlay layout readable: PointWatch/TargetInfo/Debuffed stacked on the upper-left, Scoreboard hidden unless explicitly testing it, XIVHotbar in the lower-center action area, and XivParty occupying the party/alliance area. Windower-native screenshots are the acceptance proof after any overlay move.
- Keep 4GB Patch active on `pol.exe` and `xiloader.exe`; both are currently LargeAddressAware.
- Keep dgVoodoo2 and ReShade staged but disabled. dgVoodoo2 must pass a keyboard-input regression before it becomes a default wrapper, and ReShade should remain after dgVoodoo/wrapper stability rather than part of the baseline.
- Do not echo or commit account secrets.

## Next Gates

1. GM and command-boundary QA:
   - First confirm Windower is the foreground app with
     `tools\mochirii\assert_windower_foreground.ps1`; no in-game command or
     screenshot counts as accepted without that foreground proof.
   - Capture and inspect a Windower-native screenshot after every command/menu
     verification step. If the UI is hidden, cropped, or unreadable, fix the
     client view first instead of relying only on logs.
   - Verify `!twillsrepair` repairs Twills while logged in, then relog and check Mog House job, Merit Points, Job Points, Alter Ego Points/category ranks, Trust, and master-related access gates.
   - Run `!twillsaudit` after repair/relog. Treat any `[FIX]` row as a concrete follow-up item unless it is an explicitly documented local-content limitation.

2. Trust parity and logging:
   - For the QA alliance, run `!trustparty summonqa` and wait for its completion message before running `!trustparty audit active`; `summonqa` owns the repair pass once all 17 Trusts are active. Verify `!trustparty status`, post-summon `!trustparty repair`, `!trustparty audit active`, `!trustparty audit all`, and `!trustparty audit <trust>` only after the roster is fully settled.
   - Use the Trust action logs under `C:\Users\xtyty\Documents\FFXI-Runtime\logs\trust_actions` plus Windower-native screenshots to verify every active Trust action, target, rest state, and role decision.
   - Keep Trust rest logical only. Do not reintroduce native kneel/healing animation attempts; XivParty displays the resting marker from the live Trust rest TSV.

3. Visual stack expansion:
   - Treat the real-DAT mirror as the current working baseline, not an experiment.
   - Add only one new texture, UI, audio, or wrapper layer per verification pass.
   - Use `ALL-Dat-Mods.rar` as the Amelila/RadialArcana/Kireek source pack unless a newer author/source page is explicitly selected.
   - Keep Ashenbubs organized as Prime-only in XIPivot. Merge future Ashenbubs update packs into `AshenbubsHD-Prime` with overwritten-file backups and hash manifests instead of adding Basic or update-pack overlays.
   - Prefer XIPivot for new layers; fall back to real DAT replacement only with a new backup/manifest and Windower-native foreground screenshot.

4. Compatibility wrappers:
   - Apply 4GB Patch only after backing up the exact active executable and verifying `LargeAddressAware`.
   - Add dgVoodoo2 only after DAT/UI stability, using 32-bit wrapper DLLs for Final Fantasy XI only.
   - Add ReShade last, with a clean screenshot/log rollback point.

5. RDM/SCH gear, storage, professions, and chocobo verification:
   - Run `!twillsrepair` after the v9 rebuild/relog, then verify the storage,
     profession, GearSwap, title, mission, quest, key item, and chocobo gates
     documented in `documentation/twills_rdm_sch_gear_completion.md`.
   - Keep completion state source-gated through supported local APIs and tables;
     unsupported or `.todo` content must stay listed in the manifest instead
     of fabricated through raw blobs.

## Evidence

Current WSL evidence:
- `/root/projects/FFXI-Runtime/audits/twills-full-state-20260702-041334.md`
- `/root/projects/FFXI-Runtime/manifests/xipivot-overlay-collisions-20260702-031101.tsv`
- `/root/projects/FFXI-Runtime/manifests/direct-dat-verification-20260702-031340.tsv`

Historical Windows-runtime evidence from before the WSL runtime move:
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\visual-baseline-20260622-1740.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\desktop-windower-xipivot-xiview-clean-20260622-1740.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-official-plugins-live-verification.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\expanded-xipivot-mod-stack-verified-20260622-231427.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-applied-20260622-234443.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-active-window-20260622-235044.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\active-windower-twills-20260623-033704.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\client-mod-windower-current-state-20260624-0420.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\logs\windower-addon-reload-20260624-0417.log`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-addon-profile-clean-active-window-20260624-0410.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-clean-after-error-hardening-20260624-0422.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\screenshots\overlay-verification\twills-overlay-20260624-060951.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\xicamera-install-v0.7.10-windower4.csv`
- `C:\Users\xtyty\Documents\FFXI-Runtime\screenshots\xicamera-status-20260624-180528.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\screenshots\xicamera-xipivot-status-20260624-180655.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\screenshots\native-windower-proof-20260624-182825.jpg`

## 2026-06-24 XIVHotbar Pass

- Installed `Akirane/XIVHotbar` from
  `https://github.com/Akirane/XIVHotbar.git` at commit
  `aaebbc27ec33b29f223508e5ceaa9ff920c31032`.
- Runtime source clone is kept at
  `C:\Users\xtyty\Documents\FFXI-Runtime\downloads\XIVHotbar`; the live
  Windower addon is installed at
  `C:\Program Files (x86)\Steam\steamapps\common\FFXINA\Windower\addons\xivhotbar`.
- Twills hotbar files:
  - `Windower\addons\xivhotbar\data\Twills\RDM.lua`
  - `Windower\addons\xivhotbar\data\Twills\General.lua`
- `RDM.lua` maps `//gs c healer`, `//gs c damage`, and `//gs c cycle` to
  visible buttons, then fills the remaining rows with server-supported RDM/SCH
  cures, buffs, enfeebles, nukes, weapon skills via native `/ws`, and RDM/SCH
  abilities.
- XIVHotbar is mouse-clickable by default. Layout/icon dragging is deliberately
  gated behind `//htb move`; run `//htb move` again to lock and save positions.
- Current layout keeps XIVHotbar lower-center, away from chat/tracker panels on
  the left and the XivParty party/alliance area on the right. Final foreground
  screenshot evidence:
  `C:\Users\xtyty\Documents\FFXI-Runtime\screenshots\overlay-verification\twills-overlay-20260624-060951.png`.
