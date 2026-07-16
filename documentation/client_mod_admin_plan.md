# Mochirii Client, Mod Stack, Admin, And Trust QA Plan

This plan tracks the local Final Fantasy XI client and Mochirii GM bootstrap gates used by this branch. Runtime manifests, screenshots, downloaded archives, secrets, and database dumps live outside the repo. Current server/runtime evidence lives under `/home/xartyzx/projects/FFXI-Runtime` in WSL; the Windows path `C:\Github Repo's\FFXI\Runtime` is only the small Windower launcher/screenshot trigger bridge required by the D: client.

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
- NTCore Large Address Aware, dgVoodoo2, and ReShade are optional graphics layers outside Git. The first two are configured locally; ReShade remains on a no-effects baseline until the complete compatibility soak passes.
- XIPivot's own documentation notes that some early-loaded menu/font/UI DATs cannot be redirected after Windower loads the addon. For Mochirii, that means future DAT work should prefer XIPivot first, but direct replacement is accepted for XiView/TideFont-style UI assets only with backups, hash manifests, and Windower-native screenshots.

## Completed Gates

- Official client launch is healthy again after reinstall/update and manual Rules and Policies acceptance.
- Direct xiloader login was verified before Windower.
- The local Mochirii Windower profile launches xiloader with the secret JSON file under the runtime secrets folder.
- Twills was created through the normal client flow with San d'Oria as home nation.
- Twills was elevated server-side to GM5 with the visible GM marker disabled, San d'Oria rank 10, active RDM99/SCH99 with the retail Master Level support cap applied as `/SCH59`, genkai 99, all jobs unlocked, broad spells/trusts/maps/warps/mounts/attachments/weaponskills/skills bootstrap applied, and all jobs stored as Master Level 50 in `char_master_levels`.
- Twills repair is explicit and non-automatic. `!twillsrepair` with no arguments only prints usage; login never runs a repair. The supported operations are `core`, `metadata`, `merits`, and `currency`. Unsupported content and gear expose dry-run-only gates until exact state manifests and replacement GearSwap QA pass.
- `!twillsrepair merits` installs a legal curated profile: retail category caps for general stats/skills, Critical Hit Rate 5, Spell Interruption Rate 5, ten points per job Group 1/2, RDM Ice/Wind Magic Accuracy 5, RDM Magic Accuracy/Immunobreak Chance 5, and 25 weapon-skill points across Exenterator, Requiescat, Resolution, Shattersoul, and Last Stand. It no longer maxes every local merit row.
- `!twillsrepair currency` clamps Ballista Points to 2,000, clears the current Ambuscade cycle, and resets absent Odyssey, Sortie, and current-Limbus balances. It does not grant permanent content floors. Unverified Escha/Domain balances remain unchanged for later acquisition-path acceptance testing. `!twillsrepair metadata` applies the documented simulated 2011-07-11 / 10,000-hour QA history without changing last-login timestamps.
- `!twillsaudit` is split into `core`, `parity`, `content <key>`, `merits`, `currency`, and `gear`. The generated implementation registry classifies content as verified, partial, skeleton, absent, monthly, or unverified; enum/blob coverage alone is never reported as playable completion.
- Red Mage is intentionally kept at 2100 spent JP, not reduced to exactly 1200. Retail-shaped ML50 requires Job Master status, while the 550/1200 JP thresholds are gift unlock tiers. The local `modules/custom/sql/rdm_master_spells.sql` module defines missing server rows for `Addle II`, `Distract III`, `Frazzle III`, and `Refresh III` so Twills' learned RDM job-point spells can be offered and cast by the server.
- Alter Ego Points packet repair is part of the local build. The current client uses category `17` for the Magic Skills upgrade command path, while the visible `0x08e` menu payload displays Magic Skills in row slot `1`. Keep both pieces: `src/map/enums/alter_ego_points.h` preserves the command category, and `src/map/packets/s2c/0x08e_alter_ego_points.cpp` serializes Combat Skills to display slot `0` and Magic Skills to display slot `1`.
- Master Levels are locally implemented for persistent per-job level, job-info packet display, support-job cap, HP/MP/stat bonuses, and combat/magic skill bonuses. Exemplar point earning is still not implemented; capped jobs use `exemplar_points = 0` at ML50 until a full exemplar progression system is added.
- Unsupported missions and quests were not fabricated; a manifest records implemented/skipped/missing content.
- Full world/account/character backup exists at `C:\Github Repo's\FFXI\Runtime\world-snapshots\20260622-172102`.
- Baseline visual stack is installed and verified:
  - XIPivot Windower `v0.4.7`
  - XICamera Windower 4 addon `v0.7.10`, installed from the release ZIP with GitHub-published SHA-256 verification. Local defaults are `cameraDistance = 6`, `battleDistance = 8.2`, `horizontalPanSpeed = 3`, `autoCalcVertSpeed = true`, `battleRange = 4`, and `battleRangeLocked = true`.
  - XIView `v2.5.3` widescreen owns four backed-up direct UI DATs because master-star/menu assets load before Windower can reliably redirect them. The only stock rollback is the post-update 2026-07-14 capture.
  - XITide owns only `ROM/91/15.DAT` through `XITide-Nameplates`; XIView retains direct ownership of the conflicting `ROM/119/51.DAT`.
  - XIPivot owns normal textures, maps, and effects. Its current first-hit order is documented in `documentation/client_graphics_stack.md` and has 36,516 unique paths, 86 intentional collisions, and zero unexplained collisions.
  - Ashenbubs Prime is the primary world/equipment base. A 15-file July 2026 candidate remains isolated above Prime until soak acceptance; Basic is not active.
  - Remapster 2048 maps and the 421-file conflict-free NextGames HD selection are active. The retired `ALL-Dat-Mods` folder was archived and replaced by the 184-file `Legacy-Community-Unique` remainder.
  - Windower Lua QA addons loaded once through `Windower\scripts\init.txt`: `XIPivot`, `XICamera`, `shortcuts`, `battlemod`, `DressUp`, `findAll`, `craft`, `GearSwap`, `XivParty`, `xivhotbar`, and `MochiriiScreenshotQA`. The global `Windower\settings.xml` `<autoload>` block remains intentionally empty.
  - Windower Lua addons installed but not autoloaded include `xivbar`, `organizer`, and the broader historical QA overlay set. The official Windower `craft` addon remains autoloaded for Cooking QA.
  - `GearSwap` autoloads the local `Twills.lua` RDM/SCH v10 profile with practical idle/engaged baselines and action-specific healer/buffer/damage/debuffer swaps. `XivParty` remains the active party/alliance overlay; `xivbar` is intentionally disabled by default.
  - Windower official plugin baseline in current `init.txt`: `Config` only. Add other official plugins through Windower's supported launcher/update path when a verification pass requires them.
