# Mochirii Agent Guide

This file is the default operating guide for coding agents working in this
repository. Keep Mochirii as the project/server name and use Final Fantasy XI
when referring to the game.

## Current Focus

- Mochirii is a local Final Fantasy XI server project.
- The active development focus is Trust retail-player parity, Twills QA/admin
  completeness, Windower client QA, and clean server operation.
- Do not reintroduce custom world-population automation, player-commandable
  artificial party systems, real automated client sessions, or dedicated
  artificial-character database tables. Trust retail-player parity is the active
  behavior track.

## Setup Commands

- Verify tools:
  - `git --version`
  - `python --version`
  - `cmake --version`
  - `ninja --version`
  - `clang-format --version`
  - `luajit -v`
  - `lua-language-server --version`
  - `stylua --version`
- Install Python dependencies when needed:
  - `python -m pip install -r tools/requirements.txt`
- Update database modules:
  - `python tools/dbtool.py update full`
  - Run database updates twice when SQL modules change to prove idempotency.
- Build after C++ changes:
  - `cmake --build build --target xi_map --config Release --parallel 6`
- Lua syntax check for Mochirii modules:
  - `luajit -bl modules/custom/lua/trust_retail_parity.lua NUL`
  - `luajit -bl modules/custom/lua/trust_action_logger.lua NUL`
  - `luajit -bl modules/custom/commands/trustparty.lua NUL`
  - `luajit -bl modules/custom/commands/craftqa.lua NUL`

## Verification Rules

- Always inspect current source, git status, server processes, and latest logs
  before changing behavior.
- For portable restore work, read `documentation/portable_restore.md` and the
  JSON manifests under `restore/manifests` before changing scripts, database
  backup handling, Windower restore state, or client mod policy.
- For client-visible state, use only native Windower screenshots through
  `tools\mochirii\capture_windower_window.ps1`. Background capture is the
  default; the helper restores the previously active window. Use
  `-RequireForeground` only when a specific DirectInput fallback truly needs
  the client to stay active.
- For Windower commands, Final Fantasy XI chat commands, and GM commands, use
  `tools\mochirii\Invoke-WindowerCommand.ps1`. Its UUID bridge is
  background-safe by default, so routine tests must not steal focus. The
  bridge accepts one UUID-tagged request at a time and requires
  `-AllowMutation` for mutating GM commands; never bypass its acknowledgement
  or expiry checks. Add `-RequireForeground` only for an explicitly justified
  foreground-only test. Use
  `tools\mochirii\send_windower_text.ps1` only for raw keystroke cases that
  cannot go through the Windower command bridge. It restores the previously
  active window by default; use `-KeepForeground` only when the caller must
  immediately continue with an explicitly foreground-only operation.
- OS screenshots, Snipping Tool captures, cropped screen clips, and
  `CopyFromScreen` captures are not accepted as in-game verification evidence.
- A successful key-send helper only proves Windows sent keys; verify command
  results with a native Windower screenshot or matching server/Windower logs.
- After C++ changes, rebuild and restart `xi_map`.
- On the canonical Ubuntu 24.04 development host, configure cpptrace with
  `-DMOCHIRII_CPPTRACE_USE_ADDR2LINE_ON_LINUX=ON` when the packaged libdwarf
  development headers are unavailable. The option is Linux-only and defaults
  off so CI and supported libdwarf builds keep their normal backend.
- After Lua-only Trust changes, rely on file watcher reload for quick checks,
  but restart `xi_map` when spell lists, SQL, or startup-loaded module behavior
  changed.
- Start and stop Mochirii only with the canonical desktop/runtime controls.
  Every start must satisfy `status-mochirii-wsl.sh --expect-running-manual`;
  every full stop must satisfy `--expect-stopped-disabled`. MariaDB and all four
  XI units must remain `enabled=disabled` even while active. The developer stop
  path that leaves MariaDB running must satisfy
  `--expect-xi-stopped-db-running-manual`.
