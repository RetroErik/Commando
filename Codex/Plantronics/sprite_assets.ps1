$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$sourcePath = Join-Path $project '..\..\Original game files\COMMANDO.EXE'
$expected = '4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne $expected) {
    throw 'Unsupported COMMANDO.EXE version.'
}
$exe = [IO.File]::ReadAllBytes($sourcePath)
$fileBase = 0x8550 # MZ header (200h) plus the relocated DS base (8350h).

function Map-Pair {
    param([int] $Pixel, [string] $Kind, [bool] $Belt, [bool] $Upper)
    if ($Upper) {
        if ($Kind -eq 'enemy') {
            if ($Pixel -eq 3) { return 3 }
            if ($Pixel -eq 1 -or $Pixel -eq 2) { return 2 }
        }
        if ($Kind -eq 'hero' -and $Pixel -eq 3 -and -not $Belt) { return 3 }
        return 0
    }
    if ($Kind -eq 'enemy') {
        if ($Belt -and $Pixel -eq 3) { return 3 }
        return 0
    }
    if ($Pixel -eq 1 -or $Pixel -eq 2) { return 2 }
    if ($Pixel -eq 3 -and -not $Belt) { return 3 }
    return 0
}

foreach ($class in @(
    @{ Kind = 'enemy'; Start = 0x1e12; End = 0x3b64; Count = 21 },
    @{ Kind = 'hero'; Start = 0x3dac; End = 0x599e; Count = 20 }
)) {
    $startFile = $fileBase + $class.Start
    $length = $class.End - $class.Start
    $low = New-Object byte[] $length
    $high = New-Object byte[] $length
    [Array]::Copy($exe, $startFile, $low, 0, $length)
    [Array]::Copy($exe, $startFile, $high, 0, $length)
    $sprite = $class.Start
    $count = 0
    while ($sprite -lt $class.End) {
        $file = $fileBase + $sprite
        $oddOffset = [BitConverter]::ToUInt16($exe, $file)
        $headers = @($file + 2)
        if ($oddOffset -ne 0) { $headers += $file + 2 + $oddOffset }
        $beltRow = 14
        if ($class.Kind -eq 'enemy' -and $sprite -ge 0x2756 -and $sprite -lt 0x3522) {
            $beltRow = 12
            if ($sprite -eq 0x2a46 -or $sprite -eq 0x3036) { $beltRow = 13 }
        }
        if ($class.Kind -eq 'hero' -and $sprite -ge 0x46f0 -and $sprite -lt 0x5548) {
            $beltRow = 12
            if ($sprite -eq 0x49e0 -or $sprite -eq 0x4fd0) { $beltRow = 13 }
        }
        $nextFile = 0
        foreach ($header in $headers) {
            $height = [int]$exe[$header]
            $width = [int]$exe[$header + 1]
            if ($height -lt 10 -or $height -gt 24 -or $width -lt 3 -or $width -gt 6) {
                throw ('Invalid {0} sprite header at {1:X5}.' -f $class.Kind, $header)
            }
            for ($row = 0; $row -lt $height; $row++) {
                for ($column = 0; $column -lt $width; $column++) {
                    $valueFile = $header + 2 + 2 * ($row * $width + $column) + 1
                    $value = [int]$exe[$valueFile]
                    $lowValue = 0
                    $highValue = 0
                    foreach ($shift in @(0, 2, 4, 6)) {
                        $pixel = ($value -shr $shift) -band 3
                        $lowValue = $lowValue -bor ((Map-Pair $pixel $class.Kind ($row -eq $beltRow) $false) -shl $shift)
                        $highValue = $highValue -bor ((Map-Pair $pixel $class.Kind ($row -eq $beltRow) $true) -shl $shift)
                    }
                    $index = $valueFile - $startFile
                    $low[$index] = [byte]$lowValue
                    $high[$index] = [byte]$highValue
                }
            }
            $nextFile = $header + 2 + 2 * $height * $width
        }
        if ($oddOffset -ne 0) {
            $evenEnd = $headers[0] + 2 + 2 * $exe[$headers[0]] * $exe[$headers[0] + 1]
            if ($evenEnd -ne $headers[1]) { throw ('Noncontiguous {0} variants at {1:X4}.' -f $class.Kind, $sprite) }
        }
        $nextSprite = $nextFile - $fileBase
        if ($nextSprite -le $sprite -or $nextSprite -gt $class.End) {
            throw ('Invalid {0} sprite end at {1:X4}.' -f $class.Kind, $sprite)
        }
        $sprite = $nextSprite
        $count++
    }
    if ($sprite -ne $class.End -or $count -ne $class.Count) {
        throw ('Unexpected {0} frame count or end: {1}, {2:X4}.' -f $class.Kind, $count, $sprite)
    }
    [IO.File]::WriteAllBytes((Join-Path $project ($class.Kind + '_low.bin')), $low)
    [IO.File]::WriteAllBytes((Join-Path $project ($class.Kind + '_high.bin')), $high)
    Write-Host ('Prepared {0} {1} frames and both x-parity variants.' -f $count, $class.Kind)
}

