param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$RuntimeRoot = "C:\Github Repo's\FFXI\Runtime"
)

$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $RuntimeRoot 'server-control'
$keeperPidFile = Join-Path $stateDir 'mochirii-wsl-keeper.pid'
$stopScript = '/home/xartyzx/projects/FFXI-Runtime/server-control/stop-mochirii-wsl.sh'
$statusScript = '/home/xartyzx/projects/FFXI-Runtime/server-control/status-mochirii-wsl.sh'

Write-Host 'Stopping Mochirii WSL services...'
& wsl.exe -d $Distro -u root -- $stopScript --stop-db
if ($LASTEXITCODE -ne 0) {
    throw "Mochirii WSL stop script failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Mochirii service status:'
& wsl.exe -d $Distro -u root -- $statusScript --expect-stopped-disabled
if ($LASTEXITCODE -ne 0) {
    throw "Mochirii WSL stopped/disabled status gate failed with exit code $LASTEXITCODE"
}

if (Test-Path $keeperPidFile) {
    $rawPid = (Get-Content -LiteralPath $keeperPidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    $keeperPid = 0
    [void][int]::TryParse($rawPid, [ref]$keeperPid)
    if ($keeperPid -gt 0) {
        $keeper = Get-Process -Id $keeperPid -ErrorAction SilentlyContinue
        if ($null -ne $keeper -and $keeper.ProcessName -eq 'wsl') {
            Stop-Process -Id $keeperPid -Force
            Write-Host "Stopped WSL keepalive: PID $keeperPid"
        } elseif ($null -ne $keeper) {
            Write-Warning "Ignoring stale WSL keepalive PID $keeperPid because it belongs to $($keeper.ProcessName)."
        }
    }
    Remove-Item -LiteralPath $keeperPidFile -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Mochirii FFXI server stopped.'
