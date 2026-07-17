# Restore Manifests

These files are safe, redacted descriptions of the current Mochirii restore
state. They identify private artifacts by filename and hash but do not include
database contents, account secrets, xiloader credentials, client files, or mod
archives.
- `source-of-truth.manifest.json`: canonical local paths for the single active
  server repo, runtime bridges, client/Windower install, desktop shortcuts, and
  cleanup boundaries.
- `upstream-base.manifest.json`: exact verified LandSandBoat `base` snapshot
  range used for the latest sync. This avoids relying on misleading merge-base
  ancestry after protected-branch squash merges.
- `twills-rdm-sch-bis-matrix.json`: Git-safe RDM/SCH set-family contract used by `tools/mochirii/gearswap_action_qa.py`; runtime evidence remains under `FFXI-Runtime/logs/gearswap_qa`.
- `client-direct-dat.manifest.json`: post-update XIView direct-DAT ownership,
  stock/replacement hashes, and external rollback paths.
- `mods.manifest.json`: external source versions/hashes, active XIPivot ownership,
  and accepted renderer configuration. Live renderer and UI
  evidence remains outside Git under `C:\Github Repo's\FFXI\Runtime\manifests`.
- `windower-golden-state.manifest.json`: tracked Git-safe settings subset. Full
  third-party addon binaries remain in the encrypted runtime bundle.
