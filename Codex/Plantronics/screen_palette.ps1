$ErrorActionPreference = 'Stop'
$tables = @(
    [Collections.Generic.List[byte]]::new(),
    [Collections.Generic.List[byte]]::new(),
    [Collections.Generic.List[byte]]::new(),
    [Collections.Generic.List[byte]]::new(),
    [Collections.Generic.List[byte]]::new(),
    [Collections.Generic.List[byte]]::new()
)
for ($byte = 0; $byte -le 255; $byte++) {
    $sideLow = 0; $sideHigh = 0; $sideKeep = 0
    $cyanLow = 0; $cyanHigh = 0; $cyanKeep = 0
    for ($pair = 0; $pair -lt 4; $pair++) {
        $shift = 2 * $pair
        $pixel = ($byte -shr $shift) -band 3
        if ($pixel -eq 1) {
            $sideLow = $sideLow -bor (2 -shl $shift) # Dark red.
            $cyanLow = $cyanLow -bor (1 -shl $shift)
            $cyanKeep = $cyanKeep -bor (3 -shl $shift)
        } elseif ($pixel -eq 2) {
            $sideLow = $sideLow -bor (3 -shl $shift) # Brown.
            $cyanLow = $cyanLow -bor (2 -shl $shift)
        } elseif ($pixel -eq 3) {
            $sideLow = $sideLow -bor (3 -shl $shift) # Brown.
            $cyanLow = $cyanLow -bor (1 -shl $shift)
            $cyanHigh = $cyanHigh -bor (2 -shl $shift)
        }
    }
    $tables[0].Add([byte]$sideLow)
    $tables[1].Add([byte]$sideHigh)
    $tables[2].Add([byte]$sideKeep)
    $tables[3].Add([byte]$cyanLow)
    $tables[4].Add([byte]$cyanHigh)
    $tables[5].Add([byte]$cyanKeep)
}
$out = New-Object byte[] 1536
for ($table = 0; $table -lt 6; $table++) {
    $tables[$table].CopyTo($out, $table * 256)
}
[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'screen_tables.bin'), $out)
