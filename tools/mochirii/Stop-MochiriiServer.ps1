param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$RuntimeRoot = 'C:\Users\xtyty\Documents\FFXI-Runtime'
)

$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $RuntimeRoot 'server-control'
$keeperPidFile = Join-Path $stateDir 'mochirii-wsl-keeper.pid'
$stopScript = '/root/projects/FFXI-Runtime/server-control/stop-mochirii-wsl.sh'
$statusScript = '/root/projects/FFXI-Runtime/server-control/status-mochirii-wsl.sh'

Write-Host 'Stopping Mochirii WSL services...'
& wsl.exe -d $Distro -u root -- $stopScript --stop-db
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Mochirii WSL stop script exited with code $LASTEXITCODE"
}

if (Test-Path $keeperPidFile) {
    $rawPid = (Get-Content -LiteralPath $keeperPidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    $keeperPid = 0
    [void][int]::TryParse($rawPid, [ref]$keeperPid)
    if ($keeperPid -gt 0) {
        $keeper = Get-Process -Id $keeperPid -ErrorAction SilentlyContinue
        if ($null -ne $keeper) {
            Stop-Process -Id $keeperPid -Force
            Write-Host "Stopped WSL keepalive: PID $keeperPid"
        }
    }
    Remove-Item -LiteralPath $keeperPidFile -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Mochirii service status:'
& wsl.exe -d $Distro -u root -- $statusScript

Write-Host ''
Write-Host 'Mochirii FFXI server stopped.'
