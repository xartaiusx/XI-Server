# FFXI Client, Mod Stack, Admin, And Bot QA Plan

This plan tracks the local client and GM bootstrap gates used by this branch. Runtime manifests, screenshots, downloaded archives, secrets, and database dumps live outside the repo under `C:\Users\xtyty\Documents\FFXI-Runtime`.

## Source Basis

- Square Enix PlayOnline/Final Fantasy XI launcher remains the authority for official client updates and Rules and Policies prompts.
- LandSandBoat is the authority for server process layout, xiloader compatibility, modules, SQL migrations, and in-client behavior verification.
- Windower official docs and `Windower/Lua` are the authority for Windower profile/addon behavior.
- XIPivot and XiView are installed only from their GitHub releases.
- Ashenbubs, Amelila/RadialArcana/Kireek, and other large DAT packs must be sourced from the current author/Nexus/project pages. XIPivot remains the preferred redirection layer, but UI/master-star DATs and texture packs may be mirrored into real client files only after backup, manifest, hash, screenshot, logout, and relog verification.
- NTCore 4GB Patch, dgVoodoo2, and ReShade are compatibility experiments after DAT/UI stability, not baseline requirements.

## Completed Gates

- Official client launch is healthy again after reinstall/update and manual Rules and Policies acceptance.
- Direct xiloader login was verified before Windower.
- Windower `Local LSB` profile launches xiloader with the secret JSON file under `FFXI-Runtime\secrets`.
- Twills was created through the normal client flow with San d'Oria as home nation.
- Twills was elevated server-side to GM5 with the visible GM marker disabled, San d'Oria rank 10, RDM99 with Scholar leveled to 99 like every other job, genkai 99, all jobs unlocked, broad spells/trusts/maps/warps/mounts/attachments/weaponskills/skills bootstrap applied. The active `/SCH` display remains retail-capped by support-job rules when equipped as a subjob.
- Twills has a versioned repair path through `modules/custom/lua/twills_admin_bootstrap.lua`, `modules/custom/cpp/twills_admin.cpp`, and `!twillsrepair`; v5 repairs `LIMIT_BREAKER`, `JOB_BREAKER`, `MASTER_BREAKER`, `HEART_OF_THE_BUSHIN`, Trust permits, Rhapsodies key items, `CIPHER_BRACELET`, GM5 privileges with no visible GM icon, Scholar 99, 75 available merit points with max-merit capacity, all 296 merit rows at their table-defined maximum upgrades, all 22 job-point rows at 500 unspent JP, 2100 spent JP, all ten categories at rank 20, capped capacity points, 1350 Alter Ego Points, and all 11 Alter Ego Combat Skills, Magic Skills, HP, MP, and stat categories at rank 50.
- Alter Ego Points packet repair is part of the local build. The current client sends category `17` for the Magic Skills row, so `src/map/enums/alter_ego_points.h` maps `MAGIC_SKILLS = 17` and `0x08e_alter_ego_points` now serializes Twills' stored category ranks and next costs instead of sending zeroed arrays.
- Master Levels are treated as access-gated but not fabricated. This checkout exposes `MASTER_BREAKER`, while Exemplar/Master Level progression is still not fully implemented server-side.
- Unsupported missions and quests were not fabricated; a manifest records implemented/skipped/missing content.
- Full world/account/character backup exists at `C:\Users\xtyty\Documents\FFXI-Runtime\world-snapshots\20260622-172102`.
- Baseline visual stack is installed and verified:
  - XIPivot Windower `v0.4.7`
  - XiView `v2.5.3` widescreen was staged through XIPivot, then real-DAT replaced for working UI/master-star behavior.
  - XiView HD March 2026, TideFont, level/merit/job-point UI, mission/rank-up UI, ROM 3/25 UI, clear geo bubbles, bard notes, AshenbubsHD Basic, AshenbubsHD Prime, AshenbubsHD June 2026 updates, and `ALL-Dat-Mods` were mirrored into real client DATs because Ashenbubs was not visually applying through XIPivot.
  - The real-DAT mirror has a rollback backup at `C:\Users\xtyty\Documents\FFXI-Runtime\backups\real-client-active-dat-stack-before-apply-20260622-234443` and manifest at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-applied-20260622-234443.json`.
  - Windower Lua addons `XIPivot`, `distance`, and `TParty`
  - Windower official plugins `Config`, `Timers`, `FFXIDB`, `MipmapFix`, `SSOrganizer`, and `WinControl`
- `C:\Users\xtyty\Desktop\Windower.lnk` is the canonical local client launch path. It targets the installed Windower executable and launches the `Local LSB` profile; do not bypass it with ad hoc executable paths during QA.
- Server identity is `Mochirii`.
- Manual server control shortcuts are installed on the desktop:
  - `Start Mochirii Server.lnk` starts public mode and refreshes `zone_settings.zoneip` to the current WAN IPv4 address.
  - `Start Mochirii Server (Local QA).lnk` starts local mode and sets `zone_settings.zoneip = 127.0.0.1` for same-machine client testing.
  - `Stop Mochirii Server.lnk` stops the four LSB processes and MariaDB.
- Windows Firewall allows the Mochirii FFXI-facing ports/executables on all profiles. MariaDB is bound to `127.0.0.1` and has an inbound block rule so the database is not exposed publicly.
- Router/NAT still needs manual forwarding before external players can join: forward TCP `54001`, `54002`, `54230`, and `54231` to this PC's LAN address. The current LAN address observed during setup was `172.16.0.36`; use a DHCP reservation or static LAN IP before inviting testers.
- No FFXI/Mochirii Startup-folder entry, scheduled task, service, or Run-key autostart is configured; server launch is manual through the desktop shortcut.
- Public-mode local testing can black-screen if the router does not support NAT hairpin to the WAN IP. Use Local QA mode for same-PC verification, and Public mode for external testers after router port forwarding.
- Local downloads now include:
  - AshenbubsHD Basic and Prime November 2021 archives, plus the June 2026 Ashenbubs update pack and XITide March 2026.
  - `ALL-Dat-Mods.rar`, whose included manifest lists Amelila, RadialArcana, and Kireek zone, gear, monster, NPC, spell, and misc DAT content.
  - XiView 3.4 HD March 2026 A/B, XI menu music, geo bubble, bard note, mission/rank-up, level/merit/job point, and ROM 3/25 UI DAT packs.
  - Official utility downloads: NTCore 4GB Patch, dgVoodoo2 `2.87.2`, ReShade `6.7.3`, XIPivot Windower `v0.4.7`, and xiloader `v2.1.1`.
- `pointwatch` is installed but disabled because it produced Lua format errors against the current LSB/Twills admin state.
- Windower official plugin live verification is recorded at `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-official-plugins-live-verification.json`.
- Server bot city verification passed in Southern San d'Oria:
  - 12 active city bots
  - varied bot names
  - active heartbeat updates to `server_bot_state.last_seen`
  - audit and performance snapshots ticking under budget
- Current 2026-06-23 local verification after the AEP rebuild:
  - `dbtool.py update` ran twice and reported the database up to date both times.
  - MariaDB plus `xi_connect`, `xi_search`, `xi_world`, and `xi_map` started cleanly through the Mochirii control scripts.
  - Twills logged in through `C:\Users\xtyty\Desktop\Windower.lnk`.
  - Southern San d'Oria had 12 active autonomous city bots, zero combat bots, and `server_bot_performance_snapshots` showed `tick_elapsed_ms = 0` against a 4 ms budget.
  - Latest `xi_*` stderr logs contained only the standard LSB admin/root privilege warning, not module/server errors. The only recent map warning that remains known is the benign duplicate-login packet warning; the prior Alter Ego category 17 warning is expected to be resolved by the rebuild but should still be visually rechecked from the Mog House Alter Ego Points menu.
  - Automated Windows key injection foregrounded the `Twills` window successfully, but did not prove in-game `!serverbot` command execution. Use manual in-client command entry or a future server-side QA harness for the remaining GM command acceptance pass.
- Current 2026-06-23 active-window gate update:
  - `tools\mochirii\assert_windower_foreground.ps1` returned
    `IsWindowerClient = true` for process `xiloader`, title `Twills`.
  - A read-only foreground screenshot was captured only after that gate passed:
    `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\active-windower-twills-20260623-033704.png`.
  - The screenshot shows Twills in Escha Ru'Aun with no visible GM icon; command
    injection remains blocked until the supported Windows automation bridge is
    available or commands are entered manually in the foreground client.
- Server bot safe leveling-zone verification passed in West Ronfaure:
  - Twills logged in through Windower to zone 100 after a clean map restart.
  - 8 active leveling bots spawned as untagged NPC actors with `role_state = adventuring`.
  - `server_bot_state`, `server_bot_audit_log`, and `server_bot_performance_snapshots` updated cleanly.
  - Dynamic MOB combat remained deferred through `combat_deferred` audit rows instead of crashing `xi_map`.
  - Runtime evidence is saved in `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\safe-west-ronfaure-bots-20260622-1821.json`.

## Current Safe Baseline

- Launch only through `C:\Users\xtyty\Desktop\Windower.lnk`.
- Foreground the `Twills`/xiloader window before input or screenshots.
- Treat active-window proof as a hard QA gate. Before any automated or manual
  command-entry/screenshot acceptance pass, run
  `tools\mochirii\assert_windower_foreground.ps1`. It must return
  `IsWindowerClient = true`; otherwise do not send commands, do not capture
  screenshots as evidence, and mark the client-side gate blocked until Windower
  is foregrounded.
- Keep the real-DAT mirrored UI/texture stack active unless rolling back from the recorded backup.
- Keep XIPivot installed and preferred for future overlay experiments, but do not assume UI/master-star DATs apply through XIPivot without in-client proof.
- Keep `XIPivot`, `distance`, `TParty`, `Config`, `Timers`, `FFXIDB`, `MipmapFix`, `SSOrganizer`, and `WinControl` autoloaded.
- Keep `SERVER_BOT_AH_ENABLED = false` and `SERVER_BOT_LLM_CHAT_ENABLED = false`.
- Keep `SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED = false` until the combat actor path is rebuilt around a C++-safe scanner/bridge.
- Keep `SERVER_BOT_PLAYER_COMMANDS_ENABLED = false`; players use Trusts, while server bots are autonomous world population.
- Keep `SERVER_BOT_AUTONOMOUS_PARTIES_ENABLED = true` with safe NPC actors until combat actor mode is moved to a verified C++ bridge.
- Keep 4GB Patch, dgVoodoo2, and ReShade behind separate backup and verification gates. dgVoodoo2 must pass a keyboard-input regression before it becomes a default wrapper.
- Do not echo or commit account secrets.

## Next Gates

1. GM and command-boundary QA:
   - First confirm Windower is the foreground app with
     `tools\mochirii\assert_windower_foreground.ps1`; no in-game command or
     screenshot counts as accepted without that foreground proof.
   - Verify `!serverbot status`, `trace`, `profile`, `rule`, `camp`, `strategy`, `audit`, `economy`, `perf`, `reload`, `pause`, `resume`, `disable`, `enable`, and `panic`.
   - Verify `!bot` refuses orders and tells players to use Trusts for companion gameplay.
   - Verify `!twillsrepair` repairs Twills while logged in, then relog and check Mog House job, Merit Points, Job Points, Alter Ego Points/category ranks, Trust, and master-related access gates.

2. Dynamic combat bridge:
   - Replace Lua `zone:getMobs()` combat scanning with a C++-safe target scanner before re-enabling dynamic MOB actors.
   - Keep `SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED = false` until the C++ bridge survives West Ronfaure and one additional low-risk leveling-zone soak.
   - Preserve the crash report and dump at `C:\Users\xtyty\Documents\FFXI\dmp\xi_map.exe_22-6_18-7-57.*` as the regression test seed.

3. Visual stack expansion:
   - Treat the real-DAT mirror as the current working baseline, not an experiment.
   - Add only one new texture, UI, audio, or wrapper layer per verification pass.
   - Use `ALL-Dat-Mods.rar` as the Amelila/RadialArcana/Kireek source pack unless a newer author/source page is explicitly selected.
   - Prefer XIPivot for new layers; fall back to real DAT replacement only with a new backup/manifest and active-window screenshot.

4. Compatibility wrappers:
   - Apply 4GB Patch only after backing up the exact active executable and verifying `LargeAddressAware`.
   - Add dgVoodoo2 only after DAT/UI stability, using 32-bit wrapper DLLs for FFXI only.
   - Add ReShade last, with a clean screenshot/log rollback point.

5. Bot development:
   - Convert city visual QA into repeatable database and in-client checks.
   - Harden autonomous bot-only party formation, solo/group progression, death/return-home, loot/economy ledgers, and combat actor selection.
   - Keep economy/AH/LLM behavior capability-gated and audit-first.

6. RDM/SCH gear and completion bootstrap:
   - Source current RDM/SCH sets and augment recommendations from credible FFXI references before choosing item IDs and augment payloads.
   - Add a retail-legit gear manifest and bootstrap only after confirming each item/augment is represented in this checkout's SQL.
   - Complete missions and quests only through source-gated LSB state, retail key items, titles, and rewards that this checkout implements; unsupported or `.todo` content must be listed in a skipped manifest instead of fabricated.

## Evidence

- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\visual-baseline-20260622-1740.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\server-bot-verification-20260622-1753.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\safe-west-ronfaure-bots-20260622-1821.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\desktop-windower-xipivot-xiview-clean-20260622-1740.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\desktop-bot-heartbeat-names-20260622-1753.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\desktop-safe-west-ronfaure-bots-20260622-1821.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\windower-official-plugins-live-verification.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\expanded-xipivot-mod-stack-verified-20260622-231427.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-applied-20260622-234443.json`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\real-client-active-dat-stack-active-window-20260622-235044.png`
- `C:\Users\xtyty\Documents\FFXI-Runtime\manifests\active-windower-twills-20260623-033704.png`
