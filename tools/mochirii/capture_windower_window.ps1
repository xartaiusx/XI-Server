param(
    [string] $OutputPath = (Join-Path $PWD 'windower-native-screenshot.jpg'),
    [string] $MetadataPath,
    [ValidateSet('xipivot', 'jasmint', 'remapster', 'dgvoodoo2', 'reshade')]
    [string] $EvidenceGate,
    [ValidateSet('jpg', 'png', 'bmp')]
    [string] $Format = 'jpg',
    [switch] $HideWindowerObjects,
    [switch] $RequireForeground,
    [ValidateRange(1, 100)]
    [int] $MinimumClientCoveragePercent = 95,
    [ValidateRange(1, 120)]
    [int] $TimeoutSeconds = 12
)

$ErrorActionPreference = 'Stop'

$assertScript = Join-Path $PSScriptRoot 'assert_windower_foreground.ps1'
$commandScript = Join-Path $PSScriptRoot 'Invoke-WindowerCommand.ps1'
$windowerRoot = 'D:\Steam\steamapps\common\FFXINA\Windower'
$screenshotRoot = Join-Path $windowerRoot 'screenshots'
$triggerPath = "C:\Github Repo's\FFXI\Runtime\screenshots\native_screenshot_request.txt"
$screenshotAckRoot = "C:\Github Repo's\FFXI\Runtime\screenshots\native-screenshot-acks"
$runtimeManifestRoot = "C:\Github Repo's\FFXI\Runtime\manifests"
$runtimeScreenshotRoot = "C:\Github Repo's\FFXI\Runtime\screenshots"
$ackPath = $null
$previousForegroundHandle = [IntPtr]::Zero
$previousForegroundRestored = $false

function Assert-MochiriiContainedWritePath
{
    param(
        [string] $Candidate,
        [string] $Root
    )

    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $rootBase = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $rootPrefix = $rootBase + '\'
    if (-not $candidateFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "Evidence path escaped its canonical root: $Candidate"
    }

    $relative = $candidateFull.Substring($rootPrefix.Length)
    if ($relative -match ':')
    {
        throw "Evidence paths may not use alternate data streams: $Candidate"
    }

    $rootItem = Get-Item -LiteralPath $rootBase -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    {
        throw "Evidence root may not be a reparse point: $rootBase"
    }

    $current = $rootBase
    foreach ($component in ($relative -split '[\\/]' | Where-Object { $_ }))
    {
        $current = Join-Path $current $component
        if (-not (Test-Path -LiteralPath $current))
        {
            break
        }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        {
            throw "Evidence path may not traverse a reparse point: $current"
        }
    }

    return $candidateFull
}

if ($MetadataPath)
{
    if (-not $EvidenceGate)
    {
        throw 'EvidenceGate is required whenever MetadataPath is used.'
    }

    $MetadataPath = Assert-MochiriiContainedWritePath -Candidate $MetadataPath -Root $runtimeManifestRoot
    $OutputPath = Assert-MochiriiContainedWritePath -Candidate $OutputPath -Root $runtimeScreenshotRoot
    if ([System.IO.Path]::GetExtension($MetadataPath) -ine '.json')
    {
        throw 'MetadataPath must be a JSON file under the canonical Runtime\manifests directory.'
    }
    if ($MetadataPath -ieq $OutputPath)
    {
        throw 'MetadataPath and OutputPath must be distinct.'
    }
}

$captureMutex = New-Object System.Threading.Mutex($false, 'Local\MochiriiNativeScreenshotCapture')
$mutexAcquired = $false