- `C:\Users\xtyty\Desktop\Windower.lnk` is the canonical local client launch path. It runs the tracked `tools\mochirii\Launch-Mochirii-Windower.ps1` through the runtime link, restores the verified golden state, and launches the documented `Mochirii` profile. The shortcut is marked to run as administrator because the installed Windower manifest requests elevation; approve the UAC prompt manually and do not bypass the shortcut with ad hoc executable paths.
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
- Current 2026-07-14 WSL/runtime verification:
  - Published server baseline: `main` at `f93432ff99`; the rebuilt map server reported that exact branch/SHA and reached ready state without a module error.
  - MariaDB and all four Mochirii services start only through the desktop shortcut and remain disabled for autostart.
  - XIPivot collision report: `C:\Github Repo's\FFXI\Runtime\manifests\xipivot-overlay-collisions-final-20260714-160358.json`.
  - Direct DAT verification: `C:\Github Repo's\FFXI\Runtime\manifests\xiview-direct-post-update-20260714-155354.json`; XIView owns all direct replacements and XITide is an XIPivot-only nameplate layer.
  - Native screenshots prove XIView master stars, XITide nameplates, HD world/equipment textures, Remapster runtime redirection, six visible hotbar rows, and an uncropped XivParty panel at 2560x1600.
  - The Windows Windower bridge lives at `C:\Github Repo's\FFXI\Runtime\client-tools`; persistent credentials live only under `C:\Github Repo's\FFXI\FFXI Creds` so `C:\Users\xtyty\Desktop\Windower.lnk` can launch the Mochirii profile without storing secrets in Git or runtime evidence.