# Additional object records are contiguous within these two ranges. Their
# masks and dimensions remain the game's originals; only opaque value pairs
# receive new RGBI bits. Each range includes both x-parity variants.
function Get-AccentColor {
    param([int] $Sprite, [int] $Pixel, [int] $X, [int] $Y, [int] $Width, [int] $Height)
    if ($Pixel -eq 0) { return 0 }
    if ($Sprite -eq 0x739a -or $Sprite -eq 0x8478 -or $Sprite -eq 0x84ae) {
        if ($Pixel -eq 3) { return 11 } # Light gray: lower 3, upper 2.
        return 4                       # Dark gray: lower 0, upper 1.
    }
    if ($Sprite -eq 0x804a) { return 15 } # White projectile.
    if ($Sprite -ge 0x8058 -and $Sprite -le 0x83f4) {
        if ($Pixel -eq 2) { return 2 }   # Dark red.
        if ($Pixel -eq 1) { return 11 }  # Light gray.
        $centerX = [Math]::Floor($Width / 2)
        $centerY = [Math]::Floor($Height / 2)
        if ([Math]::Abs($X - $centerX) -le 1 -and [Math]::Abs($Y - $centerY) -le 1) {
            return 11                   # Light-gray center of a hit flash.
        }
        return 7                        # Yellow: lower 3, upper 1.
    }
    return $Pixel                       # Untouched frame.
}

foreach ($region in @(
    @{ Kind = 'rock'; Start = 0x739a; End = 0x73d8; Count = 1 },
    @{ Kind = 'effects'; Start = 0x804a; End = 0x84dc; Count = 11 }
)) {
    $startFile = $fileBase + $region.Start
    $length = $region.End - $region.Start
    $low = New-Object byte[] $length
    $high = New-Object byte[] $length
    [Array]::Copy($exe, $startFile, $low, 0, $length)
    [Array]::Copy($exe, $startFile, $high, 0, $length)
    $sprite = $region.Start
    $count = 0
    while ($sprite -lt $region.End) {
        $file = $fileBase + $sprite
        $oddOffset = [BitConverter]::ToUInt16($exe, $file)
        $headers = @($file + 2)
        if ($oddOffset -ne 0) { $headers += $file + 2 + $oddOffset }
        foreach ($header in $headers) {
            $height = [int]$exe[$header]
            $widthBytes = [int]$exe[$header + 1]
            if ($height -lt 1 -or $height -gt 24 -or $widthBytes -lt 1 -or $widthBytes -gt 6) {
                throw ('Invalid {0} sprite header at {1:X5}.' -f $region.Kind, $header)
            }
            for ($row = 0; $row -lt $height; $row++) {
                for ($column = 0; $column -lt $widthBytes; $column++) {
                    $valueFile = $header + 2 + 2 * ($row * $widthBytes + $column) + 1
                    $mask = [int]$exe[$valueFile - 1]
                    $value = [int]$exe[$valueFile]
                    $lowValue = 0
                    $highValue = 0
                    for ($pair = 0; $pair -lt 4; $pair++) {
                        $shift = 6 - 2 * $pair
                        if ((($mask -shr $shift) -band 3) -eq 3) { continue }
                        $pixel = ($value -shr $shift) -band 3
                        $color = Get-AccentColor $sprite $pixel ($column * 4 + $pair) $row ($widthBytes * 4) $height
                        $lowValue = $lowValue -bor (($color -band 3) -shl $shift)
                        $highValue = $highValue -bor ((($color -shr 2) -band 3) -shl $shift)
                    }
                    $index = $valueFile - $startFile
                    $low[$index] = [byte]$lowValue
                    $high[$index] = [byte]$highValue
                }
            }
        }
        $last = $headers[-1]
        $nextFile = $last + 2 + 2 * [int]$exe[$last] * [int]$exe[$last + 1]
        $nextSprite = $nextFile - $fileBase
        if ($nextSprite -le $sprite -or $nextSprite -gt $region.End) {
            throw ('Invalid {0} sprite end at {1:X4}.' -f $region.Kind, $sprite)
        }
        $sprite = $nextSprite
        $count++
    }
    if ($sprite -ne $region.End -or $count -ne $region.Count) {
        throw ('Unexpected {0} frame count or end: {1}, {2:X4}.' -f $region.Kind, $count, $sprite)
    }
    [IO.File]::WriteAllBytes((Join-Path $project ($region.Kind + '_low.bin')), $low)
    [IO.File]::WriteAllBytes((Join-Path $project ($region.Kind + '_high.bin')), $high)
    Write-Host ('Prepared {0} {1} object frames.' -f $count, $region.Kind)
}