- Shut down the client with `tools\mochirii\Stop-MochiriiClient.ps1` through
  its runtime link. It submits native FFXI `/shutdown` through the UUID bridge,
  waits for all accepted Windower/PlayOnline/FFXI processes to exit, and fails
  if any remain. Do not substitute Windower `terminate` or a default force-kill
  path.
- Treat `C:\Github Repo's\FFXI` as the Windows project/workspace root. Its
  `XI-Server`, `WSL-Runtime`, and `Client` entries are links to the single
  canonical WSL checkout, WSL runtime, and installed client; never create a
  second server checkout under Windows.
- Keep all Mochirii/Final Fantasy XI server and client credentials under
  `C:\Github Repo's\FFXI\FFXI Creds`. Do not print, log, commit, or duplicate their
  values. The repo and runtime may contain links to required credential files,
  but not copied credentials.
- Do not recreate retired compatibility paths outside the project hub. New
  scripts, documentation, evidence, and Codex tasks must use the canonical
  locations above.
- Keep server/runtime evidence outside the repo under
  `/home/xartyzx/projects/FFXI-Runtime` in WSL. Keep only the small Windows-side
  Windower bridge under `C:\Github Repo's\FFXI\Runtime` because
  the game client and native screenshot trigger run on Windows.
- For Windower addon/plugin settings persistence, keep the live client copy
  under `D:\Steam\steamapps\common\FFXINA\Windower`, the Windows runtime
  golden-state copy under
  `C:\Github Repo's\FFXI\Runtime\windower-golden-state`, and any
  tracked restore copy aligned. Verify layout/settings changes with file
  positions or hashes plus a native Windower screenshot after addon reload; for
  session-persistence regressions, relaunch through the desktop Windower shortcut
  and verify again before calling the setting durable.

## Standard In-Game QA Workflow

Use the same native command path for every client test so results are
repeatable and logs line up with screenshots. Prefer Final Fantasy XI,
Windower, GearSwap, XivParty, and Mochirii GM commands before adding any new
helper script. Routine commands use the background UUID bridge so the user can
keep working in another app; the command itself should stay native whenever
possible.

1. Launch only through `C:\Users\xtyty\Desktop\Windower.lnk`.
2. Send normal Windower, Final Fantasy XI, GearSwap, XivParty, and GM commands
   with `C:\Github Repo's\FFXI\Runtime\client-tools\Invoke-WindowerCommand.ps1`.
   Add `-AllowMutation` only for an intentionally reviewed mutating GM command
   such as `!trustparty summonretail`, `!trustparty summonqa`,
   `!trustparty clear`, or `!twillsrepair`. Bare `!trustparty`, `mode`, `status`, `audit`,
   and `composition` are read-only and must not use the switch. Keep background
   mode unless the test has a documented DirectInput requirement.
3. For addon state checks, use `//lua list`, `//lua reload <addon>`, native
   addon commands such as `//xp setup off` and `//craft status`, and native GearSwap commands such
   as `//gs reload`, `//gs validate sets`, `//gs validate inv`, and
   `//gs c status`.
4. For Trust readiness QA, select one lane explicitly. `!trustparty summonretail`
   creates Twills plus the locked five-Trust retail-control
   party; `!trustparty summonqa` creates the Twills-only 17-Trust Mochirii QA
   alliance. Wait for the summon-complete message, verify `!trustparty mode`,
   then run the Python audit with `--readiness-only`. Readiness is not combat
   or retail-parity acceptance. Do not repair, clear, zone, or use combat
   commands while a summon is still running.
5. Capture UI proof with
   `C:\Github Repo's\FFXI\Runtime\client-tools\capture_windower_window.ps1`
   only. Require `ControlMode=BackgroundBridge`, full client dimensions, and
   `PreviousForegroundRestored=True` for unattended captures.
6. Use `!trustparty clear` between lanes and before shutdown; require idle
   state, zero Trusts, zero pending timers, and `TrustEngageType=0`. Only after
   a separately authorized combat capture, generate the default combat report
   from WSL with the canonical Python audit without `--readiness-only`.
