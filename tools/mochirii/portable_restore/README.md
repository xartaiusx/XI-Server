# Portable Restore Helpers

Use these helpers for the Windows-to-Garuda Mochirii restore path.

- `Capture-MochiriiRestoreBundle.ps1` captures encrypted Windows runtime
  artifacts outside Git.
- `capture_windows_from_wsl.sh` performs the same capture from WSL, which is the
  most reliable path when Codex is running in a Linux shell on the Windows host.
- `restore_garuda.sh` restores the encrypted artifacts into a Garuda/Arch-family
  clone.
- `verify_restore.py` checks that tracked restore material is safe and internally
  consistent.

The helpers intentionally keep full database contents, passphrases, client
assets, mod archives, and runtime logs outside the repository.
