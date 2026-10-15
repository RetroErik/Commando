param([ValidateSet('DOS', 'SID', 'NOISE', 'ENVELOPE', 'FULL', 'TOGGLE')][string]$Mode = 'DOS')
$ErrorActionPreference = 'Stop'
$dosbox = 'C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe'
$configName = if ($Mode -eq 'TOGGLE') { 'dosbox-sid-toggle.conf' } elseif ($Mode -eq 'FULL') { 'dosbox-sid-full.conf' } elseif ($Mode -eq 'ENVELOPE') { 'dosbox-sid-envelope.conf' } elseif ($Mode -eq 'NOISE') { 'dosbox-sid-noise.conf' } elseif ($Mode -eq 'SID') { 'dosbox-sid.conf' } else { 'dosbox-cms.conf' }
$windowTitle = if ($Mode -eq 'TOGGLE') { 'CODEX SID M TOGGLE - COMMANDO' } elseif ($Mode -eq 'FULL') { 'CODEX SID FULL - COMMANDO' } elseif ($Mode -eq 'ENVELOPE') { 'CODEX SID ENVELOPE - COMMANDO' } elseif ($Mode -eq 'NOISE') { 'CODEX SID NOISE - COMMANDO' } elseif ($Mode -eq 'SID') { 'CODEX SID CMS - COMMANDO' } else { 'CODEX CMS ONLY - COMMANDO' }
$config = Join-Path $PSScriptRoot $configName
$sessionFile = Join-Path $PSScriptRoot '.last_dosbox.json'
if (Test-Path -LiteralPath $sessionFile) {
    try {
        $previous = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
        $old = Get-Process -Id ([int]$previous.Id) -ErrorAction SilentlyContinue
        if ($old -and $old.ProcessName -eq 'DOSBox' -and
            $old.StartTime.ToUniversalTime().Ticks -eq [long]$previous.StartTicks) {
            Stop-Process -Id $old.Id
        }
    }
    catch {
        Write-Warning "Could not close the previous Codex DOSBox session: $_"
    }
}
$process = Start-Process -FilePath $dosbox -ArgumentList ('-conf "' + $config + '"') -WindowStyle Normal -PassThru
Start-Sleep -Seconds 5
$process.Refresh()
if ($process.HasExited -or $process.MainWindowHandle -eq [IntPtr]::Zero) {
    throw 'The Codex DOSBox window did not open.'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CodexWindow {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetWindowText(IntPtr hWnd, string text);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
'@
[CodexWindow]::SetWindowText($process.MainWindowHandle, $windowTitle) | Out-Null
[CodexWindow]::SetWindowPos($process.MainWindowHandle, [IntPtr]::Zero, 80, 80, 0, 0, 0x15) | Out-Null
@{ Id = $process.Id; StartTicks = $process.StartTime.ToUniversalTime().Ticks } |
    ConvertTo-Json | Set-Content -LiteralPath $sessionFile -Encoding UTF8
Write-Host "Started Codex CMS test in DOSBox (PID $($process.Id))."
