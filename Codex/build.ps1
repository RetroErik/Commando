$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$assembler = 'C:\FPC\3.2.2\bin\i386-Win32\as.exe'
$linker = 'C:\FPC\3.2.2\bin\i386-Win32\ld.exe'
$objcopy = 'C:\FPC\3.2.2\bin\i386-Win32\objcopy.exe'
if (-not (Test-Path -LiteralPath $assembler) -or -not (Test-Path -LiteralPath $linker) -or -not (Test-Path -LiteralPath $objcopy)) {
    throw 'GNU as.exe, ld.exe, and objcopy.exe from Free Pascal 3.2.2 are required at C:\FPC\3.2.2\bin\i386-Win32.'
}
$object = Join-Path $project 'cmsrun.o'
$linked = Join-Path $project 'cmsrun.pe'
$output = Join-Path $project 'run\CMSRUN.COM'
$sidObject = Join-Path $project 'sidrun.o'
$sidLinked = Join-Path $project 'sidrun.pe'
$sidOutput = Join-Path $project 'run-sid\SIDRUN.COM'
$noiseObject = Join-Path $project 'sidnoise.o'
$noiseLinked = Join-Path $project 'sidnoise.pe'
$noiseOutput = Join-Path $project 'run-sid-noise\SIDNOISE.COM'
$envelopeObject = Join-Path $project 'sidenvelope.o'
$envelopeLinked = Join-Path $project 'sidenvelope.pe'
$envelopeOutput = Join-Path $project 'run-sid-envelope\SIDENV.COM'
$fullObject = Join-Path $project 'sidfull.o'
$fullLinked = Join-Path $project 'sidfull.pe'
$fullOutput = Join-Path $project 'run-sid-full\SIDFULL.COM'
$toggleObject = Join-Path $project 'sidtoggle.o'
$toggleLinked = Join-Path $project 'sidtoggle.pe'
$toggleOutput = Join-Path $project 'run-sid-toggle\SIDTOG.COM'
$fullScore = Join-Path $project 'tools\SidDump\sidmusic-envelope-full.bin'
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run-sid') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run-sid-noise') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run-sid-envelope') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run-sid-full') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $project 'run-sid-toggle') | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $project 'tools\SidDump\sidmusic.bin'))) {
    & (Join-Path $project 'tools\SidDump\generate-sid-score.ps1')
}
if (-not (Test-Path -LiteralPath (Join-Path $project 'tools\SidDump\sidmusic-envelope-4m.bin'))) {
    & (Join-Path $project 'tools\SidDump\generate-sid-envelope-score.ps1')
}
if (-not (Test-Path -LiteralPath $fullScore)) {
    & (Join-Path $project 'tools\SidDump\generate-sid-full-score.ps1')
}
if ((Get-Item -LiteralPath $fullScore).Length -ne 113907) { throw 'Unexpected full SID envelope score size; update the loader block sizes.' }
Push-Location $project
try {
    & $assembler --32 --defsym SID_MODE=0 -o $object 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'DOS mode assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $linked $object
    if ($LASTEXITCODE -ne 0) { throw 'DOS mode link failed.' }
    & $objcopy -O binary -j .text $linked $output
    if ($LASTEXITCODE -ne 0) { throw 'DOS mode COM extraction failed.' }
    Copy-Item -LiteralPath $output -Destination (Join-Path $project 'run\STARTC.COM') -Force

    & $assembler --32 --defsym SID_MODE=1 -o $sidObject 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'SID mode assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $sidLinked $sidObject
    if ($LASTEXITCODE -ne 0) { throw 'SID mode link failed.' }
    & $objcopy -O binary -j .text $sidLinked $sidOutput
    if ($LASTEXITCODE -ne 0) { throw 'SID mode COM extraction failed.' }
    Copy-Item -LiteralPath $sidOutput -Destination (Join-Path $project 'run-sid\STARTC.COM') -Force

    & $assembler --32 --defsym SID_MODE=2 -o $noiseObject 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'SID clocked-noise assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $noiseLinked $noiseObject
    if ($LASTEXITCODE -ne 0) { throw 'SID clocked-noise link failed.' }
    & $objcopy -O binary -j .text $noiseLinked $noiseOutput
    if ($LASTEXITCODE -ne 0) { throw 'SID clocked-noise COM extraction failed.' }
    Copy-Item -LiteralPath $noiseOutput -Destination (Join-Path $project 'run-sid-noise\STARTC.COM') -Force

    & $assembler --32 --defsym SID_MODE=3 -o $envelopeObject 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'SID envelope assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $envelopeLinked $envelopeObject
    if ($LASTEXITCODE -ne 0) { throw 'SID envelope link failed.' }
    & $objcopy -O binary -j .text $envelopeLinked $envelopeOutput
    if ($LASTEXITCODE -ne 0) { throw 'SID envelope COM extraction failed.' }
    if ((Get-Item -LiteralPath $envelopeOutput).Length -gt 65280) { throw 'SID envelope COM exceeds the 64 KB DOS limit.' }
    Copy-Item -LiteralPath $envelopeOutput -Destination (Join-Path $project 'run-sid-envelope\STARTC.COM') -Force

    & $assembler --32 --defsym SID_MODE=4 -o $fullObject 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'SID full-score assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $fullLinked $fullObject
    if ($LASTEXITCODE -ne 0) { throw 'SID full-score link failed.' }
    & $objcopy -O binary -j .text $fullLinked $fullOutput
    if ($LASTEXITCODE -ne 0) { throw 'SID full-score COM extraction failed.' }
    Copy-Item -LiteralPath $fullOutput -Destination (Join-Path $project 'run-sid-full\STARTC.COM') -Force
    Copy-Item -LiteralPath $fullScore -Destination (Join-Path $project 'run-sid-full\SIDENV.BIN') -Force

    & $assembler --32 --defsym SID_MODE=5 -o $toggleObject 'cmsrun.s'
    if ($LASTEXITCODE -ne 0) { throw 'SID music-toggle assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o $toggleLinked $toggleObject
    if ($LASTEXITCODE -ne 0) { throw 'SID music-toggle link failed.' }
    & $objcopy -O binary -j .text $toggleLinked $toggleOutput
    if ($LASTEXITCODE -ne 0) { throw 'SID music-toggle COM extraction failed.' }
    Copy-Item -LiteralPath $toggleOutput -Destination (Join-Path $project 'run-sid-toggle\STARTC.COM') -Force
    Copy-Item -LiteralPath $fullScore -Destination (Join-Path $project 'run-sid-toggle\SIDENV.BIN') -Force
}
finally {
    Pop-Location
}
Write-Host "Built $output, $sidOutput, $noiseOutput, $envelopeOutput, $fullOutput, and $toggleOutput"