try
{
    $mutexAcquired = $captureMutex.WaitOne(0)
    if (-not $mutexAcquired)
    {
        throw 'Another native Windower screenshot capture is already running.'
    }

if ($RequireForeground -and -not (Test-Path -LiteralPath $assertScript))
{
    throw "Missing foreground helper: $assertScript"
}

if (-not (Test-Path -LiteralPath $commandScript))
{
    throw "Missing Windower command helper: $commandScript"
}

New-Item -ItemType Directory -Force -Path $screenshotRoot | Out-Null
New-Item -ItemType Directory -Force -Path $screenshotAckRoot | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class MochiriiNativeScreenshotFocus
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
'@ -ErrorAction SilentlyContinue

$allowedProcessNames = @(
    'Windower',
    'xiloader',
    'pol',
    'polboot',
    'polcore',
    'ffximain'
)

function Get-MochiriiForegroundSnapshot
{
    $handle = [MochiriiNativeScreenshotFocus]::GetForegroundWindow()
    $processId = 0
    [void][MochiriiNativeScreenshotFocus]::GetWindowThreadProcessId($handle, [ref]$processId)

    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][MochiriiNativeScreenshotFocus]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

    $process = $null
    if ($processId -ne 0)
    {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    }

    $processName = if ($process) { $process.ProcessName } else { '' }

    [pscustomobject]@{
        IsWindowerClient = $allowedProcessNames -contains $processName
        ProcessId        = $processId
        ProcessName      = $processName
        WindowTitle      = $titleBuilder.ToString()
        AllowedNames     = $allowedProcessNames -join ','
    }
}

$targetWindow = Get-Process -Name xiloader, Windower, pol, polboot, polcore, ffximain -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -match 'Twills|FINAL FANTASY|PlayOnline|Windower') } |
    Sort-Object @{ Expression = { if ($_.MainWindowTitle -match 'Twills') { 0 } else { 1 } } }, ProcessName |
    Select-Object -First 1

if ($null -eq $targetWindow)
{
    throw 'Could not find a Windower/xiloader/Final Fantasy XI client window to foreground for native screenshot.'
}

$clientProcessStartedAtUtc = $targetWindow.StartTime.ToUniversalTime()
$clientProcessStartedAtOffset = [DateTimeOffset]$clientProcessStartedAtUtc
$sessionId = 'windower-{0}-{1}' -f $targetWindow.Id, $clientProcessStartedAtOffset.ToUnixTimeMilliseconds()

