param(
    [string]$RuntimeRoot = 'C:\Users\xtyty\Documents\FFXI-Runtime'
)

$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$serverControl = Join-Path $RuntimeRoot 'server-control'
$startScript = Join-Path $serverControl 'Start-MochiriiServer.ps1'
$stopScript = Join-Path $serverControl 'Stop-MochiriiServer.ps1'

foreach ($script in @($startScript, $stopScript)) {
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Missing runtime server-control script: $script"
    }
}

$shell = New-Object -ComObject WScript.Shell

function Set-Shortcut {
    param(
        [string]$Name,
        [string]$ScriptPath
    )

    $shortcutPath = Join-Path $desktop $Name
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $shortcut.Save()
    Write-Host "Updated $shortcutPath"
}

Set-Shortcut -Name 'Start Mochirii FFXI Server (WSL).lnk' -ScriptPath $startScript
Set-Shortcut -Name 'Stop Mochirii FFXI Server (WSL).lnk' -ScriptPath $stopScript
