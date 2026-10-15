# Launch DOSBox 0.74-3 with a mounted folder + command, optionally send keys, take PNG screenshots, close.
# Usage: .\dosbox_shot.ps1 -Dir <folder> -Run "STARTC.COM" -Shots @(@{At=6;Keys=''},...) -Out <folder> [-Cycles 12000] [-Machine vgaonly]
param(
    [Parameter(Mandatory)][string]$Dir,
    [string]$Run = 'STARTC.COM',
    [Parameter(Mandatory)][string]$Out,
    # Each step: @{ At = seconds-since-start; Keys = 'SendKeys string' (optional); Shot = $true/$false }
    [object[]]$Steps = @(@{ At = 8; Shot = $true }),
    [int]$Total = 12,
    [string]$Cycles = 'fixed 4000',
    [string]$Machine = 'vgaonly',
    [string]$Conf = $null,
    [string]$Sb = 'none',            # sound card: none | sb16 (AdLib/OPL) | gb (CMS Game Blaster)
    [string]$PcSpeaker = 'false',
    [string]$NoSound = 'true',
    [string]$Memsize = '16'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Win { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  public static void Hold(byte vk, int ms, bool ext) { byte sc=(byte)MapVirtualKey(vk,0); uint f = ext ? 1u : 0u; keybd_event(vk, sc, f, UIntPtr.Zero); System.Threading.Thread.Sleep(ms); keybd_event(vk, sc, f|2u, UIntPtr.Zero); } }
'@
$dosbox = if ($env:DOSBOX_EXE) { $env:DOSBOX_EXE } else { 'C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe' }
New-Item -ItemType Directory -Force $Out | Out-Null
$cap = Join-Path $Out 'raw'
Remove-Item $cap -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $cap | Out-Null
if (-not $Conf) {
    $Conf = Join-Path $Out 'dosbox.conf'
    @"
[sdl]
fullscreen=false
windowresolution=640x400
output=surface
[dosbox]
machine=$Machine
memsize=$Memsize
captures=$cap
[cpu]
core=normal
cycles=$Cycles
[speaker]
pcspeaker=$PcSpeaker
[sblaster]
sbtype=$Sb
sbbase=220
irq=7
dma=1
oplmode=auto
[mixer]
nosound=$NoSound
[autoexec]
mount c "$Dir"
c:
$Run
"@ | Set-Content -Path $Conf -Encoding ASCII
}
$p = Start-Process -FilePath $dosbox -ArgumentList ('-conf "' + $Conf + '" -noconsole') -PassThru
$t0 = Get-Date
try {
    foreach ($s in ($Steps | Sort-Object { $_.At })) {
        $wait = $s.At - ((Get-Date) - $t0).TotalSeconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
        $p.Refresh()
        if ($p.HasExited) { Write-Warning 'DOSBox exited early'; break }
        [Win]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 150
        if ($s.Hold) { [Win]::Hold([byte]$s.Hold, [int]$(if ($s.Ms) { $s.Ms } else { 250 }), [bool]$s.Ext); Start-Sleep -Milliseconds 300 }
        if ($s.Keys) { [System.Windows.Forms.SendKeys]::SendWait($s.Keys); Start-Sleep -Milliseconds 300 }
        if ($s.Rec) { [System.Windows.Forms.SendKeys]::SendWait('^%{F6}'); Start-Sleep -Milliseconds 500 }
        if ($s.Shot) { [System.Windows.Forms.SendKeys]::SendWait('^{F5}'); Start-Sleep -Milliseconds 700 }
    }
    $rest = $Total - ((Get-Date) - $t0).TotalSeconds
    if ($rest -gt 0) { Start-Sleep -Milliseconds ([int]($rest * 1000)) }
}
finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}
Get-ChildItem $cap | ForEach-Object { $_.FullName }

