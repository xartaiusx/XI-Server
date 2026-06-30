# Portable Mochirii Restore

This document is the operator guide for moving Mochirii from the current Windows
machine to a fresh clone, including the Garuda Linux target. It deliberately
separates what belongs in Git from what must stay encrypted or reacquired from
the original source.

## Source Policy

The tracked repository may contain source code, custom modules, restore scripts,
templates, checksums, manifests, and redacted Twills state summaries.

The repository must not contain plaintext database dumps, account secrets,
xiloader credentials, Steam or Square Enix client files, original or replaced
DAT files, downloaded mod archives, raw screenshots, or runtime logs. GitHub
blocks normal Git files over 100 MiB and recommends Git LFS for large files; the
Mochirii default is stricter: keep large/private artifacts out of Git history
unless they are encrypted first and intentionally distributed through Git LFS or
a private release.

Square Enix treats the Final Fantasy XI client and service data as licensed
software/content. Restore docs therefore record client paths, source URLs,
versions, hashes, and replacement manifests instead of uploading client assets.

## Artifact Classes

- Git-safe: server source, custom Lua/C++/SQL modules, scripts, templates,
  redacted audits, manifests, and checksums.
- Encrypted portable artifacts: full `xidb` logical dump and optional Windower
  golden-state bundle. Decryption passphrases stay under
  `C:\Users\xtyty\Documents\FFXI-Runtime\secrets`.
- Reacquired external assets: Steam Final Fantasy XI client files, Windower,
  xiloader, XIPivot, XIView, XITide, Ashenbubs, DAT packs, fonts, and third-party
  addon release archives.

## Windows Capture

Run from the repository root on the Windows machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\mochirii\portable_restore\Capture-MochiriiRestoreBundle.ps1
```

When running from Codex in WSL on the Windows host, use the native WSL helper:

```bash
bash tools/mochirii/portable_restore/capture_windows_from_wsl.sh
```

The capture script writes encrypted artifacts under
`C:\Users\xtyty\Documents\FFXI-Runtime\portable-restore\artifacts`, writes
passphrases under `FFXI-Runtime\secrets`, and refreshes runtime manifests. It
does not write plaintext database dumps into the repository.

The current capture produced these restorable artifacts outside Git:

- `xidb-twills-20260630-003932.sql.gz.enc`
- `windower-golden-state-20260630-004048.tar.gz.enc`

Tracked manifests under `restore/manifests` record names, sizes, hashes, capture
methods, and restore expectations.

The latest private Proton Drive payload is
`C:\Users\xtyty\Documents\FFXI\Server Restore-20260630-011753`, updated
`2026-06-30T02:35:09-07:00`. It contains the encrypted restore artifacts, matching
passphrases, a stopped MariaDB datadir copy, the Windower runtime, current direct
DAT replacement subset, the patched PlayOnline `pol.exe`, the 4GB patch archive,
and the downloaded mod/tool archive set. It intentionally does not include the
full Steam Final Fantasy XI client.

## Garuda Restore

Garuda is Arch-family. LandSandBoat's Arch-family notes are less primary than
the Windows and Ubuntu paths, so the restore script verifies dependencies and
prints concrete package guidance before mutating system state.

On Garuda, clone recursively, place the encrypted artifacts where the manifests
expect them, keep passphrase files outside Git, then run:

```bash
bash tools/mochirii/portable_restore/restore_garuda.sh \
  --db-artifact /path/to/xidb-twills-20260630-003932.sql.gz.enc \
  --db-pass-file /path/to/mochirii-restore-db-20260630-003932.passphrase.txt \
  --windower-artifact /path/to/windower-golden-state-20260630-004048.tar.gz.enc \
  --windower-pass-file /path/to/mochirii-restore-windower-20260630-004048.passphrase.txt
```

The script verifies or creates MariaDB state, imports `xidb`, installs Python
requirements, prepares local settings from templates, runs `dbtool update full`
twice, configures/builds with CMake presets, and can start the server daemons for
a smoke test.

For a pre-format dry run on the current Windows machine, do not import the dump
into the live MariaDB datadir. The dump was captured with `--databases xidb` and
`--add-drop-database`, so use a scratch MariaDB datadir on an alternate port or a
disposable VM/container, then point `settings/network.lua` or the
`XI_NETWORK_SQL_*` environment variables at that scratch instance.

## Client Mod Restore Notes

XIPivot's active overlay setting is:

```text
Mochirii-GeoBubblesClear,Mochirii-BardNotesHD,Mochirii-LevelMeritJobPoints,Mochirii-MissionRankUps,AshenbubsHD-Prime,ALL-Dat-Mods
```

`XiView-Widescreen` is preserved only as a staged/reference folder because XIView
is a direct replacement exception. `_inactive` remains inactive.

Apply direct client DAT exceptions in this order:

1. Apply XIView direct replacements and verify their manifest hashes.
2. Apply XITide direct replacements last.
3. Verify `ROM/119/51.DAT` resolves to XITide's final hash
   `40a9dad50db8df3ee3993dd1e9be5f068f559bc14aff059cb1e73d17f9c06dfc`.

## Verification Standard

Before pushing restore work, run:

```bash
python3 tools/mochirii/portable_restore/verify_restore.py --repo-root . --check-manifests
bash -n tools/mochirii/portable_restore/restore_garuda.sh
git diff --check
```

If available, also run `gitleaks` or `git-secrets` before pushing. A successful
restore is not accepted until a fresh clone can import the encrypted DB, build,
start `xi_connect`, `xi_search`, `xi_world`, and `xi_map`, and match the redacted
Twills baseline in `restore/manifests/twills-state.redacted.json`.

For client proof after the operating-system switch, verify direct xiloader first,
then Windower. Use Windower-native screenshots only when checking XivParty,
XIVHotbar, GearSwap, BattleMod, Config, XIPivot, XIView, and XITide.
