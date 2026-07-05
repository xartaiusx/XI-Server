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

`send_windower_text.ps1` is only an input helper. A successful run means Windows
sent keys to the foreground client, not that Final Fantasy XI accepted or ran the
command. Verify command results with a Windower-native screenshot and matching
server/Windower logs.

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
runtime reports out of git.
