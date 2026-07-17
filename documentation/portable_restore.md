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
  `C:\Github Repo's\FFXI\FFXI Creds\Runtime`.
- Reacquired external assets: Steam Final Fantasy XI client files, Windower,
  xiloader, XIPivot, XIView, XITide, Ashenbubs, DAT packs, fonts, and third-party
  addon release archives.

## Canonical Capture

Run the single native WSL helper from the repository root:

```bash
bash tools/mochirii/portable_restore/capture_mochirii_from_wsl.sh
```

The capture script writes encrypted artifacts under
`/home/xartyzx/projects/FFXI-Runtime/portable-restore/artifacts`, writes
passphrases into `C:\Github Repo's\FFXI\FFXI Creds\Runtime`, reads MariaDB
credentials from the canonical client configuration, and refreshes runtime
manifests. It does not write plaintext database dumps or credentials into the
repository.

The current capture produced these restorable artifacts outside Git:

- `xidb-twills-20260630-003932.sql.gz.enc`
- `windower-golden-state-20260630-004048.tar.gz.enc`

Tracked manifests under `restore/manifests` record names, sizes, hashes, capture
methods, and restore expectations.

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

XIPivot's active first-hit overlay setting is:

```text
Mochirii-GeoBubblesClear,Mochirii-BardNotesHD,Mochirii-LevelMeritJobPoints,Mochirii-MissionRankUps,XITide-Nameplates,Remapster-Maps-2048,Jasmint-HD,NextHD-Selected,AshenbubsHD-July2026-Candidate,AshenbubsHD-Prime,Legacy-Community-Unique
```

XIView v2.5.3 widescreen is a four-file direct replacement exception. XITide is
not a direct replacement: only its nameplate DAT is active through XIPivot. The
full old `ALL-Dat-Mods` source is retained only as a hash-verified external
rollback archive; its 184 unique files are the active legacy layer.

Jasmint HD 0.3.0 contributes 80 declared character-texture overrides through
XIPivot. dgVoodoo2 v2.87.3, ReShade v6.7.3, and the Vibrant Vana'diel Mochirii
Standard preset are external renderer assets and must be reacquired from the
sources and hashes in `restore/manifests/mods.manifest.json`. The accepted
ReShade configuration sets `MAGICBLOOM_NODIRT=1`, enables Vignette, MagicBloom,
MultiLUT, and AdaptiveSharpen, and leaves UIMask disabled until a verified
2560x1600 UI mask exists.

Apply direct client DAT exceptions in this order:

1. Install or verify the current official client and capture a new stock hash
   baseline.
2. Apply XIView direct replacements only when every stock hash matches
   `restore/manifests/client-direct-dat.manifest.json`.
3. Verify `ROM/119/51.DAT` resolves to XIView's hash
   `69efbec072906cffd8a1e17c18910229d4f11e936f5ea16c00a3fd5d1039131c`.
4. Restore XITide nameplates through `XITide-Nameplates`, then verify master
   stars, menus, and nameplates with native Windower screenshots.

See `documentation/client_graphics_stack.md` for source versions, collision
ownership, renderer gates, and the current evidence paths.

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
