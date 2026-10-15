$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\Original game files')).Path
$target = Join-Path $PSScriptRoot 'run'
$exeSource = Join-Path $source 'COMMANDO.EXE'
$datSource = Join-Path $source 'COMMANDO.DAT'
$originalStart = Join-Path $source 'STARTC.COM'
$expectedExe = '4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E'
$expectedDat = 'E92EC0D64715DEADA88495E5415634FDE05B155C3EDEDAE2B0E00844A26AAAE9'
$expectedStart = '680F5BEA28E73B4251E47BF09CCA9600C9407F449808D21CE791596F0F06D2A1'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $exeSource).Hash -ne $expectedExe) { throw 'Unsupported COMMANDO.EXE version.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $datSource).Hash -ne $expectedDat) { throw 'Unsupported COMMANDO.DAT version.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $originalStart).Hash -ne $expectedStart) { throw 'Unsupported STARTC.COM version.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'PLANTRON.COM'))) { throw 'Build PLANTRON.COM first.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'launcher_probe.bin'))) { throw 'Build launcher_probe.bin first.' }
$exe = [IO.File]::ReadAllBytes($exeSource)
$dat = [IO.File]::ReadAllBytes($datSource)
$embedded = 0x2000
$start = [IO.File]::ReadAllBytes($originalStart)
$probe = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'launcher_probe.bin'))
if ($dat.Length -lt $embedded + $exe.Length) { throw 'DAT embedded EXE is truncated.' }
for ($index = 0; $index -lt $exe.Length; $index++) {
    if ($dat[$embedded + $index] -ne $exe[$index]) { throw ('DAT embedded EXE differs at {0:X5}.' -f $index) }
}

function Set-VerifiedBytes {
    param([int] $Offset, [byte[]] $Expected, [byte[]] $Replacement)
    if ($Expected.Length -ne $Replacement.Length) { throw 'Patch length mismatch.' }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        $at = $Offset + $index
        if ($exe[$at] -ne $Expected[$index]) { throw ('Unexpected EXE byte at {0:X5}.' -f $at) }
        if ($dat[$embedded + $at] -ne $Expected[$index]) { throw ('Unexpected DAT byte at {0:X5}.' -f $at) }
        $exe[$at] = $Replacement[$index]
        $dat[$embedded + $at] = $Replacement[$index]
    }
}

# Nine zero alignment bytes follow the function at 6E16h. The six-byte
# trampoline keeps the original 77EAh renderer and invokes INT 60h after it.
Set-VerifiedBytes 0x6E17 ([byte[]]@(0, 0, 0, 0, 0, 0)) ([byte[]]@(0xE8, 0xD0, 0x09, 0xCD, 0x60, 0xC3))
Set-VerifiedBytes 0x6DBC ([byte[]]@(0xE8, 0x2B, 0x0A)) ([byte[]]@(0xE8, 0x58, 0x00))
Set-VerifiedBytes 0x6C1D ([byte[]]@(0xE8, 0xF0, 0x18)) ([byte[]]@(0xCD, 0x61, 0x90))
Set-VerifiedBytes 0x6CA2 ([byte[]]@(0xE8, 0x2D, 0x0B)) ([byte[]]@(0xCD, 0x62, 0x90))
# The active-play scene clear invalidates the last image seen in video RAM.
Set-VerifiedBytes 0x618F ([byte[]]@(0xE8, 0xFE, 0x15)) ([byte[]]@(0xCD, 0x63, 0x90))
# Other screen clears must also discard the ColorPlus pixels left by play.
Set-VerifiedBytes 0x77A6 ([byte[]]@(0xF3, 0xAB)) ([byte[]]@(0xCD, 0x64))
# This clear ends the pre-play scene; gameplay starts just afterward.
Set-VerifiedBytes 0x63A5 ([byte[]]@(0xE8, 0xE8, 0x13)) ([byte[]]@(0xCD, 0x65, 0x90))
# Preserve the game's play-state initialization and mark active play only
# after the pre-play scene has returned.
Set-VerifiedBytes 0x3601 ([byte[]]@(0xC7, 0x06, 0x32, 0xFE, 0x00, 0x00)) ([byte[]]@(0xCD, 0x66, 0x90, 0x90, 0x90, 0x90))
# This back edge leaves a finished play round for the state dispatcher.
Set-VerifiedBytes 0x369B ([byte[]]@(0xE9, 0x2A, 0xFF)) ([byte[]]@(0xCD, 0x67, 0x90))
# State 04h is the player-controlled round, separate from state 02h.
Set-VerifiedBytes 0x36B1 ([byte[]]@(0xC6, 0x06, 0x19, 0xFA, 0x04)) ([byte[]]@(0xCD, 0x68, 0x90, 0x90, 0x90))
Set-VerifiedBytes 0x36F7 ([byte[]]@(0xE9, 0x92, 0xFE)) ([byte[]]@(0xCD, 0x69, 0x90))
# Only menu and high-score text color arguments change from CGA brown to
# green. The gameplay frame and score colors retain their separate palette.
foreach ($at in @(
    0x502e, 0x5069, 0x5087, 0x5099, 0x50b4, 0x50dd, 0x5105, 0x5127, 0x5131,
    0x61de, 0x6211, 0x6231, 0x6251, 0x6271, 0x62d5, 0x62de, 0x6305, 0x630e,
    0x6348, 0x6364, 0x649e
)) {
    Set-VerifiedBytes $at ([byte[]]@(0xb8, 0x03, 0x00)) ([byte[]]@(0xb8, 0x01, 0x00))
}
if (0x6DBC + 3 + [BitConverter]::ToInt16($exe, 0x6DBD) -ne 0x6E17 -or
    0x6E17 + 3 + [BitConverter]::ToInt16($exe, 0x6E18) -ne 0x77EA) {
    throw 'Frame trampoline call target mismatch.'
}

