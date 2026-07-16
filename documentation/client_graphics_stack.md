# Mochirii Post-Update Client Graphics Stack

This document is the source of truth for the local Final Fantasy XI graphics
stack after the July 2026 client update. Client assets, archives, DLLs, DATs,
backups, screenshots, and runtime reports remain outside Git under
`C:\Github Repo's\FFXI\Runtime`.

## Canonical Paths

- Client and Windower: `D:\Steam\steamapps\common\FFXINA`
- Client launcher: `C:\Users\xtyty\Desktop\Windower.lnk`
- Runtime evidence: `C:\Github Repo's\FFXI\Runtime`
- Tracked restore metadata: `restore/manifests` and
  `restore/windower-golden-state`

Never launch the client through another executable or profile during Mochirii
QA. The desktop shortcut is marked to run as administrator because this local
Windower build requests elevation; approving that Windows UAC prompt is the
only expected foreground boundary. After launch, routine commands use the
acknowledged background bridge and native screenshot requests restore the
previously active Windows application. Use only Windower-native screenshots for
in-game evidence.

## Active DAT Ownership

XIView v2.5.3 widescreen owns the four early-loaded UI DATs listed in
`restore/manifests/client-direct-dat.manifest.json`. The post-update stock files
captured on 2026-07-14 are the only accepted rollback source. XITide does not
overwrite XIView's `ROM/119/51.DAT`; it contributes only `ROM/91/15.DAT` through
XIPivot so XIView menus and master stars remain intact.

XIPivot Windower v0.4.7 resolves the first matching DAT path. The accepted
first-hit order is:

1. `Mochirii-GeoBubblesClear`
2. `Mochirii-BardNotesHD`
3. `Mochirii-LevelMeritJobPoints`
4. `Mochirii-MissionRankUps`
5. `XITide-Nameplates`
6. `Remapster-Maps-2048`
7. `NextHD-Selected`
8. `AshenbubsHD-July2026-Candidate`
9. `AshenbubsHD-Prime`
10. `Legacy-Community-Unique`

The 2026-07-14 collision audit reports 36,516 unique paths, 86 intentional
collisions, and zero unexplained collisions. `ALL-Dat-Mods` is retired: its
complete archive is hash-verified in runtime backup storage, while only its 184
unique files remain active. NextGames HD is curated to 421 files that do not
collide with Prime. The July Ashenbubs candidate contains one changed and
fourteen new files relative to Prime and remains isolated until soak acceptance.

## Windower Baseline

`Windower/scripts/init.txt` is the only addon startup source. XIPivot and
XICamera load once, followed by the lean Mochirii QA addon stack. Global
Windower autoload remains empty. XICamera uses stable Windower 4 v0.7.10 with:

- camera distance 6
- battle distance 8.2
- horizontal pan speed 3
- vertical pan speed 10.7
- automatic vertical speed enabled
- battle range 4 and locked

The tracked restore contains XICamera settings only. Its DLL, addon release
files, and archive remain external.

## Renderer Gate

`pol.exe` remains Large Address Aware. dgVoodoo2 v2.87.3 and ReShade v6.7.3 are
installed outside Git with exact rollback backups. dgVoodoo uses the initial
maximum-fidelity configuration below. ReShade injects with a clean, disabled
baseline preset; no effects are enabled until the full Mochirii login, zoning,
keyboard, menu, and soak gate passes.

The installed dgVoodoo2 configuration uses the 32-bit D3D8 wrapper and Direct3D
11 feature level 11.0, 2048 MB VRAM, 16x anisotropic filtering, 4x MSAA, and no
watermark. D3D12 is not the initial backend because dgVoodoo's current
documentation warns of NVIDIA crashes. Windower supersampling is `0` while
wrapper MSAA is active. Windower omits that default-off field when it rewrites
the launcher profile, so the durable golden state uses the same omitted form
instead of reintroducing a harmless hash mismatch on every launch.

ReShade currently has valid shader/texture search paths, five locally installed
shader sources, and no enabled techniques. Keep that disabled baseline until
dgVoodoo passes login, keyboard, menus, zoning, Mog House, combat, cutscene,
logout/relogin, and 30-minute soak checks. Removing or renaming `dxgi.dll` is the
one-file disable path, and the pre-install renderer backup remains authoritative.
Vibrant Vana'diel is optional and remains pending its authenticated source
archive.

## Verified Evidence

The 2026-07-14 graphics baseline and 2026-07-16 UI pass proved:

- XIView master stars and menus render from the direct DAT exception.
- XITide nameplates render through XIPivot.
- Remapster displays its branded Reisenjima map, proving runtime redirection.
- Ashenbubs Prime/world and equipment textures render.
- all six XIVHotbar rows remain evenly spaced in the lower action area at
  2560x1600 with `uiscale=1`: X `1114`, spacing `56`, bottom-up Y `1512`,
  `1456`, `1400`, `1344`, `1288`, `1232`. The addon's 40-pixel slots leave a
  48-pixel bottom safety margin and 16-pixel clear gaps between rows.
- XivParty uses the tracked `mochirii_xiv` layout and is bottom-anchored over
  the native party region at party `0.88,0.985`, alliance1 `0.88,0.853`,
  alliance2 `0.88,0.808`, scale `0.72`. The custom layout right-aligns all 32
  buff icons inside the 377-pixel panel, so the panel can replace the native
  party area without right-edge clipping. The 410-pixel main layout and
  315-pixel alliance layout leave 12-pixel vertical gaps after scaling and
  stack all three parties compactly in the native party region.
- XICamera settings survive logout and relaunch.
- the dgVoodoo/ReShade-disabled baseline remained responsive for a 41.7-minute
  in-world soak with no current-session `xi_map` warning or error lines.
- no black screen, invisible equipment, missing menu, or visible Lua error was
  observed in the acceptance session.

Runtime evidence includes:

- `manifests/xiview-direct-post-update-20260714-155354.json`
- `manifests/xipivot-active-overlays-current.json`
- `manifests/xipivot-overlay-collisions-final-20260714-160358.json`
- `screenshots/post-update-xiview-xipivot-xicamera-20260714-160748.jpg`
- `screenshots/xipivot-active-overlays-20260714-1609.jpg`
- `screenshots/remapster-map-proof-20260714-1610.jpg`
- `manifests/renderer-current.json`
- `manifests/windower-ui-layout-current.json`
- `screenshots/xivparty-bottom-anchor-solo-20260716.jpg`
- `screenshots/xivparty-bottom-anchor-alliance-20260716.jpg`
- `screenshots/windower-lua-list-ui-final-20260716.jpg`
- `screenshots/xipivot-status-ui-final-20260716.jpg`
- `screenshots/xicamera-status-ui-final-20260716.jpg`

## Remaining External Sources

Jasmint HD Player Characters Compilation and Vibrant Vana'diel require the
authenticated Nexus session. Jasmint is reserved above Remapster in XIPivot;
Vibrant Vana'diel is deferred until ReShade is accepted. Neither is represented
as installed until its archive, source version, and hash are recorded.
