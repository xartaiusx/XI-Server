param(
    [Parameter(Mandatory = $true)]
    [string] $Text,

    [string] $RuntimeRoot = "C:\Github Repo's\FFXI\Runtime",
    [int] $WaitSeconds = 10,
    [switch] $AllowMutation,
    [switch] $RequireForeground
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ReadOnlyGmCommand {
    param([string] $Command)

    $tokens = @($Command.Trim().ToLowerInvariant() -split '\s+')
    if ($tokens.Count -eq 0) {
        return $false
    }

    if ($tokens[0] -eq '!twillsaudit') {
        return $true
    }

    if (
        $tokens[0] -eq '!trustparty' -and
        (
            $tokens.Count -eq 1 -or
            ($tokens.Count -ge 2 -and $tokens[1] -in @('audit', 'status', 'mode', 'composition'))
        )
    ) {
        return $true
    }

    return (
        $tokens[0] -eq '!craftqa' -and
        $tokens.Count -ge 3 -and
        $tokens[1] -eq 'cooking' -and
        $tokens[2] -in @('report', 'status')
    )
}

function Get-ExistingRequest {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Malformed Windower command request already exists: $Path"
    }
}

$normalized = $Text.Trim()
if ($normalized -eq '') {
    throw 'Command text cannot be empty.'
}

if ($normalized -match '[\r\n]') {
    throw 'Exactly one command is allowed per Windower command request.'
}

$isMutatingGmCommand = $normalized.StartsWith('!') -and -not (Test-ReadOnlyGmCommand -Command $normalized)
if ($isMutatingGmCommand -and -not $AllowMutation) {
    throw "Mutating GM command rejected. Re-run with -AllowMutation after reviewing the exact command: $normalized"
}

if ($normalized.StartsWith('//')) {
    $requestCommand = $normalized.Substring(2).Trim()
} elseif ($normalized.StartsWith('/') -or $normalized.StartsWith('!')) {
    $requestCommand = "input $normalized"
} else {
    $requestCommand = $normalized
}

if ($requestCommand -eq '') {
    throw 'Command text cannot be empty after normalization.'
}

$toolsRoot = $PSScriptRoot
$focusHelper = Join-Path $toolsRoot 'send_windower_text.ps1'
if ($RequireForeground -and -not (Test-Path -LiteralPath $focusHelper)) {
    throw "Missing foreground helper: $focusHelper"
}

$clientTools = Join-Path $RuntimeRoot 'client-tools'
$bridgeRoot = Join-Path $clientTools 'windower-command-bridge'
$ackRoot = Join-Path $bridgeRoot 'acks'
$requestPath = Join-Path $bridgeRoot 'request.json'
$legacyRequestPath = Join-Path $clientTools 'windower_command_request.txt'

New-Item -ItemType Directory -Force -Path $ackRoot | Out-Null
Remove-Item -LiteralPath $legacyRequestPath -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $ackRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Where-Object LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddDays(-2) |
    Remove-Item -Force -ErrorAction SilentlyContinue

$mutex = [System.Threading.Mutex]::new($false, 'Local\MochiriiWindowerCommandBridge')
$lockAcquired = $false
$result = $null
$exitCode = 2
$tempPath = $null

try {
    try {
        $lockAcquired = $mutex.WaitOne([TimeSpan]::FromSeconds([Math]::Max(2, $WaitSeconds)))
    } catch [System.Threading.AbandonedMutexException] {
        $lockAcquired = $true
    }

    if (-not $lockAcquired) {
        throw 'Another Windower command request is still active.'
    }

    $existing = Get-ExistingRequest -Path $requestPath
    if ($null -ne $existing) {
        $expiresUnix = 0L
        if ($existing.PSObject.Properties.Name -contains 'expires_unix') {
            $expiresUnix = [long] $existing.expires_unix
        }

        $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($expiresUnix -gt 0 -and $expiresUnix -le $nowUnix) {
            Remove-Item -LiteralPath $requestPath -Force
        } else {
            throw "An unexpired Windower command request already exists: $requestPath"
        }
    }

    if ($RequireForeground) {
        # Clearing with Escape here would discard a deliberately selected <t>
        # immediately before target-dependent QA commands.
        & powershell -NoProfile -ExecutionPolicy Bypass -File $focusHelper -NoClearInputBefore -KeepForeground
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to foreground the Final Fantasy XI client before command execution. Exit code: $LASTEXITCODE"
        }
    }

    $requestId = [Guid]::NewGuid().ToString('D')
    $created = [DateTimeOffset]::UtcNow
    $lifetimeSeconds = [Math]::Max(15, $WaitSeconds + 5)
    $expires = $created.AddSeconds($lifetimeSeconds)
    $ackPath = Join-Path $ackRoot "$requestId.json"
    $tempPath = Join-Path $bridgeRoot "request.$requestId.tmp"

    $requestObject = [ordered]@{
        schema_version = 1
        id = $requestId
        created_unix = $created.ToUnixTimeSeconds()
        expires_unix = $expires.ToUnixTimeSeconds()
        allow_mutation = [bool] $AllowMutation
        mutating = [bool] $isMutatingGmCommand
        command = $requestCommand
        original_text = $normalized
    }

    $json = $requestObject | ConvertTo-Json -Compress
    # Windower's bundled JSON tokenizer treats \" as a closing quote. Keep the
    # envelope valid JSON while transporting embedded command quotes safely.
    $json = $json.Replace('\"', '\u0022')
    [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($tempPath, $requestPath)
    $tempPath = $null

    $deadline = (Get-Date).AddSeconds([Math]::Max(2, $WaitSeconds))
    do {
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $ackPath) {
            $ack = Get-Content -LiteralPath $ackPath -Raw | ConvertFrom-Json
            if ($ack.id -ne $requestId) {
                throw "Windower acknowledgement id mismatch for request $requestId."
            }

            $succeeded = $ack.status -eq 'success'
            $result = [pscustomobject]@{
                Submitted = $succeeded
                ForegroundVerified = [bool] $RequireForeground
                ControlMode = if ($RequireForeground) { 'ForegroundBridge' } else { 'BackgroundBridge' }
                RequestId = $requestId
                RequestPath = $requestPath
                AcknowledgementPath = $ackPath
                AcknowledgementStatus = $ack.status
                AcknowledgementDetail = $ack.detail
                MutationAllowed = [bool] $AllowMutation
                Mutating = [bool] $isMutatingGmCommand
                Request = $requestCommand
                OriginalText = $normalized
            }
            $exitCode = if ($succeeded) { 0 } else { 2 }
            break
        }
    } while ((Get-Date) -lt $deadline)

    if ($null -eq $result) {
        $pending = Get-ExistingRequest -Path $requestPath
        if ($null -ne $pending -and $pending.id -eq $requestId) {
            Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
        }

        $result = [pscustomobject]@{
            Submitted = $false
            ForegroundVerified = [bool] $RequireForeground
            ControlMode = if ($RequireForeground) { 'ForegroundBridge' } else { 'BackgroundBridge' }
            RequestId = $requestId
            RequestPath = $requestPath
            AcknowledgementPath = $ackPath
            MutationAllowed = [bool] $AllowMutation
            Mutating = [bool] $isMutatingGmCommand
            Request = $requestCommand
            OriginalText = $normalized
            Error = 'MochiriiScreenshotQA did not acknowledge the command request before the timeout.'
        }
    }
} finally {
    if ($null -ne $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    if ($lockAcquired) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

$result | ConvertTo-Json -Compress
exit $exitCode
