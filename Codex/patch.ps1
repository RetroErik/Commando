$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\Original game files'
$target = Join-Path $PSScriptRoot 'run'
$sidTarget = Join-Path $PSScriptRoot 'run-sid'
$noiseTarget = Join-Path $PSScriptRoot 'run-sid-noise'
$envelopeTarget = Join-Path $PSScriptRoot 'run-sid-envelope'
$fullTarget = Join-Path $PSScriptRoot 'run-sid-full'
$toggleTarget = Join-Path $PSScriptRoot 'run-sid-toggle'
$exeSource = Join-Path $source 'COMMANDO.EXE'
$exeTarget = Join-Path $target 'COMMANDO.EXE'
$datSource = Join-Path $source 'COMMANDO.DAT'
$datTarget = Join-Path $target 'COMMANDO.DAT'
$expectedHash = '4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E'
$expectedDatHash = 'E92EC0D64715DEADA88495E5415634FDE05B155C3EDEDAE2B0E00844A26AAAE9'
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exeSource).Hash
if ($actualHash -ne $expectedHash) { throw "Unsupported COMMANDO.EXE (SHA-256 $actualHash)." }
$actualDatHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $datSource).Hash
if ($actualDatHash -ne $expectedDatHash) { throw "Unsupported COMMANDO.DAT (SHA-256 $actualDatHash)." }

# Exact sites in the 1987-02-25 version 1.01 EXE, including its original overlay.
$gateOffsets = @(0x68BD, 0x68F5, 0x694E, 0x69A1, 0x69BD, 0x69F2, 0x6A6F, 0x6A95, 0x6AC5, 0x6B41, 0x6B8E)
$pitchOffsets = @(0x6A89, 0x6A8D, 0x6B82, 0x6B86, 0x6BDA, 0x6BDE)
$bytes = [IO.File]::ReadAllBytes($exeSource)
$datBytes = [IO.File]::ReadAllBytes($datSource)
$embeddedOffset = 0x2000
if ($embeddedOffset + $bytes.Length -gt $datBytes.Length) { throw 'DAT does not contain the expected embedded EXE.' }
for ($index = 0; $index -lt $bytes.Length; $index++) {
    if ($bytes[$index] -ne $datBytes[$embeddedOffset + $index]) { throw ('DAT embedded EXE mismatch at {0:X5}.' -f $index) }
}
foreach ($offset in $gateOffsets) {
    if ($bytes[$offset] -ne 0xE6 -or $bytes[$offset + 1] -ne 0x61) { throw ('Unexpected gate bytes at {0:X5}.' -f $offset) }
    $bytes[$offset] = 0xCD
    $bytes[$offset + 1] = 0x60
    $datBytes[$embeddedOffset + $offset] = 0xCD
    $datBytes[$embeddedOffset + $offset + 1] = 0x60
}
foreach ($offset in $pitchOffsets) {
    if ($bytes[$offset] -ne 0xE6 -or $bytes[$offset + 1] -ne 0x42) { throw ('Unexpected pitch bytes at {0:X5}.' -f $offset) }
    $bytes[$offset] = 0xCD
    $bytes[$offset + 1] = 0x61
    $datBytes[$embeddedOffset + $offset] = 0xCD
    $datBytes[$embeddedOffset + $offset + 1] = 0x61
}
New-Item -ItemType Directory -Force -Path $target | Out-Null
[IO.File]::WriteAllBytes($exeTarget, $bytes)
[IO.File]::WriteAllBytes($datTarget, $datBytes)
Copy-Item -LiteralPath (Join-Path $source 'STARTC.COM') -Destination (Join-Path $target 'STARTC0.COM') -Force