if ($RequireForeground)
{
    [void][MochiriiNativeScreenshotFocus]::ShowWindow($targetWindow.MainWindowHandle, 9)
    Start-Sleep -Milliseconds 250
    for ($i = 0; $i -lt 8; $i++)
    {
        [MochiriiNativeScreenshotFocus]::keybd_event([MochiriiNativeScreenshotFocus]::VK_MENU, 0, 0, [UIntPtr]::Zero)
        [MochiriiNativeScreenshotFocus]::keybd_event([MochiriiNativeScreenshotFocus]::VK_MENU, 0, [MochiriiNativeScreenshotFocus]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
        [void][MochiriiNativeScreenshotFocus]::SetForegroundWindow($targetWindow.MainWindowHandle)
        Start-Sleep -Milliseconds 250

        $preCheck = Get-MochiriiForegroundSnapshot
        if ($preCheck.IsWindowerClient -and $preCheck.ProcessId -eq $targetWindow.Id)
        {
            break
        }
    }

    $focusCheck = Get-MochiriiForegroundSnapshot
    if (-not $focusCheck.IsWindowerClient -or $focusCheck.ProcessId -ne $targetWindow.Id)
    {
        $focusCheck | ConvertTo-Json -Compress | Write-Output
        throw 'Refusing screenshot: Windower/xiloader is not the foreground client.'
    }

    $focusCheck | ConvertTo-Json -Compress | Write-Output
}

function Restore-MochiriiForegroundWindow
{
    param([IntPtr] $Handle)

    if (
        $Handle -eq [IntPtr]::Zero -or
        -not [MochiriiNativeScreenshotFocus]::IsWindow($Handle)
    )
    {
        return $false
    }

    $currentHandle = [MochiriiNativeScreenshotFocus]::GetForegroundWindow()
    if ($currentHandle -eq $Handle)
    {
        return $true
    }

    $currentProcessId = 0
    $previousProcessId = 0
    $currentThreadId = [MochiriiNativeScreenshotFocus]::GetCurrentThreadId()
    $foregroundThreadId = [MochiriiNativeScreenshotFocus]::GetWindowThreadProcessId($currentHandle, [ref]$currentProcessId)
    $previousThreadId = [MochiriiNativeScreenshotFocus]::GetWindowThreadProcessId($Handle, [ref]$previousProcessId)

    if ($foregroundThreadId -ne 0)
    {
        [void][MochiriiNativeScreenshotFocus]::AttachThreadInput($currentThreadId, $foregroundThreadId, $true)
    }
    if ($previousThreadId -ne 0)
    {
        [void][MochiriiNativeScreenshotFocus]::AttachThreadInput($currentThreadId, $previousThreadId, $true)
    }

    try
    {
        [void][MochiriiNativeScreenshotFocus]::BringWindowToTop($Handle)
        [void][MochiriiNativeScreenshotFocus]::SetActiveWindow($Handle)
        [void][MochiriiNativeScreenshotFocus]::SetForegroundWindow($Handle)
    }
    finally
    {
        if ($previousThreadId -ne 0)
        {
            [void][MochiriiNativeScreenshotFocus]::AttachThreadInput($currentThreadId, $previousThreadId, $false)
        }
        if ($foregroundThreadId -ne 0)
        {
            [void][MochiriiNativeScreenshotFocus]::AttachThreadInput($currentThreadId, $foregroundThreadId, $false)
        }
    }

    Start-Sleep -Milliseconds 100
    return [MochiriiNativeScreenshotFocus]::GetForegroundWindow() -eq $Handle
}

$previousForegroundHandle = [MochiriiNativeScreenshotFocus]::GetForegroundWindow()

$clientRect = New-Object MochiriiNativeScreenshotFocus+RECT
[void][MochiriiNativeScreenshotFocus]::GetClientRect($targetWindow.MainWindowHandle, [ref]$clientRect)
$clientWidth = [Math]::Max(0, $clientRect.Right - $clientRect.Left)
$clientHeight = [Math]::Max(0, $clientRect.Bottom - $clientRect.Top)
$windowDpi = 96
try
{
    $reportedDpi = [MochiriiNativeScreenshotFocus]::GetDpiForWindow($targetWindow.MainWindowHandle)
    if ($reportedDpi -gt 0)
    {
        $windowDpi = [int]$reportedDpi
    }
}
catch
{
    $windowDpi = 96
}

$dpiScale = [Math]::Max(1.0, $windowDpi / 96.0)
$expectedImageWidth = [int][Math]::Round($clientWidth * $dpiScale)
$expectedImageHeight = [int][Math]::Round($clientHeight * $dpiScale)
$coverageRatio = [Math]::Min(100, [Math]::Max(1, $MinimumClientCoveragePercent)) / 100.0
$minimumImageWidth = [int][Math]::Floor($expectedImageWidth * $coverageRatio)
$minimumImageHeight = [int][Math]::Floor($expectedImageHeight * $coverageRatio)

$extension = ".$Format"
$requestedOutput = $OutputPath
if ([System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -ne $extension)
{
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, $Format)
}
if ($MetadataPath)
{
    $OutputPath = Assert-MochiriiContainedWritePath -Candidate $OutputPath -Root $runtimeScreenshotRoot
}

$before = @{}
Get-ChildItem -LiteralPath $screenshotRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -ieq $extension } |
    ForEach-Object { $before[$_.FullName] = $_.LastWriteTimeUtc }

function Get-NativeScreenshotCandidate
{
    param(
        [datetime] $SinceUtc,
        [hashtable] $Seen,
        [string] $Root,
        [string] $Extension
    )

    Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -ieq $Extension -and
            $_.LastWriteTimeUtc -ge $SinceUtc.AddSeconds(-5) -and
            ((-not $Seen.ContainsKey($_.FullName)) -or $Seen[$_.FullName] -ne $_.LastWriteTimeUtc) -and
            (Test-Path -LiteralPath $_.FullName)
        } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

