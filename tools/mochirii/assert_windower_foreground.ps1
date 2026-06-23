param(
    [int]$WaitSeconds = 0
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ForegroundWindowInfo
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@

$allowedProcessNames = @(
    'Windower',
    'xiloader',
    'pol',
    'polboot',
    'polcore',
    'ffximain'
)

function Get-ForegroundSnapshot {
    $handle = [ForegroundWindowInfo]::GetForegroundWindow()
    $processId = 0
    [void][ForegroundWindowInfo]::GetWindowThreadProcessId($handle, [ref]$processId)

    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][ForegroundWindowInfo]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

    $process = $null
    if ($processId -ne 0) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    }

    $processName = if ($process) { $process.ProcessName } else { '' }
    $isWindowerClient = $allowedProcessNames -contains $processName

    [pscustomobject]@{
        IsWindowerClient = $isWindowerClient
        ProcessId        = $processId
        ProcessName      = $processName
        WindowTitle      = $titleBuilder.ToString()
        AllowedNames     = $allowedProcessNames -join ','
    }
}

$deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
do {
    $snapshot = Get-ForegroundSnapshot
    if ($snapshot.IsWindowerClient) {
        $snapshot | ConvertTo-Json -Compress
        exit 0
    }

    if ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
} while ((Get-Date) -lt $deadline)

$snapshot | ConvertTo-Json -Compress
exit 2