- Local downloads now include:
  - XIView v2.5.3, XITide March 2026, Ashenbubs Prime/July 2026 update, NextGames HD 1.0, Remapster 2048, XICamera v0.7.10, dgVoodoo2 v2.87.3, and ReShade v6.7.3.
  - Jasmint HD and Vibrant Vana'diel remain explicitly pending authenticated Nexus downloads; they are not represented as installed.
- `pointwatch` is installed and loaded. A local compatibility guard in `Windower\addons\pointwatch\pointwatch.lua` coerces Mochirii Exemplar/Master/point fields to numbers before its display format strings. This resolved the prior format spam while preserving the recommended progression overlay.
- Windower official plugin live verification is recorded at `C:\Github Repo's\FFXI\Runtime\manifests\windower-official-plugins-live-verification.json`.
- Windower addon/plugin hardening verification is recorded at `C:\Github Repo's\FFXI\Runtime\manifests\client-mod-windower-current-state-20260624-0420.json`.
- A forced live reload of the recommended default addon stack on 2026-06-24 produced no fresh `error`, `failed`, `runtime`, or traceback lines. Evidence log: `C:\Github Repo's\FFXI\Runtime\logs\windower-addon-reload-20260624-0417.log`.
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
    `C:\Github Repo's\FFXI\Runtime\manifests\active-windower-twills-20260623-033704.png`.
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
- Use `tools\mochirii\Invoke-WindowerCommand.ps1` for routine Windower, Final
  Fantasy XI, GearSwap, addon, and GM commands. Its acknowledged UUID bridge is
  background-safe by default and must not steal focus. Use
  `-RequireForeground` only for a documented DirectInput/raw-input fallback.
- Treat Windower-native screenshots as the required proof for every
  client-visible check. Use `tools\mochirii\capture_windower_window.ps1`. The
  helper writes a trigger file for the loaded
  `MochiriiScreenshotQA` Windower addon, which runs Windower's native
  `screenshot` command, waits for the new file under `Windower\screenshots`,
  validates that the captured image dimensions cover the live client after DPI
  scaling, restores the previously active Windows application, and optionally
  copies the screenshot under `C:\Github Repo's\FFXI\Runtime`. Inspect the
  captured image before accepting UI, addon, menu, gear, Trust, point, or
  command-entry results.
- Do not use OS-level screenshots for in-game verification. Snipping Tool,
  Print Screen, desktop capture, `CopyFromScreen`, and cropped snippets are not
  valid Mochirii client QA evidence.
- A successful key-send script is not proof that an in-game command ran. Accept
  command verification only when a Windower-native screenshot shows the expected
  chat/UI result or the map/Windower logs show the command output for the same
  timestamp.
