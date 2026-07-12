param(
    [string] $OutputPath = (Join-Path $PWD 'windower-native-screenshot.jpg'),
    [ValidateSet('jpg', 'png', 'bmp')]
    [string] $Format = 'jpg',
    [switch] $HideWindowerObjects,
    [int] $MinimumClientCoveragePercent = 95,
    [int] $TimeoutSeconds = 12
)

$ErrorActionPreference = 'Stop'

$assertScript = Join-Path $PSScriptRoot 'assert_windower_foreground.ps1'
$sendScript = Join-Path $PSScriptRoot 'send_windower_text.ps1'
$windowerRoot = 'D:\Steam\steamapps\common\FFXINA\Windower'
$screenshotRoot = Join-Path $windowerRoot 'screenshots'
$triggerPath = "C:\Github Repo's\FFXI\Runtime\screenshots\native_screenshot_request.txt"

if (-not (Test-Path -LiteralPath $assertScript))
{
    throw "Missing foreground helper: $assertScript"
}

if (-not (Test-Path -LiteralPath $sendScript))
{
    throw "Missing Windower input helper: $sendScript"
}

New-Item -ItemType Directory -Force -Path $screenshotRoot | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class MochiriiNativeScreenshotFocus
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

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

[void][MochiriiNativeScreenshotFocus]::ShowWindow($targetWindow.MainWindowHandle, 9)
Start-Sleep -Milliseconds 250
for ($i = 0; $i -lt 8; $i++)
{
    [MochiriiNativeScreenshotFocus]::keybd_event([MochiriiNativeScreenshotFocus]::VK_MENU, 0, 0, [UIntPtr]::Zero)
    [MochiriiNativeScreenshotFocus]::keybd_event([MochiriiNativeScreenshotFocus]::VK_MENU, 0, [MochiriiNativeScreenshotFocus]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [void][MochiriiNativeScreenshotFocus]::SetForegroundWindow($targetWindow.MainWindowHandle)
    Start-Sleep -Milliseconds 250

    $preCheck = Get-MochiriiForegroundSnapshot
    if ($preCheck.IsWindowerClient)
    {
        break
    }
}

$focusCheck = Get-MochiriiForegroundSnapshot
if (-not $focusCheck.IsWindowerClient)
{
    $focusCheck | ConvertTo-Json -Compress | Write-Output
    throw 'Refusing screenshot: Windower/xiloader is not the foreground client.'
}

$focusCheck | ConvertTo-Json -Compress | Write-Output

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
$request = "id=$requestId`nformat=$Format`nhide=$([bool]$HideWindowerObjects)"
Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $triggerPath -Value $request -Encoding ASCII

$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
$nativeScreenshot = $null
do
{
    Start-Sleep -Milliseconds 350
    $nativeScreenshot = Get-NativeScreenshotCandidate -SinceUtc $requestTimeUtc -Seen $before -Root $screenshotRoot -Extension $extension
} while ($null -eq $nativeScreenshot -and (Get-Date) -lt $deadline)

if ($null -eq $nativeScreenshot)
{
    # Most Mochirii sessions autoload the bridge from Windower\scripts\init.txt.
    # If this session does not have it yet, load it once as a fallback and retry.
    try
    {
        & $sendScript -Text "//lua load MochiriiScreenshotQA" -PressSpaceBefore -PressEnterAfter -EscapeCount 1
    }
    catch
    {
        throw 'Could not load MochiriiScreenshotQA in Windower.'
    }

    $requestTimeUtc = (Get-Date).ToUniversalTime()
    $requestId = [Guid]::NewGuid().ToString('N')
    $request = "id=$requestId`nformat=$Format`nhide=$([bool]$HideWindowerObjects)"
    Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $triggerPath -Value $request -Encoding ASCII
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))

    do
    {
        Start-Sleep -Milliseconds 350
        $nativeScreenshot = Get-NativeScreenshotCandidate -SinceUtc $requestTimeUtc -Seen $before -Root $screenshotRoot -Extension $extension
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

[pscustomobject]@{
    CaptureMode = 'WindowerNativeScreenshot'
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
} | Format-List
