param(
    [Parameter(Mandatory)][string] $SourceVhd,
    [Parameter(Mandatory)][string] $OutputVhd
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceVhd).Path
$output = [IO.Path]::GetFullPath($OutputVhd)
if ($source -eq $output) { throw 'Use a separate output VHD.' }
$vhd = [IO.File]::ReadAllBytes($source)
if ([Text.Encoding]::ASCII.GetString($vhd, 0, 8) -ne 'conectix' -or
    [Text.Encoding]::ASCII.GetString($vhd, 512, 8) -ne 'cxsparse') {
    throw 'Expected a dynamic VHD.'
}
function Read-Be32([int] $at) {
    return [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($vhd, $at))
}
function Read-Be64([int] $at) {
    return [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt64($vhd, $at))
}
$bat = [int](Read-Be64 (512 + 16))
$blockBytes = Read-Be32 (512 + 32)
$maxBlocks = Read-Be32 (512 + 28)
$bitmapBytes = [int][Math]::Ceiling([Math]::Ceiling($blockBytes / 512.0) / 8.0 / 512.0) * 512
if ($blockBytes -ne 2097152 -or $maxBlocks -lt 3) { throw 'Unexpected VHD block layout.' }
function Map-Virtual([long] $virtual) {
    $block = [int][Math]::Floor($virtual / $blockBytes)
    if ($block -ge $maxBlocks) { throw 'VHD offset is out of range.' }
    $sector = Read-Be32 ($bat + $block * 4)
    if ($sector -eq -1) { throw 'The requested VHD block is not allocated.' }
    $physical = [long]$sector * 512 + $bitmapBytes + ($virtual % $blockBytes)
    if ($physical -ge $vhd.Length) { throw 'VHD mapping is out of range.' }
    return [int]$physical
}
function Read-Virtual16([long] $at) {
    $lo = $vhd[(Map-Virtual $at)]
    $hi = $vhd[(Map-Virtual ($at + 1))]
    return [int]$lo + ([int]$hi -shl 8)
}
function Read-Virtual32([long] $at) {
    $value = 0L
    for ($byte = 0; $byte -lt 4; $byte++) {
        $value = $value -bor ([long]$vhd[(Map-Virtual ($at + $byte))] -shl (8 * $byte))
    }
    return $value
}

$partitionLba = Read-Virtual32 454
$partition = $partitionLba * 512
$bps = Read-Virtual16 ($partition + 11)
$spc = [int]$vhd[(Map-Virtual ($partition + 13))]
$reserved = Read-Virtual16 ($partition + 14)
$fatCount = [int]$vhd[(Map-Virtual ($partition + 16))]
$rootEntries = Read-Virtual16 ($partition + 17)
$sectorsPerFat = Read-Virtual16 ($partition + 22)
if ($partitionLba -ne 17 -or $bps -ne 512 -or $spc -ne 4 -or
    $reserved -ne 1 -or $fatCount -ne 2 -or $rootEntries -ne 512 -or
    $sectorsPerFat -ne 255) { throw 'Unexpected EuroPC FAT16 layout.' }
$root = $partition + ($reserved + $fatCount * $sectorsPerFat) * $bps
$data = $root + $rootEntries * 32
$entry = -1L
for ($index = 0; $index -lt $rootEntries; $index++) {
    $candidate = $root + $index * 32
    $first = $vhd[(Map-Virtual $candidate)]
    if ($first -eq 0) { break }
    if ($first -eq 0xe5) { continue }
    $name = [byte[]]::new(11)
    for ($byte = 0; $byte -lt 11; $byte++) { $name[$byte] = $vhd[(Map-Virtual ($candidate + $byte))] }
    if ([Text.Encoding]::ASCII.GetString($name) -eq 'AUTOEXECBAT') {
        $entry = $candidate
        break
    }
}
if ($entry -lt 0) { throw 'AUTOEXEC.BAT is missing.' }
$cluster = Read-Virtual16 ($entry + 26)
$oldSize = Read-Virtual32 ($entry + 28)
if ($cluster -ne 2013 -or $oldSize -ne 29) { throw 'Unexpected AUTOEXEC.BAT location or length.' }
$file = $data + ($cluster - 2) * $spc * $bps
$old = [byte[]]::new($oldSize)
for ($index = 0; $index -lt $oldSize; $index++) { $old[$index] = $vhd[(Map-Virtual ($file + $index))] }
$oldText = [Text.Encoding]::ASCII.GetString($old)
if ($oldText -notmatch '(?i)Prompt \$P\$g' -or $oldText -notmatch '(?i)Path=c:\\;c:\\util') {
    throw "Unexpected AUTOEXEC.BAT content: $oldText"
}
$lines = @('@ECHO OFF', 'PROMPT $P$G', 'PATH C:\;C:\UTIL', 'A:', 'STARTC.COM', '')
$text = $lines -join "`r`n"
$new = [Text.Encoding]::ASCII.GetBytes($text)
if ($new.Length -gt $spc * $bps) { throw 'AUTOEXEC.BAT exceeds its original cluster.' }
for ($index = 0; $index -lt $new.Length; $index++) {
    $vhd[(Map-Virtual ($file + $index))] = $new[$index]
}
for ($index = 0; $index -lt 4; $index++) {
    $vhd[(Map-Virtual ($entry + 28 + $index))] = [byte](($new.Length -shr (8 * $index)) -band 255)
}
[IO.File]::WriteAllBytes($output, $vhd)
Write-Host "Created EuroPC autoboot copy: $output"
