param(
    [string]$RuntimeRoot = "C:\Github Repo's\FFXI\Runtime",
    [ValidateRange(1, 600)]
    [int]$WaitSeconds = 90,
    [ValidateRange(2, 120)]
    [int]$CommandWaitSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$clientProcessNames = @(
    'Windower',
    'xiloader',
    'pol',
    'polboot',
    'polcore',
    'ffximain'
)

$commandBridge = Join-Path $PSScriptRoot 'Invoke-WindowerCommand.ps1'

function Get-MochiriiClientProcess {
    @(
        Get-Process -Name $clientProcessNames -ErrorAction SilentlyContinue |
            Sort-Object ProcessName, Id
    )
}

$initialProcesses = @(Get-MochiriiClientProcess)
if ($initialProcesses.Count -eq 0) {
    [pscustomobject]@{
        Status = 'stopped'
        AlreadyStopped = $true
        CommandSubmitted = $false
        RemainingProcesses = 0
    } | ConvertTo-Json -Compress
    exit 0
}

if (-not (Test-Path -LiteralPath $commandBridge -PathType Leaf)) {
    throw "Missing canonical Windower command bridge: $commandBridge"
}

$bridgeArguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $commandBridge,
    '-Text',
    '/shutdown',
    '-RuntimeRoot',
    $RuntimeRoot,
    '-WaitSeconds',
    $CommandWaitSeconds
)

$null = & powershell.exe @bridgeArguments
$bridgeExitCode = $LASTEXITCODE
if ($bridgeExitCode -ne 0) {
    throw "Native FFXI /shutdown was not acknowledged; command bridge exit code: $bridgeExitCode"
}

$deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
$remainingProcesses = @(Get-MochiriiClientProcess)
while ($remainingProcesses.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $remainingProcesses = @(Get-MochiriiClientProcess)
}

if ($remainingProcesses.Count -gt 0) {
    $remaining = $remainingProcesses |
        ForEach-Object { "{0}:{1}" -f $_.ProcessName, $_.Id }
    throw "Native FFXI /shutdown was acknowledged, but client processes remain after $WaitSeconds seconds: $($remaining -join ', ')"
}

[pscustomobject]@{
    Status = 'stopped'
    AlreadyStopped = $false
    CommandSubmitted = $true
    RemainingProcesses = 0
} | ConvertTo-Json -Compress
