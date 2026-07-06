param(
    [string]$WindowerRoot = 'D:\Steam\steamapps\common\FFXINA\Windower',
    [string]$RuntimeRoot = 'C:\Users\xtyty\Documents\FFXI-Runtime'
)

$ErrorActionPreference = 'Stop'

$addonPath = Join-Path $WindowerRoot 'addons\XivParty\xivparty.lua'
if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "XivParty addon file was not found: $addonPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$hadBom = $source.Length -gt 0 -and [int][char]$source[0] -eq 0xFEFF
if ($hadBom) {
    $source = $source.Substring(1)
}
$normalizedSource = $source -replace "`r`n", "`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$oldBlock = @'
local function setSetupEnabled(enabled)
    isSetupEnabled = enabled

    if not setupModel then
        setupModel = model.new()
        setupModel:createSetupData()
    end

    view:setModel(isSetupEnabled and setupModel or model) -- lua style ternary operator
    view:setUiLocked(not isSetupEnabled)
end
'@

$newBlock = @'
local function setSetupEnabled(enabled)
    isSetupEnabled = enabled

    if not view and windower.ffxi.get_info().logged_in then
        init()
    end

    if not view then
        log('Setup mode deferred until XivParty initializes after login.')
        return
    end

    if not setupModel then
        setupModel = model.new()
        setupModel:createSetupData()
    end

    view:setModel(isSetupEnabled and setupModel or model) -- lua style ternary operator
    view:setUiLocked(not isSetupEnabled)
end
'@

$setupPattern = '(?s)local function setSetupEnabled\(enabled\).*?view:setUiLocked\(not isSetupEnabled\)\s*end'

if ($normalizedSource.Contains('Setup mode deferred until XivParty initializes after login.')) {
    if ($hadBom) {
        [System.IO.File]::WriteAllText($addonPath, $normalizedSource, $utf8NoBom)
        Write-Output "Removed UTF-8 BOM from already-guarded XivParty addon: $addonPath"
    }
    Write-Output "XivParty setup guard is already applied: $addonPath"
    exit 0
}

if (-not [regex]::IsMatch($normalizedSource, $setupPattern)) {
    throw "Expected XivParty setup block was not found. Refusing to patch an unknown version: $addonPath"
}

$backupDir = Join-Path $RuntimeRoot 'backups\xivparty'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $backupDir "xivparty.lua.$timestamp.bak"
Copy-Item -LiteralPath $addonPath -Destination $backupPath -Force

$patched = [regex]::Replace($normalizedSource, $setupPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $newBlock.TrimEnd() }, 1)
[System.IO.File]::WriteAllText($addonPath, $patched, $utf8NoBom)

$originalHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$patchedHash = (Get-FileHash -LiteralPath $addonPath -Algorithm SHA256).Hash.ToLowerInvariant()

$manifestPath = Join-Path $backupDir "xivparty-setup-guard-$timestamp.json"
$manifest = [ordered]@{
    patchedAt = (Get-Date).ToString('o')
    addonPath = $addonPath
    backupPath = $backupPath
    originalSha256 = $originalHash
    patchedSha256 = $patchedHash
    change = 'Guard xp setup commands so view:setModel and view:setUiLocked are never called before XivParty initializes.'
}

$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output "Applied XivParty setup guard: $addonPath"
Write-Output "Backup: $backupPath"
Write-Output "Manifest: $manifestPath"
