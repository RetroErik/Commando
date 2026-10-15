$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$source = Join-Path $project '..\..\Original game files\COMMANDO.EXE'
$expected = '4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $expected) {
    throw 'Unsupported COMMANDO.EXE version.'
}
$exe = [IO.File]::ReadAllBytes($source)
$first = 0x1b46
$last = 0x350c
$menu = New-Object byte[] ($last - $first)
[Array]::Copy($exe, $first, $menu, 0, $menu.Length)
$expectedStarts = @(0x1b46, 0x20c8, 0x242a, 0x2864, 0x2e3e, 0x350c)
for ($id = 0; $id -lt 5; $id++) {
    $at = [BitConverter]::ToUInt16($exe, 0x1b3c + 2 * $id) + 0x200
    if ($at -ne $expectedStarts[$id]) { throw "Unexpected menu sprite $id offset." }
    $height = [int]$exe[$at]
    $width = [int]$exe[$at + 1]
    if ($at + 2 + 2 * $height * $width -ne $expectedStarts[$id + 1]) {
        throw "Unexpected menu sprite $id dimensions."
    }
    for ($byteIndex = 0; $byteIndex -lt $height * $width; $byteIndex++) {
        $mask = [int]$exe[$at + 2 + 2 * $byteIndex]
        $valueAt = $at + 3 + 2 * $byteIndex
        $value = [int]$exe[$valueAt]
        $mapped = 0
        foreach ($shift in @(0, 2, 4, 6)) {
            $maskPair = ($mask -shr $shift) -band 3
            $pixel = ($value -shr $shift) -band 3
            if ($maskPair -ne 0 -and $maskPair -ne 3) { throw 'Unexpected menu pixel mask.' }
            if ($maskPair -eq 0) {
                # In the game's CGA palette, value 1 is green and value 2
                # is red. Replace brown with green in the title and soldier,
                # keeping the existing red and green pixels distinct.
                if ($pixel -eq 3) { $pixel = 1 }
            }
            $mapped = $mapped -bor ($pixel -shl $shift)
        }
        $menu[$valueAt - $first] = [byte]$mapped
    }
}
[IO.File]::WriteAllBytes((Join-Path $project 'menu_low.bin'), $menu)
Write-Host 'Prepared four red/green title sprites and the menu soldier.'
