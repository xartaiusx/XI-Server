param(
    [Parameter(Mandatory = $true)]
    [string] $Text,

    [string] $RuntimeRoot = 'C:\Users\xtyty\Documents\FFXI-Runtime',
    [int] $WaitSeconds = 5
)

$ErrorActionPreference = 'Stop'

$toolsRoot = $PSScriptRoot
$focusHelper = Join-Path $toolsRoot 'send_windower_text.ps1'
if (-not (Test-Path -LiteralPath $focusHelper)) {
    throw "Missing foreground helper: $focusHelper"
}

$normalized = $Text.Trim()
if ($normalized -eq '') {
    throw 'Command text cannot be empty.'
}

# Always foreground the game and clear stale chat/menu state before command execution.
& powershell -NoProfile -ExecutionPolicy Bypass -File $focusHelper
if ($LASTEXITCODE -ne 0) {
    throw "Failed to foreground and clear the Final Fantasy XI client before command execution. Exit code: $LASTEXITCODE"
}

if ($normalized.StartsWith('//')) {
    $request = $normalized.Substring(2).Trim()
} elseif ($normalized.StartsWith('/') -or $normalized.StartsWith('!')) {
    $request = "input $normalized"
} else {
    $request = $normalized
}

if ($request -eq '') {
    throw 'Command text cannot be empty after normalization.'
}

$clientTools = Join-Path $RuntimeRoot 'client-tools'
New-Item -ItemType Directory -Force -Path $clientTools | Out-Null
$requestPath = Join-Path $clientTools 'windower_command_request.txt'

Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $requestPath -Value $request -NoNewline -Encoding ASCII

$deadline = (Get-Date).AddSeconds([Math]::Max(1, $WaitSeconds))
do {
    Start-Sleep -Milliseconds 250
    if (-not (Test-Path -LiteralPath $requestPath)) {
        [pscustomobject]@{
            Submitted = $true
            ForegroundVerified = $true
            RequestPath = $requestPath
            Request = $request
            OriginalText = $Text
        } | ConvertTo-Json -Compress
        exit 0
    }
} while ((Get-Date) -lt $deadline)

[pscustomobject]@{
    Submitted = $false
    ForegroundVerified = $true
    RequestPath = $requestPath
    Request = $request
    OriginalText = $Text
    Error = 'MochiriiScreenshotQA did not consume the command request before the timeout.'
} | ConvertTo-Json -Compress
exit 2
