# Portable Restore Helpers

Use these helpers for Mochirii backup and portable restore.

- `capture_mochirii_from_wsl.sh` is the single capture entry point. It reads the
  canonical WSL MariaDB service, archives the canonical Windows Windower golden
  state, and stores encrypted artifacts outside Git.
- `restore_garuda.sh` restores the encrypted artifacts into a Garuda/Arch-family
  clone.
- `verify_restore.py` checks that tracked restore material is safe and internally
  consistent.

The helper reads MariaDB credentials from the canonical client configuration;
it never accepts or logs a password argument. Full database contents,
passphrases, client assets, mod archives, and runtime logs stay outside Git.