# The SID mode also delegates the game's IRQ0 sound tick to INT 62h.
$sidExe = [byte[]]$bytes.Clone()
$sidDat = [byte[]]$datBytes.Clone()
# The game's M switch calls this setter with zero to mute its own music.
# Force that input to zero in SID mode, while leaving the separate S effects
# switch and every original speaker write available to the CMS bridge.
$musicSetterOffset = 0x6989
$musicFlagOffset = 0x6783
if ($sidExe[$musicFlagOffset] -ne 0xFF -or $sidDat[$embeddedOffset + $musicFlagOffset] -ne 0xFF) {
    throw 'Unexpected initial music flag in EXE or DAT.'
}
$sidExe[$musicFlagOffset] = 0
$sidDat[$embeddedOffset + $musicFlagOffset] = 0
$musicSetterExpected = [byte[]]@(0x8B, 0x46, 0x04)
$musicSetterPatched = [byte[]]@(0x33, 0xC0, 0x90)
for ($index = 0; $index -lt $musicSetterExpected.Length; $index++) {
    if ($sidExe[$musicSetterOffset + $index] -ne $musicSetterExpected[$index] -or
        $sidDat[$embeddedOffset + $musicSetterOffset + $index] -ne $musicSetterExpected[$index]) {
        throw 'Unexpected game music setter in EXE or DAT.'
    }
    $sidExe[$musicSetterOffset + $index] = $musicSetterPatched[$index]
    $sidDat[$embeddedOffset + $musicSetterOffset + $index] = $musicSetterPatched[$index]
}
$timerOffset = 0x848E
$timerExpected = [byte[]]@(0xE8, 0x14, 0xE7)
for ($index = 0; $index -lt $timerExpected.Length; $index++) {
    if ($sidExe[$timerOffset + $index] -ne $timerExpected[$index] -or
        $sidDat[$embeddedOffset + $timerOffset + $index] -ne $timerExpected[$index]) {
        throw 'Unexpected timer sound call in EXE or DAT.'
    }
}
$timerPatched = [byte[]]@(0xCD, 0x62, 0x90)
for ($index = 0; $index -lt $timerPatched.Length; $index++) {
    $sidExe[$timerOffset + $index] = $timerPatched[$index]
    $sidDat[$embeddedOffset + $timerOffset + $index] = $timerPatched[$index]
}
New-Item -ItemType Directory -Force -Path $sidTarget | Out-Null
[IO.File]::WriteAllBytes((Join-Path $sidTarget 'COMMANDO.EXE'), $sidExe)
[IO.File]::WriteAllBytes((Join-Path $sidTarget 'COMMANDO.DAT'), $sidDat)
Copy-Item -LiteralPath (Join-Path $source 'STARTC.COM') -Destination (Join-Path $sidTarget 'STARTC0.COM') -Force
New-Item -ItemType Directory -Force -Path $noiseTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.EXE') -Destination (Join-Path $noiseTarget 'COMMANDO.EXE') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.DAT') -Destination (Join-Path $noiseTarget 'COMMANDO.DAT') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'STARTC0.COM') -Destination (Join-Path $noiseTarget 'STARTC0.COM') -Force
New-Item -ItemType Directory -Force -Path $envelopeTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.EXE') -Destination (Join-Path $envelopeTarget 'COMMANDO.EXE') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.DAT') -Destination (Join-Path $envelopeTarget 'COMMANDO.DAT') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'STARTC0.COM') -Destination (Join-Path $envelopeTarget 'STARTC0.COM') -Force
New-Item -ItemType Directory -Force -Path $fullTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.EXE') -Destination (Join-Path $fullTarget 'COMMANDO.EXE') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'COMMANDO.DAT') -Destination (Join-Path $fullTarget 'COMMANDO.DAT') -Force
Copy-Item -LiteralPath (Join-Path $sidTarget 'STARTC0.COM') -Destination (Join-Path $fullTarget 'STARTC0.COM') -Force
New-Item -ItemType Directory -Force -Path $toggleTarget | Out-Null
$toggleExe = [byte[]]$sidExe.Clone()
$toggleDat = [byte[]]$sidDat.Clone()
$toggleSetter = [byte[]]@(0xCD, 0x63, 0x90)
for ($index = 0; $index -lt $toggleSetter.Length; $index++) {
    if ($toggleExe[$musicSetterOffset + $index] -ne $musicSetterPatched[$index] -or
        $toggleDat[$embeddedOffset + $musicSetterOffset + $index] -ne $musicSetterPatched[$index]) {
        throw 'Unexpected muted game music setter before M-toggle patch.'
    }
    $toggleExe[$musicSetterOffset + $index] = $toggleSetter[$index]
    $toggleDat[$embeddedOffset + $musicSetterOffset + $index] = $toggleSetter[$index]
}
[IO.File]::WriteAllBytes((Join-Path $toggleTarget 'COMMANDO.EXE'), $toggleExe)
[IO.File]::WriteAllBytes((Join-Path $toggleTarget 'COMMANDO.DAT'), $toggleDat)
Copy-Item -LiteralPath (Join-Path $sidTarget 'STARTC0.COM') -Destination (Join-Path $toggleTarget 'STARTC0.COM') -Force
Write-Host "Patched copies: $exeTarget and $datTarget"
Write-Host "SID-mode copies: $sidTarget"
Write-Host "SID clocked-noise copies: $noiseTarget"
Write-Host "SID envelope copies: $envelopeTarget"
Write-Host "SID full-score copies: $fullTarget"
Write-Host "SID M-toggle copies: $toggleTarget"
Write-Host 'Original game files are unchanged.'
