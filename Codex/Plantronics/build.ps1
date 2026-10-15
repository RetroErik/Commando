$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$bin = 'C:\FPC\3.2.2\bin\i386-Win32'
$assembler = Join-Path $bin 'as.exe'
$linker = Join-Path $bin 'ld.exe'
$objcopy = Join-Path $bin 'objcopy.exe'
foreach ($tool in @($assembler, $linker, $objcopy)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Required tool missing: $tool" }
}

& (Join-Path $project 'sprite_assets.ps1')
& (Join-Path $project 'menu_assets.ps1')
& (Join-Path $project 'screen_palette.ps1')

Push-Location $project
try {
    & $assembler --32 -o 'plantronics.o' 'plantronics.s'
    if ($LASTEXITCODE -ne 0) { throw 'Assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x100 -e start -o 'plantronics.pe' 'plantronics.o'
    if ($LASTEXITCODE -ne 0) { throw 'Link failed.' }
    & $objcopy -O binary -j .text 'plantronics.pe' 'PLANTRON.COM'
    if ($LASTEXITCODE -ne 0) { throw 'COM extraction failed.' }
    & $assembler --32 -o 'launcher_probe.o' 'launcher_probe.s'
    if ($LASTEXITCODE -ne 0) { throw 'Launcher probe assembly failed.' }
    & $linker -m i386pe --image-base 0 --section-alignment 1 --file-alignment 1 -Ttext 0x2e0 -e probe_exec -o 'launcher_probe.pe' 'launcher_probe.o'
    if ($LASTEXITCODE -ne 0) { throw 'Launcher probe link failed.' }
    & $objcopy -O binary -j .text 'launcher_probe.pe' 'launcher_probe.bin'
    if ($LASTEXITCODE -ne 0) { throw 'Launcher probe extraction failed.' }
}
finally {
    Pop-Location
}
$length = (Get-Item -LiteralPath (Join-Path $project 'PLANTRON.COM')).Length
if ($length -gt 65280) { throw "COM exceeds DOS limit: $length bytes." }
& (Join-Path $project 'patch.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Patch step failed.' }
Remove-Item -LiteralPath (Join-Path $project 'plantronics.o'), (Join-Path $project 'plantronics.pe'),
    (Join-Path $project 'launcher_probe.o'), (Join-Path $project 'launcher_probe.pe')
Write-Host "Built Plantronics loader ($length bytes) and version-checked game copies."