$command = "screenshot $Format"
if ($HideWindowerObjects)
{
    $command += ' hide'
}

$requestDirectory = Split-Path -Parent $triggerPath
New-Item -ItemType Directory -Force -Path $requestDirectory | Out-Null
$requestTimeUtc = (Get-Date).ToUniversalTime()
$requestId = [Guid]::NewGuid().ToString('N')
$ackPath = Join-Path $screenshotAckRoot "$requestId.txt"
$request = "id=$requestId`nformat=$Format`nhide=$([bool]$HideWindowerObjects)"
Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ackPath -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $triggerPath -Value $request -Encoding ASCII

$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
$nativeScreenshot = $null
do
{
    Start-Sleep -Milliseconds 350
    $candidate = Get-NativeScreenshotCandidate -SinceUtc $requestTimeUtc -Seen $before -Root $screenshotRoot -Extension $extension
    if ($null -ne $candidate -and (Test-Path -LiteralPath $ackPath) -and (Get-Content -Raw -LiteralPath $ackPath).Trim() -eq $requestId)
    {
        $nativeScreenshot = $candidate
    }
} while ($null -eq $nativeScreenshot -and (Get-Date) -lt $deadline)

if ($null -eq $nativeScreenshot)
{
    # Mochirii sessions autoload the bridge from Windower\scripts\init.txt.
    # Reload once so a session that predates a helper update cannot keep using
    # an unacknowledged screenshot protocol.
    try
    {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $commandScript -Text '//lua reload MochiriiScreenshotQA'
        if ($LASTEXITCODE -ne 0)
        {
            throw "Background addon-load request failed with exit code $LASTEXITCODE."
        }
    }
    catch
    {
        throw 'Could not reload MochiriiScreenshotQA in Windower.'
    }

    $requestTimeUtc = (Get-Date).ToUniversalTime()
    $requestId = [Guid]::NewGuid().ToString('N')
    $ackPath = Join-Path $screenshotAckRoot "$requestId.txt"
    $request = "id=$requestId`nformat=$Format`nhide=$([bool]$HideWindowerObjects)"
    Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ackPath -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $triggerPath -Value $request -Encoding ASCII
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))

    do
    {
        Start-Sleep -Milliseconds 350
        $candidate = Get-NativeScreenshotCandidate -SinceUtc $requestTimeUtc -Seen $before -Root $screenshotRoot -Extension $extension
        if ($null -ne $candidate -and (Test-Path -LiteralPath $ackPath) -and (Get-Content -Raw -LiteralPath $ackPath).Trim() -eq $requestId)
        {
            $nativeScreenshot = $candidate
        }
    } while ($null -eq $nativeScreenshot -and (Get-Date) -lt $deadline)

    if ($null -eq $nativeScreenshot)
    {
        throw "Timed out waiting for Windower native screenshot under $screenshotRoot."
    }
}

Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing
$imageWidth = 0
$imageHeight = 0
$image = $null
$readError = $null
for ($attempt = 1; $attempt -le 10; $attempt++)
{
    try
    {
        $image = [System.Drawing.Image]::FromFile($nativeScreenshot.FullName)
        $imageWidth = $image.Width
        $imageHeight = $image.Height
        $readError = $null
        break
    }
    catch
    {
        $readError = $_
        Start-Sleep -Milliseconds 350
    }
    finally
    {
        if ($null -ne $image)
        {
            $image.Dispose()
            $image = $null
        }
    }
}

if ($null -ne $readError)
{
    throw $readError
}

