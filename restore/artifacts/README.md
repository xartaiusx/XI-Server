# Restore Artifacts

This directory is a local staging point for encrypted restore payloads. Git
ignores its contents by default.

Accepted local-only examples:

- `xidb-twills-YYYYMMDD-HHMMSS.sql.gz.enc`
- `windower-golden-state-YYYYMMDD-HHMMSS.tar.gz.enc`
- matching `.sha256` and `.manifest.json` files copied from
  `C:\Github Repo's\FFXI\Runtime\portable-restore\artifacts`

Never commit passphrase files, plaintext SQL, client DAT files, downloaded mod
archives, or launcher binaries here.
