param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$RuntimeRoot = "C:\Github Repo's\FFXI\Runtime"
)

$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $RuntimeRoot 'server-control'
$keeperPidFile = Join-Path $stateDir 'mochirii-wsl-keeper.pid'
$startScript = '/home/xartyzx/projects/FFXI-Runtime/server-control/start-mochirii-wsl.sh'
$statusScript = '/home/xartyzx/projects/FFXI-Runtime/server-control/status-mochirii-wsl.sh'
$ports = @(3306, 54001, 54002, 54003, 55030, 55031)

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Test-WslKeeperProcess {
    param([int]$ProcessId)
    if ($ProcessId -le 0) {
        return $false
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return $null -ne $process -and $process.ProcessName -eq 'wsl'
}

function Ensure-WslKeeper {
    $existingPid = 0
    if (Test-Path $keeperPidFile) {
        $rawPid = (Get-Content -LiteralPath $keeperPidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        [void][int]::TryParse($rawPid, [ref]$existingPid)
    }

    if (Test-WslKeeperProcess -ProcessId $existingPid) {
        Write-Host "WSL keepalive already running: PID $existingPid"
        return
    }

    if ($existingPid -gt 0) {
        Write-Host "Ignoring stale WSL keepalive PID $existingPid"
        Remove-Item -LiteralPath $keeperPidFile -Force -ErrorAction SilentlyContinue
    }

    $keeper = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $Distro, '-u', 'root', '--', '/bin/sleep', 'infinity') -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $keeperPidFile -Value $keeper.Id -Encoding ascii
    Start-Sleep -Seconds 2
    Write-Host "Started WSL keepalive: PID $($keeper.Id)"
}

Ensure-WslKeeper

Write-Host 'Starting Mochirii WSL services...'
& wsl.exe -d $Distro -u root -- $startScript
if ($LASTEXITCODE -ne 0) {
    throw "Mochirii WSL start script failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Mochirii service status:'
& wsl.exe -d $Distro -u root -- $statusScript --expect-running-manual
if ($LASTEXITCODE -ne 0) {
    throw "Mochirii WSL running/manual status gate failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Windows localhost port check:'
$failedPorts = @()
foreach ($port in $ports) {
    $result = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -WarningAction SilentlyContinue
    $status = if ($result.TcpTestSucceeded) { 'OK' } else { 'FAILED' }
    Write-Host ("  {0}: {1}" -f $port, $status)
    if (-not $result.TcpTestSucceeded) {
        $failedPorts += $port
    }
}

if ($failedPorts.Count -gt 0) {
    throw "Mochirii started, but Windows could not reach ports: $($failedPorts -join ', ')"
}

Write-Host ''
Write-Host 'Mochirii FFXI server is ready. Use the Stop Mochirii shortcut before rebooting or ending the session.'
