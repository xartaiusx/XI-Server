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
- For client-visible state, use only native Windower screenshots. Run
  `tools\mochirii\assert_windower_foreground.ps1` first, then
  `tools\mochirii\capture_windower_window.ps1`.
- For Windower commands, Final Fantasy XI chat commands, and GM commands, use
  `tools\mochirii\Invoke-WindowerCommand.ps1` so the Twills game client is
  foregrounded and verified before the command request is submitted. The
  bridge accepts one UUID-tagged request at a time and requires
  `-AllowMutation` for mutating GM commands; never bypass its acknowledgement
  or expiry checks. Use
  `tools\mochirii\send_windower_text.ps1` only for raw keystroke cases that
  cannot go through the Windower command bridge.
- OS screenshots, Snipping Tool captures, cropped screen clips, and
  `CopyFromScreen` captures are not accepted as in-game verification evidence.
- A successful key-send helper only proves Windows sent keys; verify command
  results with a native Windower screenshot or matching server/Windower logs.
- After C++ changes, rebuild and restart `xi_map`.
- After Lua-only Trust changes, rely on file watcher reload for quick checks,
  but restart `xi_map` when spell lists, SQL, or startup-loaded module behavior
  changed.
- Keep server/runtime evidence outside the repo under
  `/root/projects/FFXI-Runtime` in WSL. Keep only the small Windows-side
  Windower bridge under `C:\Users\xtyty\Documents\FFXI-Runtime` because
  the game client and native screenshot trigger run on Windows.
- For Windower addon/plugin settings persistence, keep the live client copy
  under `D:\Steam\steamapps\common\FFXINA\Windower`, the Windows runtime
  golden-state copy under
  `C:\Users\xtyty\Documents\FFXI-Runtime\windower-golden-state`, and any
  tracked restore copy aligned. Verify layout/settings changes with file
  positions or hashes plus a native Windower screenshot after addon reload; for
  session-persistence regressions, relaunch through the desktop Windower shortcut
  and verify again before calling the setting durable.

## Standard In-Game QA Workflow

Use the same native command path for every client test so results are
repeatable and logs line up with screenshots. Prefer Final Fantasy XI,
Windower, GearSwap, XivParty, and Mochirii GM commands before adding any new
helper script. The helper layer may foreground the client and submit commands,
but the command itself should stay native whenever possible.

1. Launch only through `C:\Users\xtyty\Desktop\Windower.lnk`.
2. Before every command or screenshot, run
   `C:\Users\xtyty\Documents\FFXI-Runtime\client-tools\assert_windower_foreground.ps1`.
3. Send normal Windower, Final Fantasy XI, GearSwap, XivParty, and GM commands
   with `C:\Users\xtyty\Documents\FFXI-Runtime\client-tools\Invoke-WindowerCommand.ps1`.
   Add `-AllowMutation` only for an intentionally reviewed mutating GM command
   such as `!trustparty summonqa` or `!twillsrepair`; audits and status commands
   stay read-only and must not use the switch.
4. For addon state checks, use `//lua list`, `//lua reload <addon>`, native
   addon commands such as `//xp setup off` and `//craft status`, and native GearSwap commands such
   as `//gs reload`, `//gs validate sets`, `//gs validate inv`, and
   `//gs c status`.
5. For Trust QA, use `!trustparty summonqa`, wait for the summon-complete
   message, then run `!trustparty audit active`. Do not send `!trustparty
   repair` or combat commands while `summonqa` is still running.
6. Capture UI proof with
   `C:\Users\xtyty\Documents\FFXI-Runtime\client-tools\capture_windower_window.ps1`
   only.
7. After combat tests, generate the report from WSL with
   `python3 tools/mochirii/trust_parity_audit.py --repo-root . --runtime-root /root/projects/FFXI-Runtime --player Twills`.
8. For CraftQA, keep Twills Alchemy 110 / Cooking 70 unless a future plan
   explicitly switches specialization. Use native client Synthesis History and
   `/lastsynth` as the proof path; CraftQA may stage ingredients and record
   evidence, but must not fake a permanent synthesis history.

Keep the source tree organized: one canonical helper per job, no duplicate
Windows/WSL scripts for the same operation, no runtime logs or screenshots in
git, and no duplicate server checkout outside `/root/projects/FFXI/XI-Server`.
When tracked Windower golden-state files change, update the corresponding
manifest under `restore/manifests` in the same commit.
Never run Windower command helpers, raw key helpers, or native screenshot helpers in parallel; they share foreground focus and request files, so parallel execution can invalidate the test.

## Trust Development Rules

- Trust identity wins over generic cloning. Make each Trust a safe,
  player-like analogue for its modeled job/subjob only where the local server
  supports the action.
- Use existing Mochirii gambit/controller patterns before adding new engine
  behavior.
- Buffs and debuffs must use missing-or-expiring maintenance gates.
- Do not make broad movement/controller changes until the Trust action logs
  show the exact Trust, target, range, recast, or idle cause.
- Generate post-combat evidence with:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\mochirii\trust_parity_audit.ps1`
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
