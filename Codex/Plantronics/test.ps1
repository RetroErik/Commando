$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$test = Join-Path $project 'test'
$dosbox = 'C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe'
$bin = 'C:\FPC\3.2.2\bin\i386-Win32'
if (-not (Test-Path -LiteralPath $dosbox)) { throw "DOSBox not found: $dosbox" }
$exe = [IO.File]::ReadAllBytes((Join-Path $project 'run\COMMANDO.EXE'))
$dat = [IO.File]::ReadAllBytes((Join-Path $project 'run\COMMANDO.DAT'))
# Keep the original scrolling-ground creation and object compositing code.
foreach ($entry in @(@(0x54A9, 0xE8), @(0x5776, 0x8A), @(0x5799, 0xD3), @(0x57E1, 0x2B))) {
    $at = $entry[0]
    if ($exe[$at] -ne $entry[1] -or $dat[0x2000 + $at] -ne $entry[1]) {
        throw ('Scrolling-ground code changed at {0:X4}.' -f $at)
    }
}
foreach ($asset in @(
    @{ Kind = 'menu'; Offset = 0x1b46 },
    @{ Kind = 'enemy'; Offset = 0xa362 },
    @{ Kind = 'hero'; Offset = 0xc2fc },
    @{ Kind = 'rock'; Offset = 0xf8ea },
    @{ Kind = 'effects'; Offset = 0x1059a }
)) {
    $pixels = [IO.File]::ReadAllBytes((Join-Path $project ($asset.Kind + '_low.bin')))
    for ($index = 0; $index -lt $pixels.Length; $index++) {
        if ($exe[$asset.Offset + $index] -ne $pixels[$index] -or
            $dat[0x2000 + $asset.Offset + $index] -ne $pixels[$index]) {
            throw ("$($asset.Kind) sprite bytes differ between generated data, EXE, and DAT.")
        }
    }
}
if ($exe[0x1b71] -ne 0x55 -or $dat[0x3b71] -ne 0x55 -or
    $exe[0x502f] -ne 1 -or $dat[0x702f] -ne 1) {
    throw 'Menu brown pixels or text did not map to CGA green value 1.'
}
$launcher = [IO.File]::ReadAllBytes((Join-Path $project 'run\STARTC0.COM'))
if ($launcher[0xc4] -ne 0x21 -or $launcher[0xc5] -ne 0x24) {
    throw 'The copied launcher banner was not suppressed safely.'
}
$heroHigh = [IO.File]::ReadAllBytes((Join-Path $project 'hero_high.bin'))
$heroLow = [IO.File]::ReadAllBytes((Join-Path $project 'hero_low.bin'))
if ($heroLow[0x17] -ne 0x2b -or $heroHigh[0x17] -ne 3 -or
    $heroLow[119] -ne 0 -or $heroHigh[119] -ne 0) {
    throw 'Hero white detail or black belt differs from the selected palette.'
}
$effectLow = [IO.File]::ReadAllBytes((Join-Path $project 'effects_low.bin'))
$effectHigh = [IO.File]::ReadAllBytes((Join-Path $project 'effects_high.bin'))
if ($effectLow[5] -ne 0xf0 -or $effectHigh[5] -ne 0xf0) {
    throw 'White projectile pixel differs from the selected palette.'
}
New-Item -ItemType Directory -Path $test -Force | Out-Null
Push-Location $project
try {
    & (Join-Path $bin 'as.exe') --32 -o (Join-Path $test 'test_stub.o') 'test_assets_stub.s'
    if ($LASTEXITCODE -ne 0) { throw 'Test stub assembly failed.' }
    & (Join-Path $bin 'ld.exe') -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o (Join-Path $test 'test_stub.pe') (Join-Path $test 'test_stub.o')
    if ($LASTEXITCODE -ne 0) { throw 'Test stub link failed.' }
    & (Join-Path $bin 'objcopy.exe') -O binary -j .text (Join-Path $test 'test_stub.pe') (Join-Path $test 'STARTC0.COM')
    if ($LASTEXITCODE -ne 0) { throw 'Test stub COM extraction failed.' }
    & (Join-Path $bin 'as.exe') --32 -o (Join-Path $test 'speaker_probe.o') 'speaker_probe.s'
    if ($LASTEXITCODE -ne 0) { throw 'Speaker probe assembly failed.' }
    & (Join-Path $bin 'ld.exe') -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o (Join-Path $test 'speaker_probe.pe') (Join-Path $test 'speaker_probe.o')
    if ($LASTEXITCODE -ne 0) { throw 'Speaker probe link failed.' }
    & (Join-Path $bin 'objcopy.exe') -O binary -j .text (Join-Path $test 'speaker_probe.pe') (Join-Path $test 'SPEAKER.COM')
    if ($LASTEXITCODE -ne 0) { throw 'Speaker probe COM extraction failed.' }
}
finally {
    Pop-Location
}
Copy-Item -LiteralPath (Join-Path $project 'PLANTRON.COM') -Destination (Join-Path $test 'STARTC.COM') -Force
$output = Join-Path $test 'RESULT.OUT'
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
$trace = Join-Path $test 'PLTRACE.TXT'
if (Test-Path -LiteralPath $trace) { Remove-Item -LiteralPath $trace }
$config = Join-Path $test 'smoke.conf'
$mount = $test.Replace('\', '/')
@"
[sdl]
fullscreen=false
[autoexec]
@echo off
mount c "$mount"
c:
STARTC.COM > RESULT.OUT
SPEAKER.COM >> RESULT.OUT
exit
"@ | Set-Content -LiteralPath $config -Encoding ascii
$process = Start-Process -FilePath $dosbox -ArgumentList ('-conf "' + $config + '"') -PassThru -WindowStyle Hidden
if (-not $process.WaitForExit(60000)) {
    Stop-Process -Id $process.Id
    throw 'DOSBox smoke test timed out.'
}
if ($process.ExitCode -ne 0) { throw "DOSBox exited with code $($process.ExitCode)." }
$result = Get-Content -LiteralPath $output -Raw
if ($result -notmatch 'PASS: precolored assets, paired copy, black background, play clears, and round exit\.') { throw "Unexpected DOSBox output: $result" }
if ($result -notmatch 'PASS: speaker off after loader exit\.') { throw "Unexpected speaker result: $result" }
$traceText = Get-Content -LiteralPath $trace -Raw
if ($traceText -notmatch 'Child returned: type=00 code=00 mode=01 frames=000B copy=0B' -or
    $traceText -notmatch 'Scene builds: 03' -or
    $traceText -notmatch 'Other clears: 01' -or
    $traceText -notmatch 'Intro clears: 01' -or
    $traceText -notmatch 'Attract starts: 01' -or
    $traceText -notmatch 'Player starts: 01') { throw "Unexpected loader trace: $traceText" }
Write-Host $result.Trim()
Push-Location $project
try {
    & (Join-Path $bin 'as.exe') --32 -o (Join-Path $test 'test_leave.o') 'test_leave_stub.s'
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay exit stub assembly failed.' }
    & (Join-Path $bin 'ld.exe') -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o (Join-Path $test 'test_leave.pe') (Join-Path $test 'test_leave.o')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay exit stub link failed.' }
    & (Join-Path $bin 'objcopy.exe') -O binary -j .text (Join-Path $test 'test_leave.pe') (Join-Path $test 'STARTC0.COM')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay exit COM extraction failed.' }
}
finally {
    Pop-Location
}
Remove-Item -LiteralPath $output, $trace
$process = Start-Process -FilePath $dosbox -ArgumentList ('-conf "' + $config + '"') -PassThru -WindowStyle Hidden
if (-not $process.WaitForExit(60000)) {
    Stop-Process -Id $process.Id
    throw 'DOSBox gameplay exit test timed out.'
}
if ($process.ExitCode -ne 0) { throw "DOSBox exited with code $($process.ExitCode)." }
$result = Get-Content -LiteralPath $output -Raw
$traceText = Get-Content -LiteralPath $trace -Raw
if ($result -notmatch 'PASS: both state exits clear video and resume at original jump targets\.' -or
    $traceText -notmatch 'Attract leaves: 01' -or
    $traceText -notmatch 'Player leaves: 01') {
    throw "Gameplay exit test failed: $result $traceText"
}
Write-Host $result.Trim()
Remove-Item -LiteralPath (Join-Path $test 'test_stub.o'), (Join-Path $test 'test_stub.pe'),
    (Join-Path $test 'speaker_probe.o'), (Join-Path $test 'speaker_probe.pe'),
    (Join-Path $test 'test_leave.o'), (Join-Path $test 'test_leave.pe'),
    (Join-Path $test 'STARTC.COM'), (Join-Path $test 'STARTC0.COM'),
    (Join-Path $test 'SPEAKER.COM'), $config, $output, $trace
