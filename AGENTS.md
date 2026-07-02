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

## Verification Rules

- Always inspect current source, git status, server processes, and latest logs
  before changing behavior.
- For portable restore work, read `documentation/portable_restore.md` and the
  JSON manifests under `restore/manifests` before changing scripts, database
  backup handling, Windower restore state, or client mod policy.
- For client-visible state, use only native Windower screenshots. Run
  `tools\mochirii\assert_windower_foreground.ps1` first, then
  `tools\mochirii\capture_windower_window.ps1`.
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
