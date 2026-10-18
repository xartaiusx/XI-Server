from __future__ import annotations

import os
import shutil
import subprocess
import unittest
from pathlib import Path


class LauncherPrivacyTests(unittest.TestCase):
    def test_reports_do_not_serialize_credentials_or_raw_exceptions(self) -> None:
        powershell = shutil.which("pwsh")
        if powershell is None and os.name == "nt":
            powershell = shutil.which("powershell.exe")
        if powershell is None:
            self.skipTest("PowerShell is required to inspect and evaluate its AST")
        launcher = Path(__file__).resolve().parents[1] / "Launch-Mochirii-Windower.ps1"
        script = r"""
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $env:MOCHIRII_TEST_LAUNCHER, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Launcher syntax is invalid' }
$assignments = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left.Extent.Text -eq '$redacted'
}, $true))
if ($assignments.Count -ne 1) { throw 'Expected one redacted launch report' }
$secret = [pscustomobject]@{
    server = 'synthetic-server-value'
    username = 'synthetic-username-value'
    password = 'synthetic-password-value'
}
$timestamp = 'synthetic-time'
$windowerExe = 'synthetic-windower'
$xiloaderExe = 'synthetic-xiloader'
$report = & ([scriptblock]::Create($assignments[0].Right.Extent.Text))
foreach ($field in @('Server', 'Username', 'Password')) {
    if ($report[$field] -cne '[redacted]') { throw 'Credential report field is not redacted' }
}
$json = $report | ConvertTo-Json
foreach ($value in @($secret.server, $secret.username, $secret.password)) {
    if ($json.Contains($value)) { throw 'Synthetic credential escaped into launch report' }
}
$traps = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.TrapStatementAst]
}, $true))
if ($traps.Count -ne 1) { throw 'Expected one launch failure trap' }
$failureText = $traps[0].Extent.Text
if ($failureText -match '\$_|\$secret') {
    throw 'Failure reporter must not serialize raw exception or credential data'
}
"""
        environment = dict(os.environ, MOCHIRII_TEST_LAUNCHER=str(launcher))
        result = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-Command", script],
            env=environment,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
