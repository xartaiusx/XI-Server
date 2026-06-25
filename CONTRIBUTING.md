# Mochirii Contribution Guide

Mochirii is a private Final Fantasy XI server project. Contributions should keep
the local server identity, runtime behavior, and QA workflow consistent with the
state documented in `README.md` and the files under `documentation/`.

## Ground Rules

- Keep the project/server name as Mochirii in all project-facing text.
- Spell out Final Fantasy XI when referring to the game.
- Do not commit account passwords, runtime secrets, database dumps, screenshots,
  downloaded client/mod archives, or local manifests.
- Preserve third-party copyright and license notices.
- Prefer small, reviewable changes that match the surrounding code style.
- Use local Mochirii modules and settings before adding broad engine changes.

## Verification

- For database or SQL changes, run the local migration/update path twice to
  verify idempotency.
- For C++ changes, rebuild before runtime testing.
- For client-facing behavior, launch through the desktop Windower shortcut,
  foreground the Final Fantasy XI window, and use only Windower-native
  screenshots for evidence after the foreground check passes. Do not use
  OS-level desktop or window screenshots for in-game UI verification.
- For Twills repair/admin work, run `!twillsaudit` after applying changes and
  check the current map log for new errors.

## Review Focus

Mochirii changes should prioritize:

- retail-shaped Final Fantasy XI behavior where the local implementation supports
  it cleanly;
- reversible client/mod and database changes;
- clear audit logs for GM, Trust, bot, and admin repair systems;
- performance-safe autonomous systems with explicit caps and kill switches.
