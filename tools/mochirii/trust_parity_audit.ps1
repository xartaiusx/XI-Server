param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$WslUser = 'xartyzx',
    [string]$RepoRoot = '/home/xartyzx/projects/FFXI/XI-Server',
    [string]$RuntimeRoot = '/home/xartyzx/projects/FFXI-Runtime',
    [string]$Player = 'Twills',
    [string]$InputPath,
    [switch]$ReadinessOnly,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxAgeSeconds = 1800
)

$ErrorActionPreference = 'Stop'

$auditPath = "$RepoRoot/tools/mochirii/trust_parity_audit.py"
$auditArgs = @(
    '-d', $Distro,
    '-u', $WslUser,
    '--',
    'python3', $auditPath,
    '--repo-root', $RepoRoot,
    '--runtime-root', $RuntimeRoot,
    '--player', $Player,
    '--max-age-seconds', $MaxAgeSeconds
)

if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
    $auditArgs += @('--input', $InputPath)
}

if ($ReadinessOnly) {
    $auditArgs += '--readiness-only'
}

& wsl.exe @auditArgs
exit $LASTEXITCODE