if ($clientWidth -gt 0 -and $clientHeight -gt 0 -and ($imageWidth -lt $minimumImageWidth -or $imageHeight -lt $minimumImageHeight))
{
    throw "Windower native screenshot is smaller than the live client. Captured ${imageWidth}x${imageHeight}; expected at least ${minimumImageWidth}x${minimumImageHeight} from client ${clientWidth}x${clientHeight} at DPI $windowDpi. Refusing to use a cropped or stale screenshot."
}

$copiedPath = $null
if ($OutputPath)
{
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory)
    {
        New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    }

    Copy-Item -LiteralPath $nativeScreenshot.FullName -Destination $OutputPath -Force
    $copiedPath = (Resolve-Path -LiteralPath $OutputPath).Path
}

$previousForegroundRestored = Restore-MochiriiForegroundWindow -Handle $previousForegroundHandle
$evidencePath = if ($copiedPath) { $copiedPath } else { $nativeScreenshot.FullName }
$screenshotSha256 = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
$capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
$nativeLastWriteTimeUtc = [DateTimeOffset]$nativeScreenshot.LastWriteTimeUtc

$result = [pscustomobject]@{
    CaptureMode = 'WindowerNativeScreenshot'
    CaptureBridgeVersion = '1.2.0'
    ControlMode = if ($RequireForeground) { 'ForegroundBridge' } else { 'BackgroundBridge' }
    ForegroundRequired = [bool]$RequireForeground
    PreviousForegroundRestored = [bool]$previousForegroundRestored
    Command = "MochiriiScreenshotQA -> $command"
    NativePath = $nativeScreenshot.FullName
    CopiedPath = $copiedPath
    RequestedOutput = $requestedOutput
    Format = $Format
    ImageWidth = $imageWidth
    ImageHeight = $imageHeight
    ClientWidth = $clientWidth
    ClientHeight = $clientHeight
    WindowDpi = $windowDpi
    MinimumClientCoveragePercent = $MinimumClientCoveragePercent
    HideWindowerObjects = [bool]$HideWindowerObjects
    EvidenceGate = $EvidenceGate
    SessionId = $sessionId
    ClientProcessId = $targetWindow.Id
    ClientProcessName = $targetWindow.ProcessName
    ClientProcessStartedAtUtc = $clientProcessStartedAtOffset.ToString('o')
    RequestId = $requestId
    RequestAcknowledged = $true
    CapturedAtUtc = $capturedAtUtc
    NativeLastWriteTimeUtc = $nativeLastWriteTimeUtc.ToString('o')
    ScreenshotSha256 = $screenshotSha256
    MetadataPath = $MetadataPath
}

if ($MetadataPath)
{
    $metadataDirectory = Split-Path -Parent $MetadataPath
    if ($metadataDirectory)
    {
        New-Item -ItemType Directory -Force -Path $metadataDirectory | Out-Null
    }

    $temporaryMetadataPath = Join-Path $metadataDirectory ('.{0}.{1}.tmp' -f ([System.IO.Path]::GetFileName($MetadataPath)), [Guid]::NewGuid().ToString('N'))
    $metadataJson = ($result | ConvertTo-Json -Depth 4) + [Environment]::NewLine
    try
    {
        [System.IO.File]::WriteAllText($temporaryMetadataPath, $metadataJson, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryMetadataPath -Destination $MetadataPath -Force
    }
    finally
    {
        Remove-Item -LiteralPath $temporaryMetadataPath -Force -ErrorAction SilentlyContinue
    }
}

$result | Format-List
}
finally
{
    Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
    if ($ackPath)
    {
        Remove-Item -LiteralPath $ackPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $previousForegroundRestored -and $previousForegroundHandle -ne [IntPtr]::Zero)
    {
        try
        {
            $previousForegroundRestored = Restore-MochiriiForegroundWindow -Handle $previousForegroundHandle
        }
        catch
        {
            Write-Warning "Could not restore the previous foreground window: $($_.Exception.Message)"
        }
    }
    if ($mutexAcquired)
    {
        [void]$captureMutex.ReleaseMutex()
    }
    $captureMutex.Dispose()
}
