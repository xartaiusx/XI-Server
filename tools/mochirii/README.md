# Mochirii Client QA Helpers

Use these scripts whenever a task needs Final Fantasy XI client evidence from
the local Windower session.

Required order for client-visible checks:

1. Launch through `C:\Users\xtyty\Desktop\Windower.lnk`.
2. Run `assert_windower_foreground.ps1` and require `IsWindowerClient = true`.
3. Run `capture_windower_window.ps1`. This writes a request for the loaded
   `MochiriiScreenshotQA` Windower addon, which runs Windower's native
   `screenshot` command and waits for the new file under `Windower\screenshots`;
   it must not use OS screen capture. The helper must also report image
   dimensions that meet the live client rectangle after DPI scaling; otherwise
   the capture is treated as cropped or stale and must not be accepted.
4. Inspect the screenshot before accepting UI, addon, menu, Trust, point,
   GearSwap, or command-entry results.

Do not use `CopyFromScreen`, Snipping Tool, Print Screen, desktop screenshots,
or any other OS-level capture as in-game verification evidence. Native
Windower screenshots are the permanent Mochirii client QA standard because they
capture the actual game client output without Codex, desktop, or window-manager
overlap.

The source copy for the Windower-side bridge is kept at
`tools\mochirii\windower_addons\MochiriiScreenshotQA\MochiriiScreenshotQA.lua`
and installed into `Windower\addons\MochiriiScreenshotQA`.

## Repeatable Native Command Sequence

For every in-client test, keep the command surface stable and native:

1. Foreground and verify the Twills/Windower client with
   `assert_windower_foreground.ps1`.
2. Submit commands with `Invoke-WindowerCommand.ps1`; it is the single normal
   bridge for Windower commands, Final Fantasy XI input commands, GearSwap
   commands, XivParty commands, and Mochirii GM commands. It writes one atomic,
   UUID-tagged request, rejects duplicate or expired work, and waits for the
   Windower addon acknowledgement. Mutating GM commands require the explicit
   `-AllowMutation` switch; audit and status commands do not.
3. Prefer existing client/server commands before creating helpers: `//lua list`,
   `//lua reload <addon>`, `//xp setup off`, `//craft status`, `//gs reload`,
   `//gs validate sets`, `//gs validate inv`, `//gs c status`,
   `!trustparty summonqa`, and `!trustparty audit active`.
4. For Trust alliance QA, wait for the `!trustparty summonqa` completion message
   before any repair, audit, screenshot, or combat command. The summon helper
   owns the repair pass while it is active.
5. Use `capture_windower_window.ps1` for proof. The helper must trigger native
   Windower screenshot output and must report full client dimensions.

Do not add another helper for a task already covered here unless a native
Windower/Final Fantasy XI/GearSwap/XivParty/Mochirii command cannot do the job.
Never run command, raw-key, and screenshot helpers in parallel; each client step must finish before the next one starts.

## XivParty Runtime Guard

Mochirii tracks XivParty settings in Git, while the full third-party addon
source stays in the private encrypted Windower restore bundle. If XivParty
errors while toggling setup mode before its UI view is initialized, apply the
runtime guard to the live addon copy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\mochirii\Apply-XivPartySetupGuard.ps1
```

The helper backs up `Windower\addons\XivParty\xivparty.lua` under
`C:\Users\xtyty\Documents\FFXI-Runtime\backups\xivparty` and patches only the
`setSetupEnabled()` path so `//xp setup on` and `//xp setup off` cannot call
`view:setModel()` or `view:setUiLocked()` before XivParty has initialized after
login. Verify with `//lua reload XivParty`, `//xp setup on`, `//xp setup off`,
and a native Windower screenshot.

For layout persistence, keep XivParty positions synchronized between the live
client file `D:\Steam\steamapps\common\FFXINA\Windower\addons\XivParty\data\settings.xml`
and the runtime golden-state file
`C:\Users\xtyty\Documents\FFXI-Runtime\windower-golden-state\addons\XivParty\data\settings.xml`.
The current Twills layout is party `0.765,0.815`, alliance1 `0.765,0.675`,
alliance2 `0.765,0.535`, scale `0.72`. Verify changes through native XivParty
commands, addon reload, and native Windower screenshots before updating tracked
restore state.