- Keep the four XIView direct UI DATs active unless rolling back from the 2026-07-14 post-update stock backup.
- Keep Ashenbubs Prime as the single base texture pack. The July 2026 candidate may stay isolated above it while under test; do not load Basic.
- Keep XIPivot installed and preferred for future texture overlay experiments, but do not assume UI/master-star DATs apply through XIPivot without in-client proof.
- Keep the active XIPivot order exactly as recorded in `documentation/client_graphics_stack.md`; every collision requires one declared first-hit owner.
- Keep these Windower addons loaded by `Windower\scripts\init.txt` for the current lean Mochirii QA profile: `XIPivot`, `XICamera`, `shortcuts`, `battlemod`, `DressUp`, `findAll`, `craft`, `GearSwap`, `XivParty`, `xivhotbar`, and `MochiriiScreenshotQA`.
- `MochiriiScreenshotQA` is v1.1.0 or newer. Native screenshot requests carry a unique id, and command requests use an atomic UUID envelope with expiry, one-command serialization, processed-ID caching, explicit mutation authorization, and success/failure acknowledgements. Leftover or duplicate requests are rejected rather than replayed.
- XivParty includes a Mochirii login-race guard in `player.lua` so early party-buff packets cannot crash the addon before per-character `Settings` is initialized.
- XivParty layout persistence is accepted only when the live settings file and the Windows runtime golden-state settings file match the on-screen layout values, then survive `//lua reload XivParty` and a desktop-Windower relaunch. At 2560x1600, use the tracked `mochirii_xiv` layout with bottom anchoring at party `0.88,0.985`, alliance1 `0.88,0.853`, alliance2 `0.88,0.808`, and Twills scale `0.72`. Its right-aligned 32-icon buff grid stays inside the panel, allowing the main panel to replace the native party region while the alliance panels stack upward with consistent 12-pixel gaps and no cropping.
- XIVHotbar's 2560x1600 baseline is X `1114`, `HotbarSpacing=56`, and bottom-up Y positions `1512`, `1456`, `1400`, `1344`, `1288`, and `1232`. With the addon's 40-pixel slots, this keeps all six rows evenly spaced with a 48-pixel bottom safety margin and 16-pixel clear gaps.
- Keep `bind sysrq screenshot jpg` in `Windower\scripts\init.txt` for manual native screenshots. Do not add `hide` to the default binding because UI/addon verification needs Windower overlays visible.
- Keep XICamera v0.7.10 autoloaded once with its verified conservative settings; the prerelease remains disallowed unless stable fails to load initial settings.
- Keep Windower plugin autoload lean. The current profile loads `Config`; add `Timers`, `FFXIDB`, `MipmapFix`, `SSOrganizer`, or `WinControl` only through Windower's supported launcher/update path when a verification pass requires them.
- Keep `Windower\settings.xml` global `<autoload>` empty. Do not re-add broad launcher-managed addon lists there; it causes duplicate startup behavior and can load disabled overlays such as `xivbar`.
- Keep `xivbar` and `organizer` installed but manual. This preserves the recommended tools without adding extra bar or inventory automation behavior to Trust QA by default.
- Keep the current Windower overlay layout readable: PointWatch/TargetInfo/Debuffed stacked on the upper-left, Scoreboard hidden unless explicitly testing it, XIVHotbar in the lower-center action area, and XivParty occupying the party/alliance area. Windower-native screenshots are the acceptance proof after any overlay move.
- Keep the post-update `pol.exe` Large Address Aware result verified. Recheck after every official update.
- Keep the installed dgVoodoo2 v2.87.3 configuration on D3D11 feature level 11.0, 2048 MB VRAM, 16x AF, and 4x MSAA; Windower supersampling stays disabled. ReShade v6.7.3 remains injected with zero enabled techniques until wrapper login, keyboard, zoning, Mog House, combat, cutscene, relog, and soak acceptance is complete.
- Do not echo or commit account secrets.

## Next Gates

1. GM and command-boundary QA:
   - Submit routine commands through the acknowledged background bridge. Require
     explicit `-RequireForeground` only for a documented foreground-only
     DirectInput test.
   - Capture and inspect a Windower-native screenshot after every command/menu
     verification step. If the UI is hidden, cropped, or unreadable, fix the
     client view first instead of relying only on logs.
   - Run only the explicitly reviewed `!twillsrepair <operation>` command while Twills is logged in, then relog before menu verification. Never use an unqualified repair command as a mutation shortcut.
   - Run `!twillsaudit core`, `merits`, `currency`, and `parity` after repair/relog. Use `content <key>` for implementation status; unsupported content remains informational rather than falsely complete.

2. Trust parity and logging:
   - For the QA alliance, run `!trustparty summonqa` and wait for its completion message before running `!trustparty audit active`; `summonqa` owns the repair pass once all 17 Trusts are active. Verify `!trustparty status`, post-summon `!trustparty repair`, `!trustparty audit active`, `!trustparty audit all`, and `!trustparty audit <trust>` only after the roster is fully settled.
   - Use the Trust action logs under `C:\Github Repo's\FFXI\Runtime\logs\trust_actions` plus Windower-native screenshots to verify every active Trust action, target, rest state, and role decision.
   - Keep Trust rest logical only. Do not reintroduce native kneel/healing animation attempts; XivParty displays the resting marker from the live Trust rest TSV.

3. Visual stack expansion:
   - Treat XIView's four-file direct exception and the current XIPivot ownership order as the working baseline.
   - Add only one new texture, UI, audio, or wrapper layer per verification pass.
   - Keep the complete legacy community archive only as rollback evidence; active files come from the manifested `Legacy-Community-Unique` layer.
   - Keep Ashenbubs organized as Prime plus at most one isolated candidate layer under active verification.
   - Prefer XIPivot for new layers; fall back to real DAT replacement only with a new backup/manifest and Windower-native screenshot.

