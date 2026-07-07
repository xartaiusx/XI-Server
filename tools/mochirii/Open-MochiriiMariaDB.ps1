param(
    [string]$Distro = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'

$dbScript = '/root/projects/FFXI-Runtime/server-control/open-mariadb-wsl.sh'

Write-Host 'Opening Mochirii MariaDB xidb shell in WSL...'
Write-Host 'MariaDB will be started if needed and left disabled for autostart.'

& wsl.exe -d $Distro -u root -- $dbScript
if ($LASTEXITCODE -ne 0) {
    throw "Mochirii MariaDB helper failed with exit code $LASTEXITCODE"
}
