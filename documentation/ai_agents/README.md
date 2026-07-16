# Mochirii AI Agent Guidance

AI-assisted coding can help with repetitive work, documentation cleanup, and search-heavy refactors, but it is not a substitute for understanding the local source or verifying behavior in the Final Fantasy XI client.

## Acceptable Uses

- Expanding developer notes into clear documentation after a human review.
- Finding nearby source patterns before making a narrow implementation change.
- Generating boilerplate only when the result is checked against current Mochirii code.
- Summarizing logs and database evidence for QA.

## High-Risk Areas

- Final Fantasy XI behavior that must match in-client reality.
- Packet formats, mission/quest state, Trust AI, party/alliance state, and inventory blobs.
- Any code path that can crash `xi_map` or corrupt player data.

For these areas, use the current source, database, logs, packet evidence, and the live client before accepting a change.

## Agent Rules

- Read nearby code first.
- Prefer existing Mochirii patterns over new abstractions.
- Keep changes small and reviewable.
- Do not write secrets, account passwords, downloaded client files, runtime logs, or database dumps into the repo.
- Do not claim client verification without capturing the full client with Windower's native `screenshot` command.
- For every in-game UI, addon, menu, overlay, Trust, point, gear, or command-result check, use `tools\mochirii\capture_windower_window.ps1`. Its background mode must request capture through `MochiriiScreenshotQA`, validate full client dimensions, and restore the previously active window. Use `-RequireForeground` only for a documented DirectInput fallback.
- Do not use OS-level captures for in-game evidence: no `CopyFromScreen`, Snipping Tool, Print Screen, desktop capture, or cropped snippets. If the Windower-native screenshot does not show the state being verified, mark the check incomplete and capture again.
- Mark unsupported or unverified behavior as a limitation instead of fabricating state.

## Available Agent Guides

- [Retail Packet Captures Format Guide](retail-packet-captures.md)
- [Interaction Framework Migration & Verification Guide](interaction-framework-migration.md)
- [NPC Script Header Guide](npc-header-guide.md)