4. Compatibility wrappers:
   - Preserve the verified `LargeAddressAware` `pol.exe` and recheck it after every official client update.
   - Validate the installed 32-bit dgVoodoo2 D3D8 wrapper through the complete Mochirii login/zoning/soak gate.
   - Keep ReShade techniques disabled until dgVoodoo acceptance, then add one preset/effect layer at a time with a native screenshot/log rollback point.

5. RDM/SCH gear, storage, professions, and chocobo verification:
   - Run the reviewed explicit `!twillsrepair core` operation after the v9 rebuild/relog, then verify the storage,
     profession, GearSwap, title, mission, quest, key item, and chocobo gates
     documented in `documentation/twills_rdm_sch_gear_completion.md`.
   - Keep completion state source-gated through supported local APIs and tables;
     unsupported or `.todo` content must stay listed in the manifest instead
     of fabricated through raw blobs.

## Evidence

Current WSL evidence:
- `/home/xartyzx/projects/FFXI-Runtime/audits/twills-full-state-20260702-041334.md`
- `/home/xartyzx/projects/FFXI-Runtime/manifests/xipivot-overlay-collisions-20260702-031101.tsv`
- `/home/xartyzx/projects/FFXI-Runtime/manifests/direct-dat-verification-20260702-031340.tsv`

Historical Windows-runtime evidence from before the WSL runtime move:
- `C:\Github Repo's\FFXI\Runtime\manifests\visual-baseline-20260622-1740.json`
- `C:\Github Repo's\FFXI\Runtime\manifests\desktop-windower-xipivot-xiview-clean-20260622-1740.png`
- `C:\Github Repo's\FFXI\Runtime\manifests\windower-official-plugins-live-verification.json`
- `C:\Github Repo's\FFXI\Runtime\manifests\expanded-xipivot-mod-stack-verified-20260622-231427.json`
- `C:\Github Repo's\FFXI\Runtime\manifests\real-client-active-dat-stack-applied-20260622-234443.json`
- `C:\Github Repo's\FFXI\Runtime\manifests\real-client-active-dat-stack-active-window-20260622-235044.png`
- `C:\Github Repo's\FFXI\Runtime\manifests\active-windower-twills-20260623-033704.png`
- `C:\Github Repo's\FFXI\Runtime\manifests\client-mod-windower-current-state-20260624-0420.json`
- `C:\Github Repo's\FFXI\Runtime\logs\windower-addon-reload-20260624-0417.log`
- `C:\Github Repo's\FFXI\Runtime\manifests\windower-addon-profile-clean-active-window-20260624-0410.png`
- `C:\Github Repo's\FFXI\Runtime\manifests\windower-clean-after-error-hardening-20260624-0422.png`
- `C:\Github Repo's\FFXI\Runtime\screenshots\overlay-verification\twills-overlay-20260624-060951.png`
- `C:\Github Repo's\FFXI\Runtime\manifests\xicamera-install-v0.7.10-windower4.csv`
- `C:\Github Repo's\FFXI\Runtime\screenshots\xicamera-status-20260624-180528.png`
- `C:\Github Repo's\FFXI\Runtime\screenshots\xicamera-xipivot-status-20260624-180655.png`
- `C:\Github Repo's\FFXI\Runtime\screenshots\native-windower-proof-20260624-182825.jpg`

## 2026-06-24 XIVHotbar Pass

- Installed `Akirane/XIVHotbar` from
  `https://github.com/Akirane/XIVHotbar.git` at commit
  `aaebbc27ec33b29f223508e5ceaa9ff920c31032`.
- Runtime source clone is kept at
  `C:\Github Repo's\FFXI\Runtime\downloads\XIVHotbar`; the live
  Windower addon is installed at
  `D:\Steam\steamapps\common\FFXINA\Windower\addons\xivhotbar`.
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
  the left and the XivParty party/alliance area on the right. Current native
  full-client evidence is recorded in
  `C:\Github Repo's\FFXI\Runtime\manifests\windower-ui-layout-current.json` and
  `C:\Github Repo's\FFXI\Runtime\screenshots\xivparty-bottom-anchor-alliance-20260716.jpg`.
