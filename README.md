# Mochirii

Mochirii is a local Final Fantasy XI server project focused on a polished, retail-shaped private world for development and QA.

The project name and server identity are Mochirii. Public-facing documentation should use Mochirii for the server/project and spell out Final Fantasy XI when referring to the game.

## Current State

- Server identity: `Mochirii`.
- Windows project root: `C:\Github Repo's\FFXI`.
- Canonical WSL checkout: `/home/xartyzx/projects/FFXI/XI-Server`.
- Credentials: `C:\Github Repo's\FFXI\FFXI Creds`, outside Git and runtime evidence.
- Manual server controls are available from the desktop:
  - `Start Mochirii FFXI Server (WSL).lnk`
  - `Stop Mochirii FFXI Server (WSL).lnk`
- The server does not auto-start after reboot.
- The canonical client launch path is `C:\Users\xtyty\Desktop\Windower.lnk`.
- Twills is the local admin QA character: Red Mage main, Scholar support, GM5 privileges, visible GM marker hidden.
- 2026-06-25 server verification: desktop Start/Stop shortcuts manually started and stopped MariaDB plus `xi_connect`, `xi_search`, `xi_world`, and `xi_map`; no Startup-folder, Run-key, service, or Scheduled Task autostart was configured.
- 2026-06-25 tooling verification: LuaJIT, Lua, Lua Language Server, StyLua, CMake, Ninja, clang-format 22, Python, Node, and GitHub CLI are installed. Local `gh` is authenticated for `xartaiusx/XI-Server`.
- 2026-06-25 cleanup: ignored root debug artifacts and the old root Windower screenshot were removed from the workspace. Runtime evidence remains under `C:\Github Repo's\FFXI\Runtime`.
- 2026-06-30 portable restore baseline: fresh encrypted `xidb` and Windower golden-state artifacts exist under `C:\Github Repo's\FFXI\Runtime\portable-restore\artifacts`; tracked restore manifests live under `restore\manifests`.
- 2026-07-12 source-of-truth consolidation: the project hub links to one WSL checkout, one WSL runtime, and one installed client; Windows helper deployments are links to tracked sources where practical.
- 2026-07-14/16 post-update graphics baseline: XIView owns four backed-up direct UI DATs; XIPivot owns the collision-audited texture/map/effect stack; XICamera v0.7.10 and the bottom-anchored XivParty/XIVHotbar layouts are persistent; dgVoodoo2 and a disabled-technique ReShade baseline are installed with separate acceptance gates.

## Development Focus

Mochirii currently tracks three active workstreams:

- Client and mod-stack stability through Windower, GearSwap, XIVHotbar, XivParty, and verified visual DAT layers.
- Twills account and character completion for a retail-shaped long-time Red Mage/Scholar tester.
- Trust behavior parity, with Trusts becoming closer to competent player-like versions of their job/subjob roles.

## Documentation Map

- `AGENTS.md` is the repo-level operating guide for Codex/agent work.
- `documentation/client_mod_admin_plan.md` tracks client, Windower, mod, server-control, and Trust QA state.
- `documentation/client_graphics_stack.md` records current graphics ownership, versions, collision policy, renderer gates, and runtime proof.
- `documentation/twills_rdm_sch_gear_completion.md` tracks Twills gear, storage, professions, chocobo, progression, and audit state.
- `documentation/trust_retail_parity.md` tracks retail-control and Twills-only
  full-alliance evidence lanes, Trust combat behavior, session-bound logging,
  and per-Trust parity work.
- `documentation/portable_restore.md` explains the Windows capture, GitHub-safe artifact policy, and Garuda restore path.
- `restore/` contains Git-safe restore manifests, templates, and the tracked Windower golden-state subset.

## Validation Standard

Changes should be verified against the current local source, the live database, logs, and the Final Fantasy XI client whenever the behavior is visible in-game.

For in-game UI proof, only native Windower screenshots count. Use the
foreground helper and capture helper under `tools/mochirii` before accepting
client-visible results.

Preferred evidence order:

1. Current local source, SQL, migrations, and runtime behavior.
2. Official Final Fantasy XI or Square Enix update notes.
3. Retail captures, packet observations, or in-client proof when official notes omit exact details.
4. Community references as secondary guidance, verified against source or runtime evidence before implementation.

## Portable Restore

The restore goal is reproducibility, not committing every byte. Source code,
custom modules, redacted Twills state, templates, checksums, and manifests are
tracked. Full database state and exact Windower runtime bundles are encrypted
under `FFXI-Runtime` and referenced by hash. Final Fantasy XI client files, DAT
files, downloaded mod archives, launcher binaries, screenshots, raw logs, and
secrets are intentionally reacquired or restored from private encrypted
artifacts instead of committed.

Key entry points:

- `tools/mochirii/portable_restore/capture_mochirii_from_wsl.sh`
- `tools/mochirii/portable_restore/restore_garuda.sh`
- `tools/mochirii/portable_restore/verify_restore.py`

## Safety Rules

Do not commit or publish:

- secrets, passwords, hashes, tokens, or temporary credentials
- client files, mod archives, launcher binaries, or extracted game assets
- database dumps, backups, raw captures with private data, or runtime logs
- local account details beyond safe QA summaries
- plaintext restore artifacts, encrypted artifacts without an explicit private
  distribution decision, or decryption passphrases

## License

This project is distributed under the GNU GPL v3 license. See [LICENSE](LICENSE).
