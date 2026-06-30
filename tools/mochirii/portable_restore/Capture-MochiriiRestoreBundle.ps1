param(
    [string]$RepoRoot = "C:\Users\xtyty\Documents\FFXI\XI-Server",
    [string]$RuntimeRoot = "C:\Users\xtyty\Documents\FFXI-Runtime",
    [string]$WindowerRoot = "D:\Steam\steamapps\common\FFXINA\Windower",
    [string]$MariaDbBin = "C:\Program Files\MariaDB 12.3\bin",
    [string]$MariaDbDefaults = "C:\Program Files\MariaDB 12.3\data\my.ini",
    [string]$DatabaseName = "xidb",
    [string]$DatabaseUser = "root",
    [string]$DatabasePassword = "root",
    [switch]$SkipDatabase,
    [switch]$SkipWindower
)

$ErrorActionPreference = "Stop"

$artifactRoot = Join-Path $RuntimeRoot "portable-restore\artifacts"
$secretRoot = Join-Path $RuntimeRoot "secrets"
$logRoot = Join-Path $RuntimeRoot "logs\portable-restore"
New-Item -ItemType Directory -Force -Path $artifactRoot, $secretRoot, $logRoot | Out-Null

function Test-TcpPort {
    param([int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $result = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(700, $false)) { return $false }
        $client.EndConnect($result)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Invoke-Wsl {
    param([string]$Command)
    & wsl.exe bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: $Command"
    }
}

function ConvertTo-WslPath {
    param([string]$Path)
    return (& wsl.exe wslpath -a $Path).Trim()
}

function New-RestorePassphrase {
    param([string]$Prefix, [string]$Stamp)
    $path = Join-Path $secretRoot "$Prefix-$Stamp.passphrase.txt"
    Invoke-Wsl "openssl rand -base64 48 > '$(ConvertTo-WslPath $path)' && chmod 600 '$(ConvertTo-WslPath $path)'"
    return $path
}

function Start-MariaDbIfNeeded {
    if (Test-TcpPort -Port 3306) {
        return $false
    }

    Start-Process -FilePath (Join-Path $MariaDbBin "mariadbd.exe") `
        -ArgumentList "--defaults-file=`"$MariaDbDefaults`"" `
        -RedirectStandardOutput (Join-Path $logRoot "mariadb-capture.stdout.log") `
        -RedirectStandardError (Join-Path $logRoot "mariadb-capture.stderr.log") `
        -WindowStyle Minimized

    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        if (Test-TcpPort -Port 3306) {
            return $true
        }
    }

    throw "MariaDB did not start on 127.0.0.1:3306."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$captured = [ordered]@{
    capturedAt = (Get-Date).ToString("o")
    repoRoot = $RepoRoot
    runtimeRoot = $RuntimeRoot
    windowerRoot = $WindowerRoot
    artifacts = @()
}

if (-not $SkipDatabase -or -not $SkipWindower) {
    try {
        Invoke-Wsl "command -v openssl >/dev/null && command -v gzip >/dev/null && command -v tar >/dev/null"
    } catch {
        throw "WSL crypto/archive tools were not reachable from PowerShell. Run tools\mochirii\portable_restore\capture_windows_from_wsl.sh from WSL, or install/repair WSL openssl, gzip, and tar for this PowerShell session."
    }
}

if (-not $SkipDatabase) {
    $startedMariaDb = Start-MariaDbIfNeeded
    $dbPassphrase = New-RestorePassphrase -Prefix "mochirii-restore-db" -Stamp $stamp
    $artifact = Join-Path $artifactRoot "xidb-twills-$stamp.sql.gz.enc"
    $artifactWsl = ConvertTo-WslPath $artifact
    $passWsl = ConvertTo-WslPath $dbPassphrase
    $dumpExe = (ConvertTo-WslPath (Join-Path $MariaDbBin "mariadb-dump.exe")).Replace("'", "'\''")
    $dbPasswordSafe = $DatabasePassword.Replace("'", "'\''")
    $dumpCommand = "'$dumpExe' -u$DatabaseUser --password='$dbPasswordSafe' -h127.0.0.1 -P3306 --databases $DatabaseName --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 --add-drop-database --add-drop-table --add-drop-trigger | gzip -9 | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass file:'$passWsl' -out '$artifactWsl'"
    Invoke-Wsl $dumpCommand
    Invoke-Wsl "sha256sum '$artifactWsl' > '$artifactWsl.sha256'"

    $captured.artifacts += [ordered]@{
        kind = "database"
        database = $DatabaseName
        artifact = Split-Path -Leaf $artifact
        bytes = (Get-Item $artifact).Length
        sha256 = Get-Sha256 $artifact
        passphrasePath = $dbPassphrase
        plaintextCommitted = $false
    }

    if ($startedMariaDb) {
        & (Join-Path $MariaDbBin "mysqladmin.exe") -u$DatabaseUser --password=$DatabasePassword -h127.0.0.1 -P3306 shutdown | Out-Null
    }
}

if (-not $SkipWindower) {
    $goldenRoot = Join-Path $RuntimeRoot "windower-golden-state"
    if (-not (Test-Path $goldenRoot)) {
        throw "Missing Windower golden state at $goldenRoot"
    }

    $windowerPassphrase = New-RestorePassphrase -Prefix "mochirii-restore-windower" -Stamp $stamp
    $artifact = Join-Path $artifactRoot "windower-golden-state-$stamp.tar.gz.enc"
    $artifactWsl = ConvertTo-WslPath $artifact
    $passWsl = ConvertTo-WslPath $windowerPassphrase
    $runtimeWsl = ConvertTo-WslPath $RuntimeRoot
    Invoke-Wsl "tar -C '$runtimeWsl' -czf - windower-golden-state | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass file:'$passWsl' -out '$artifactWsl'"
    Invoke-Wsl "sha256sum '$artifactWsl' > '$artifactWsl.sha256'"

    $captured.artifacts += [ordered]@{
        kind = "windower-golden-state"
        artifact = Split-Path -Leaf $artifact
        bytes = (Get-Item $artifact).Length
        sha256 = Get-Sha256 $artifact
        passphrasePath = $windowerPassphrase
        plaintextCommitted = $false
    }
}

$manifestPath = Join-Path $artifactRoot "portable-restore-capture-$stamp.manifest.json"
$captured | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $manifestPath
Write-Host "Capture manifest: $manifestPath"