# The game's normal renderer now draws the correct lower ColorPlus bits from
# its own sprite data. Headers, masks, positions, and row dimensions remain.
foreach ($asset in @(
    @{ Kind = 'enemy'; Offset = 0xa362; Length = 0x1d52 },
    @{ Kind = 'hero'; Offset = 0xc2fc; Length = 0x1bf2 },
    @{ Kind = 'rock'; Offset = 0xf8ea; Length = 0x003e },
    @{ Kind = 'effects'; Offset = 0x1059a; Length = 0x0492 }
)) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot ($asset.Kind + '_low.bin')))
    if ($bytes.Length -ne $asset.Length) { throw "Unexpected $($asset.Kind) sprite asset length." }
    [Array]::Copy($bytes, 0, $exe, $asset.Offset, $bytes.Length)
    [Array]::Copy($bytes, 0, $dat, $embedded + $asset.Offset, $bytes.Length)
}
# The four title pieces use CGA composite-style red/brown/green stripes.
# Change brown to green without changing masks or geometry.
$menu = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'menu_low.bin'))
if ($menu.Length -ne 0x350c - 0x1b46) { throw 'Unexpected menu sprite asset length.' }
[Array]::Copy($menu, 0, $exe, 0x1b46, $menu.Length)
[Array]::Copy($menu, 0, $dat, $embedded + 0x1b46, $menu.Length)

# Preserve the original launcher's cleanup while exposing its hidden EXEC
# error and passing DOS's own floppy reads to BIOS. DOS errors return as 80h
# plus the error code.
if ($start.Length -ne 0x1e0 -or $probe.Length -lt 0x90) { throw 'Unexpected launcher or probe length.' }
if ($probe[0] -ne 0x0e -or $probe[0x40] -ne 0xb4 -or $probe[0x70] -ne 0x50) {
    throw 'Unexpected launcher probe layout.'
}
if ($start[0x66] -ne 0xcd -or $start[0x67] -ne 0x21 -or $start[0x68] -ne 0xfa -or
    $start[0xc0] -ne 0xb8 -or $start[0xc1] -ne 0 -or $start[0xc2] -ne 0x4c -or
    $start[0x46] -ne 0xb8 -or $start[0x47] -ne 0x13 -or $start[0x48] -ne 0x25 -or
    $start[0x49] -ne 0xba -or $start[0x4a] -ne 0x48 -or $start[0x4b] -ne 0x02 -or
    $start[0x4c] -ne 0xcd -or $start[0x4d] -ne 0x21 -or
    $start[0x148] -ne 0x80 -or $start[0x149] -ne 0xfa -or $start[0x14a] -ne 0 -or
    $start[0x14b] -ne 0x74 -or $start[0x14c] -ne 0x03) {
    throw 'Unexpected launcher EXEC or exit instruction.'
}
$start[0x46] = 0xe8
$start[0x47] = 0xd7
$start[0x48] = 0x01
for ($at = 0x49; $at -le 0x4d; $at++) { $start[$at] = 0x90 }
$start[0x66] = 0xe8
$start[0x67] = 0x77
$start[0x68] = 0x01
$start[0xc0] = 0xe8
$start[0xc1] = 0x4d
$start[0xc2] = 0x01
$start[0x148] = 0xe9
$start[0x149] = 0x05
$start[0x14a] = 0x01
$start[0x14b] = 0x90
$start[0x14c] = 0x90
# This copied launcher has since been modified for DOS compatibility. Hide
# the original crack banner rather than implying its author made this patch.
if ([Text.Encoding]::ASCII.GetString($start, 0xc5, 39) -ne 'Commando crack by Demonlord 05/30/99...') {
    throw 'Unexpected launcher credit text.'
}
for ($at = 0xc5; $at -lt 0xee; $at++) { $start[$at] = 0 }
$start[0xc5] = 0x24
if (0x146 + 3 + [BitConverter]::ToInt16($start, 0x47) -ne 0x320 -or
    0x166 + 3 + [BitConverter]::ToInt16($start, 0x67) -ne 0x2e0 -or
    0x1c0 + 3 + [BitConverter]::ToInt16($start, 0xc1) -ne 0x310 -or
    0x248 + 3 + [BitConverter]::ToInt16($start, 0x149) -ne 0x350) {
    throw 'Launcher probe branch target mismatch.'
}
$diagnosticStart = New-Object byte[] ($start.Length + $probe.Length)
[Array]::Copy($start, 0, $diagnosticStart, 0, $start.Length)
[Array]::Copy($probe, 0, $diagnosticStart, $start.Length, $probe.Length)

New-Item -ItemType Directory -Path $target -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $target 'COMMANDO.EXE'), $exe)
[IO.File]::WriteAllBytes((Join-Path $target 'COMMANDO.DAT'), $dat)
[IO.File]::WriteAllBytes((Join-Path $target 'STARTC0.COM'), $diagnosticStart)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PLANTRON.COM') -Destination (Join-Path $target 'STARTC.COM') -Force
Write-Host "Patched copies in $target. Originals are unchanged."
