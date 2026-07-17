param(
    [string] $Text = '',

    [switch] $PressEnterBefore,
    [switch] $PressSpaceBefore,
    [switch] $PressEnterAfter,
    [switch] $NoClearInputBefore,
    [string[]] $KeySequence = @(),
    [switch] $KeepForeground,
    [int] $EscapeCount = 0,
    [int] $KeyDelayMs = 35
)

$ErrorActionPreference = 'Stop'

$normalizedText = $Text.Trim()
if ($normalizedText -match '^/attack$')
{
    throw 'Refusing to send bare /attack because it can leave Final Fantasy XI in target-selection mode. Use an explicit target or a safer GM/QA command.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assertScript = Join-Path $PSScriptRoot 'assert_windower_foreground.ps1'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class MochiriiFocusWindow
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
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
    $handle = [MochiriiFocusWindow]::GetForegroundWindow()
    $processId = 0
    [void][MochiriiFocusWindow]::GetWindowThreadProcessId($handle, [ref]$processId)

    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][MochiriiFocusWindow]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

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

if ($targetWindow -eq $null)
{
    throw 'Could not find a Windower/xiloader/Final Fantasy XI client window to foreground.'
}

$previousForegroundHandle = [MochiriiFocusWindow]::GetForegroundWindow()

[void][MochiriiFocusWindow]::ShowWindow($targetWindow.MainWindowHandle, 9)
Start-Sleep -Milliseconds 250
for ($i = 0; $i -lt 8; $i++)
{
    $foregroundHandle = [MochiriiFocusWindow]::GetForegroundWindow()
    $foregroundProcessId = 0
    $targetProcessId = 0
    $foregroundThreadId = [MochiriiFocusWindow]::GetWindowThreadProcessId($foregroundHandle, [ref]$foregroundProcessId)
    $targetThreadId = [MochiriiFocusWindow]::GetWindowThreadProcessId($targetWindow.MainWindowHandle, [ref]$targetProcessId)
    $currentThreadId = [MochiriiFocusWindow]::GetCurrentThreadId()

    if ($foregroundThreadId -ne 0) { [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $foregroundThreadId, $true) }
    if ($targetThreadId -ne 0) { [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $targetThreadId, $true) }

    [void][MochiriiFocusWindow]::BringWindowToTop($targetWindow.MainWindowHandle)
    [void][MochiriiFocusWindow]::SetActiveWindow($targetWindow.MainWindowHandle)
    [void][MochiriiFocusWindow]::SetForegroundWindow($targetWindow.MainWindowHandle)

    if ($targetThreadId -ne 0) { [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $targetThreadId, $false) }
    if ($foregroundThreadId -ne 0) { [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $foregroundThreadId, $false) }

    Start-Sleep -Milliseconds 250

    $focusCheck = Get-MochiriiForegroundSnapshot
    if ($focusCheck.IsWindowerClient)
    {
        $focusCheck | ConvertTo-Json -Compress | Write-Output
        break
    }

    if ($i -eq 7)
    {
        $focusCheck | ConvertTo-Json -Compress | Write-Output
        exit 2
    }
}

function Assert-MochiriiForeground
{
    $focusCheck = Get-MochiriiForegroundSnapshot
    if (-not $focusCheck.IsWindowerClient)
    {
        $focusCheck | ConvertTo-Json -Compress | Write-Output
        throw 'Final Fantasy XI client lost foreground focus before command entry.'
    }
}

function Restore-MochiriiPreviousForeground
{
    param([IntPtr] $Handle)

    if (
        $KeepForeground -or
        $Handle -eq [IntPtr]::Zero -or
        -not [MochiriiFocusWindow]::IsWindow($Handle)
    )
    {
        return $false
    }

    $currentHandle = [MochiriiFocusWindow]::GetForegroundWindow()
    if ($currentHandle -eq $Handle)
    {
        return $true
    }

    $currentProcessId = 0
    $previousProcessId = 0
    $currentThreadId = [MochiriiFocusWindow]::GetCurrentThreadId()
    $foregroundThreadId = [MochiriiFocusWindow]::GetWindowThreadProcessId($currentHandle, [ref]$currentProcessId)
    $previousThreadId = [MochiriiFocusWindow]::GetWindowThreadProcessId($Handle, [ref]$previousProcessId)

    if ($foregroundThreadId -ne 0)
    {
        [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $foregroundThreadId, $true)
    }
    if ($previousThreadId -ne 0)
    {
        [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $previousThreadId, $true)
    }

    try
    {
        [void][MochiriiFocusWindow]::BringWindowToTop($Handle)
        [void][MochiriiFocusWindow]::SetActiveWindow($Handle)
        [void][MochiriiFocusWindow]::SetForegroundWindow($Handle)
    }
    finally
    {
        if ($previousThreadId -ne 0)
        {
            [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $previousThreadId, $false)
        }
        if ($foregroundThreadId -ne 0)
        {
            [void][MochiriiFocusWindow]::AttachThreadInput($currentThreadId, $foregroundThreadId, $false)
        }
    }

    Start-Sleep -Milliseconds 100
    return [MochiriiFocusWindow]::GetForegroundWindow() -eq $Handle
}

$source = @'
using System;
using System.Runtime.InteropServices;