Use `Invoke-WindowerCommand.ps1` for normal Windower, Final Fantasy XI chat,
and GM command execution. It foregrounds the Twills/Windower client, clears any
stale chat/menu input through `send_windower_text.ps1`, then atomically publishes
one expiring request for the loaded `MochiriiScreenshotQA` addon to execute
through Windower's native command channel. The addon caches processed request
IDs and writes a success or failure acknowledgement; the helper does not treat
file consumption alone as success. It normalizes `//lua reload XivParty` to a
Windower command, `/ma ...` to `input /ma ...`, and `!trustparty ...` to
`input !trustparty ...`. Use `-AllowMutation` for commands such as
`!trustparty summonqa`, `!twillsrepair`, and CraftQA staging/crafting. Do not use
the switch for `!twillsaudit`, `!trustparty audit|status`, or
`!craftqa cooking status|report`.

`send_windower_text.ps1` is only a raw input helper for cases that truly require
keystrokes. It must foreground the Twills/Windower client, verify the game
client is the active foreground window, clear stale chat/menu input unless
`-NoClearInputBefore` is explicitly passed, and verify foreground focus again
before typing. A successful run means Windows sent keys to the foreground client,
not that Final Fantasy XI accepted or ran the command. Verify command results
with a Windower-native screenshot and matching server/Windower logs.

## Trust Parity Audit

When the live Mochirii server/runtime is running from WSL, generate the canonical
Trust parity report from the WSL checkout so the audit reads the active live log
without copying runtime files:

```bash
python3 tools/mochirii/trust_parity_audit.py --repo-root . --runtime-root /root/projects/FFXI-Runtime --player Twills
```

The report is written under `/root/projects/FFXI-Runtime/reports`. Use it
after `!trustparty summonqa`, the summon-complete message, `!trustparty audit
active`, and a controlled combat test. Fix Trust AI only from report evidence:
unresolved names, runtime action issues, role mistakes, early buff/debuff
refreshes, missing static preconditions, or support-scope gaps.

## Twills GearSwap QA

Run the static resolver before accepting Twills RDM/SCH GearSwap changes:

```bash
python3 tools/mochirii/gearswap_action_qa.py --repo-root .
```

Then verify the live Windower profile with:

```text
//gs reload
//gs validate sets
//gs validate inv
//gs c qa all
//gs c status
//gs c gearscore
```

The static resolver writes reports to `/root/projects/FFXI-Runtime/logs/gearswap_qa/`.
The live GearSwap command writes TSV evidence to
`C:\Users\xtyty\Documents\FFXI-Runtime\logs\gearswap_qa`. Keep those
runtime reports out of git. `//gs c qa all` writes live set, equipment,
visual-model, and action-family/baseline TSV evidence; `//gs c qa families`
refreshes only the action-family matrix.

## GearSwap Visual-Model Audit

Twills GearSwap QA validates visible equipment model ids. Final action sets fail when `main`, `sub`, `head`, `body`, `hands`, `legs`, or `feet` resolve to a local equipment row with `MId=0`, because Mochirii sends `item_equipment.MId` as the rendered model id. Ammo, ranged, and accessory rows with `MId=0` are informational unless they affect a visible character model.

`restore/windower-golden-state/addons/GearSwap/data/Twills-visual-models.lua` is generated from local `item_basic` and `item_equipment` data by:

```bash
python3 tools/mochirii/gearswap_action_qa.py --repo-root . --write-visual-manifest restore/windower-golden-state/addons/GearSwap/data/Twills-visual-models.lua --no-write-report
```

Do not edit that manifest by hand. Use `//gs c qa visual` for a live Windower snapshot under `FFXI-Runtime/logs/gearswap_qa`; unknown visible items and missing manifests are failures.
