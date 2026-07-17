param()

$ErrorActionPreference = 'Stop'

$windowerRoot = 'D:\Steam\steamapps\common\FFXINA\Windower'
$windowerExe = Join-Path $windowerRoot 'Windower.exe'
$xiloaderExe = 'D:\Steam\steamapps\common\FFXINA\SquareEnix\PlayOnlineViewer\xiloader.exe'
$secretPath = "C:\Github Repo's\FFXI\FFXI Creds\Runtime\twills-xiloader-v211.json"
$logDir = "C:\Github Repo's\FFXI\Runtime\logs\client"
$restoreStateScript = "C:\Github Repo's\FFXI\Runtime\client-tools\Restore-Mochirii-Windower-State.ps1"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$failureLog = Join-Path $logDir 'last-windower-launch-error.json'
$stage = 'preflight'
Remove-Item -LiteralPath $failureLog -Force -ErrorAction SilentlyContinue

trap {
    @{
        Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
        Stage = $stage
        Error = $_.Exception.Message
    } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $failureLog
    Write-Error $_
    exit 1
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Windower requires elevation on this workstation. Launch C:\Users\xtyty\Desktop\Windower.lnk.'
}

if (-not (Test-Path -LiteralPath $windowerExe)) {
    throw "Missing Windower executable: $windowerExe"
}

if (-not (Test-Path -LiteralPath $xiloaderExe)) {
    throw "Missing xiloader executable: $xiloaderExe"
}

if (-not (Test-Path -LiteralPath $secretPath)) {
    throw "Missing Twills xiloader secret: $secretPath"
}

if (-not (Test-Path -LiteralPath $restoreStateScript)) {
    throw "Missing Mochirii Windower state restore script: $restoreStateScript"
}

$stage = 'restore-windower-state'
& $restoreStateScript

$stage = 'validate-secret'
$secret = Get-Content -Raw -LiteralPath $secretPath | ConvertFrom-Json

foreach ($field in @('server', 'username', 'password')) {
    if ([string]::IsNullOrWhiteSpace([string]$secret.$field)) {
        throw "Twills xiloader secret is missing required field: $field"
    }
}

$windowerArgs = '-p "Mochirii"'

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
$redacted = @{
    Timestamp = $timestamp
    Profile = 'Mochirii'
    Windower = $windowerExe
    Xiloader = $xiloaderExe
    Server = $secret.server
    Username = $secret.username
    Password = '[redacted]'
    WindowerArgs = '-p Mochirii'
    XiloaderArgs = 'profile-managed --json [runtime secret]'
}
$redacted | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $logDir 'last-windower-launch-redacted.json')

$stage = 'start-windower'
Start-Process -FilePath $windowerExe -WorkingDirectory $windowerRoot -ArgumentList $windowerArgs