7. At the pre-combat stop boundary, run the runtime-linked
   `Stop-MochiriiClient.ps1`, then the canonical full server stop. Require zero
   accepted client processes plus `--expect-stopped-disabled`. Stop there until
   a fresh full-alliance combat-action capture is explicitly authorized.
8. For CraftQA, keep Twills Alchemy 110 / Cooking 70 unless a future plan
   explicitly switches specialization. Use native client Synthesis History and
   `/lastsynth` as the proof path; CraftQA may stage ingredients and record
   evidence, but must not fake a permanent synthesis history.

Keep the source tree organized: one canonical helper per job, no duplicate
Windows/WSL scripts for the same operation, no runtime logs or screenshots in
git, and no duplicate server checkout outside `/home/xartyzx/projects/FFXI/XI-Server`.
When tracked Windower golden-state files change, update the corresponding
manifest under `restore/manifests` in the same commit.
Never run Windower command helpers, raw key helpers, or native screenshot helpers in parallel; they share foreground focus and request files, so parallel execution can invalidate the test.

At 2560x1600 with `uiscale=1`, the persisted overlay baseline is:

- XIVHotbar: X `1114`, spacing `56`, bottom-up battle-row Y positions `1512`,
  `1456`, `1400`, `1344`, `1288`, and `1232`. With the addon's 40-pixel
  slots, this leaves a 48-pixel bottom safety margin and 16 pixels of clear
  vertical space between rows.
- XivParty: use the tracked `mochirii_xiv` layout with `alignBottom=true`;
  party `0.88,0.985`, alliance1 `0.88,0.853`, alliance2 `0.88,0.808`; Twills
  scale `0.72`. The custom layout right-aligns all 32 buff icons inside the
  party panel, allowing the panel to occupy the native party region without
  cropping at the right edge.

Mirror any accepted change to the live client, Windows runtime golden state,
and tracked restore copy, then prove solo and full-alliance states with native
2560x1600 screenshots.

## Trust Development Rules

- Trust identity wins over generic cloning. Make each Trust a safe,
  player-like analogue for its modeled job/subjob only where the local server
  supports the action.
- Use existing Mochirii gambit/controller patterns before adding new engine
  behavior.
- Buffs and debuffs must use missing-or-expiring maintenance gates.
- Do not make broad movement/controller changes until the Trust action logs
  show the exact Trust, target, range, recast, or idle cause.
- Generate readiness evidence with the canonical Python audit and
  `--readiness-only`. Its successful report must still state
  `combat_acceptance=not_run` and must never be presented as Trust parity.
- Generate post-combat evidence with the same Python audit without
  `--readiness-only`. The PowerShell entrypoint is only a thin argument and
  exit-code forwarder.
- Treat `twills_full_alliance_qa` as a permanent Mochirii extension, never as
  retail acceptance. Retail-control evidence remains one PC plus exactly five
  eligible Trusts in one party.
- Review unresolved action names, runtime action issues, distance diagnostics,
  role-enmity decisions, alliance support scope, active effects, and early
  buff/debuff refreshes after every combat test.

## Git And Cleanup Rules

- Keep generated binaries, debug artifacts, screenshots, runtime logs, database
  backups, secrets, client files, and mod archives out of git.
- Portable restore artifacts must stay split by class:
  - Git-safe source, docs, templates, redacted summaries, and manifests may be
    tracked.
  - Full `xidb`, Windower runtime bundles, account state, and any private
    payload must be encrypted before storage outside Git history.
  - Final Fantasy XI client files, DATs, downloaded mod archives, xiloader, and
    Windower binaries are reacquired from documented sources or restored from
    private encrypted artifacts; do not commit them.
- Before committing, run:
  - `git diff --check`
  - `python3 tools/mochirii/portable_restore/verify_restore.py --repo-root .`
  - relevant LuaJIT syntax checks
  - relevant CMake build target when C++ changed
- Use focused commits with descriptive messages.
- Do not rewrite or revert user work unless explicitly asked.
- Prefer the GitHub connector for PR inspection when local `gh` is not
  authenticated.