public static class MochiriiSendInput
{
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public uint padding;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)]
        public MOUSEINPUT mi;

        [FieldOffset(0)]
        public KEYBDINPUT ki;

        [FieldOffset(0)]
        public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern short VkKeyScan(char ch);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    public const uint INPUT_KEYBOARD = 1;
    public const uint MAPVK_VK_TO_VSC = 0;
    public const uint KEYEVENTF_SCANCODE = 0x0008;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const ushort VK_SHIFT = 0x10;
    public const ushort VK_CONTROL = 0x11;
    public const ushort VK_MENU = 0x12;
    public const ushort VK_TAB = 0x09;
    public const ushort VK_RETURN = 0x0D;
    public const ushort VK_ESCAPE = 0x1B;
    public const ushort VK_SPACE = 0x20;
    public const ushort VK_LEFT = 0x25;
    public const ushort VK_UP = 0x26;
    public const ushort VK_RIGHT = 0x27;
    public const ushort VK_DOWN = 0x28;

    public static void Key(ushort vk, bool up)
    {
        var scanCode = (ushort)MapVirtualKey(vk, MAPVK_VK_TO_VSC);
        if (scanCode == 0)
        {
            throw new InvalidOperationException("Cannot map virtual key to scan code: " + vk);
        }

        var input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wVk = 0;
        input.U.ki.wScan = scanCode;
        input.U.ki.dwFlags = KEYEVENTF_SCANCODE | (up ? KEYEVENTF_KEYUP : 0);
        input.U.ki.time = 0;
        input.U.ki.dwExtraInfo = IntPtr.Zero;
        var sent = SendInput(1, new INPUT[] { input }, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@

Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue

function Send-Key([uint16] $vk)
{
    [MochiriiSendInput]::Key($vk, $false)
    Start-Sleep -Milliseconds $KeyDelayMs
    [MochiriiSendInput]::Key($vk, $true)
    Start-Sleep -Milliseconds $KeyDelayMs
}

function Send-NamedKey([string] $name)
{
    $normalizedName = $name.Trim().ToLowerInvariant()
    $virtualKey = switch ($normalizedName)
    {
        'enter'  { [MochiriiSendInput]::VK_RETURN; break }
        'return' { [MochiriiSendInput]::VK_RETURN; break }
        'tab'    { [MochiriiSendInput]::VK_TAB; break }
        'escape' { [MochiriiSendInput]::VK_ESCAPE; break }
        'esc'    { [MochiriiSendInput]::VK_ESCAPE; break }
        'space'  { [MochiriiSendInput]::VK_SPACE; break }
        'left'   { [MochiriiSendInput]::VK_LEFT; break }
        'up'     { [MochiriiSendInput]::VK_UP; break }
        'right'  { [MochiriiSendInput]::VK_RIGHT; break }
        'down'   { [MochiriiSendInput]::VK_DOWN; break }
        default  { throw "Unsupported named key '$name'." }
    }

    Send-Key $virtualKey
}

function Send-TextChar([char] $ch)
{
    $scan = [MochiriiSendInput]::VkKeyScan($ch)
    if ($scan -eq -1)
    {
        throw "Cannot map character '$ch' to a virtual key."
    }

    $vk = [uint16]($scan -band 0xff)
    $mods = ($scan -shr 8) -band 0xff

    if (($mods -band 1) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_SHIFT, $false) }
    if (($mods -band 2) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_CONTROL, $false) }
    if (($mods -band 4) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_MENU, $false) }

    Send-Key $vk

    if (($mods -band 4) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_MENU, $true) }
    if (($mods -band 2) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_CONTROL, $true) }
    if (($mods -band 1) -ne 0) { [MochiriiSendInput]::Key([MochiriiSendInput]::VK_SHIFT, $true) }
}

Assert-MochiriiForeground

if (-not $NoClearInputBefore)
{
    Send-Key ([MochiriiSendInput]::VK_ESCAPE)
    Start-Sleep -Milliseconds 75
    Send-Key ([MochiriiSendInput]::VK_ESCAPE)
    Start-Sleep -Milliseconds 75
}

if ($PressEnterBefore)
{
    Send-Key ([MochiriiSendInput]::VK_RETURN)
}

for ($i = 0; $i -lt $EscapeCount; $i++)
{
    Send-Key ([MochiriiSendInput]::VK_ESCAPE)
    Start-Sleep -Milliseconds 75
}

Assert-MochiriiForeground

if ($PressSpaceBefore)
{
    Send-Key ([MochiriiSendInput]::VK_SPACE)
}

Start-Sleep -Milliseconds 100
Assert-MochiriiForeground

foreach ($ch in $Text.ToCharArray())
{
    Send-TextChar $ch
}

if ($PressEnterAfter)
{
    Send-Key ([MochiriiSendInput]::VK_RETURN)
}

foreach ($keyName in $KeySequence)
{
    Assert-MochiriiForeground
    Send-NamedKey $keyName
}

Start-Sleep -Milliseconds 250
$finalClientFocus = Get-MochiriiForegroundSnapshot
$previousForegroundRestored = Restore-MochiriiPreviousForeground -Handle $previousForegroundHandle

[pscustomobject]@{
    Submitted                  = $true
    ControlMode               = 'ForegroundDirectInputFallback'
    PreviousForegroundRestored = [bool]$previousForegroundRestored
    KeptForeground            = [bool]$KeepForeground
    KeySequence               = @($KeySequence)
    FinalClientFocus          = $finalClientFocus
} | ConvertTo-Json -Depth 4 -Compress | Write-Output
