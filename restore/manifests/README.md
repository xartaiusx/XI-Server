# Restore Manifests

These files are safe, redacted descriptions of the current Mochirii restore
state. They identify private artifacts by filename and hash but do not include
database contents, account secrets, xiloader credentials, client files, or mod
archives.
- `source-of-truth.manifest.json`: canonical local paths for the single active
  server repo, runtime bridges, client/Windower install, desktop shortcuts, and
  cleanup boundaries.
- `twills-rdm-sch-bis-matrix.json`: Git-safe RDM/SCH set-family contract used by `tools/mochirii/gearswap_action_qa.py`; runtime evidence remains under `FFXI-Runtime/logs/gearswap_qa`.
