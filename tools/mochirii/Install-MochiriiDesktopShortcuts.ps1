param(
    [string]$RuntimeRoot = "C:\Github Repo's\FFXI\Runtime",
    [string]$WindowerRoot = 'D:\Steam\steamapps\common\FFXINA\Windower'
)

$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$serverControl = Join-Path $RuntimeRoot 'server-control'
$clientTools = Join-Path $RuntimeRoot 'client-tools'
$startScript = Join-Path $serverControl 'Start-MochiriiServer.ps1'
$stopScript = Join-Path $serverControl 'Stop-MochiriiServer.ps1'
$dbScript = Join-Path $serverControl 'Open-MochiriiMariaDB.ps1'
$windowerScript = Join-Path $clientTools 'Launch-Mochirii-Windower.ps1'
$windowerExe = Join-Path $WindowerRoot 'Windower.exe'

foreach ($script in @($startScript, $stopScript, $dbScript, $windowerScript)) {
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Missing runtime script: $script"
    }
}

if (-not (Test-Path -LiteralPath $windowerExe)) {
    throw "Missing Windower executable for shortcut icon: $windowerExe"
}

$shell = New-Object -ComObject WScript.Shell

function Set-PowerShellShortcut {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string]$WorkingDirectory,
        [switch]$NoExit,
        [switch]$RunAsAdministrator,
        [string]$IconLocation
    )

    $shortcutPath = Join-Path $desktop $Name
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $exitArg = if ($NoExit) { '-NoExit ' } else { '' }
    $shortcut.Arguments = "${exitArg}-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()

    if ($RunAsAdministrator) {
        $shortcutBytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $shortcutBytes[0x15] = $shortcutBytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $shortcutBytes)
    }

    Write-Host "Updated $shortcutPath"
}

$powerShellIcon = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"

Set-PowerShellShortcut -Name 'Start Mochirii FFXI Server (WSL).lnk' -ScriptPath $startScript -WorkingDirectory $serverControl -NoExit -IconLocation $powerShellIcon
Set-PowerShellShortcut -Name 'Stop Mochirii FFXI Server (WSL).lnk' -ScriptPath $stopScript -WorkingDirectory $serverControl -NoExit -IconLocation $powerShellIcon
Set-PowerShellShortcut -Name 'Open Mochirii MariaDB (WSL).lnk' -ScriptPath $dbScript -WorkingDirectory $serverControl -NoExit -IconLocation $powerShellIcon
Set-PowerShellShortcut -Name 'Windower.lnk' -ScriptPath $windowerScript -WorkingDirectory $WindowerRoot -RunAsAdministrator -IconLocation "$windowerExe,0"
