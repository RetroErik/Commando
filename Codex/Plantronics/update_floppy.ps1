param(
    [Parameter(Mandatory)][string] $SourceImage,
    [Parameter(Mandatory)][string] $OutputImage
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceImage).Path
$output = [IO.Path]::GetFullPath($OutputImage)
if ($source -eq $output) { throw 'Use a separate output image so the supplied floppy stays intact.' }
$disk = [IO.File]::ReadAllBytes($source)
$original = [byte[]]$disk.Clone()
$allowed = [Collections.Generic.HashSet[int]]::new()
$stagedFiles = @{}
$bytesPerSector = [BitConverter]::ToUInt16($disk, 11)
$sectorsPerCluster = [int]$disk[13]
$reserved = [BitConverter]::ToUInt16($disk, 14)
$fatCount = [int]$disk[16]
$rootEntries = [BitConverter]::ToUInt16($disk, 17)
$sectorsPerFat = [BitConverter]::ToUInt16($disk, 22)
if ($disk.Length -ne 737280 -or $bytesPerSector -ne 512 -or
    $sectorsPerCluster -ne 2 -or $reserved -ne 1 -or $fatCount -ne 2 -or
    $rootEntries -ne 112 -or $sectorsPerFat -ne 3) {
    throw 'This updater expects the supplied 720 KB FAT12 floppy layout.'
}
$fatOffset = $reserved * $bytesPerSector
$fatBytes = $sectorsPerFat * $bytesPerSector
for ($index = 0; $index -lt $fatBytes; $index++) {
    if ($disk[$fatOffset + $index] -ne $disk[$fatOffset + $fatBytes + $index]) {
        throw 'The two FAT copies differ.'
    }
}
$rootOffset = ($reserved + $fatCount * $sectorsPerFat) * $bytesPerSector
$dataOffset = $rootOffset + $rootEntries * 32
$clusterBytes = $bytesPerSector * $sectorsPerCluster

function Get-Fat12Next([int] $cluster) {
    $position = $fatOffset + [int][Math]::Floor($cluster * 1.5)
    if (($cluster -band 1) -eq 0) {
        return [int]([int]$disk[$position] -bor (([int]$disk[$position + 1] -band 15) -shl 8))
    }
    return [int](([int]$disk[$position] -shr 4) -bor ([int]$disk[$position + 1] -shl 4))
}

function Set-Fat12Next([int] $cluster, [int] $value) {
    if ($value -lt 0 -or $value -gt 0xfff) { throw 'Invalid FAT12 entry value.' }
    for ($copy = 0; $copy -lt $fatCount; $copy++) {
        $position = $fatOffset + $copy * $fatBytes + [int][Math]::Floor($cluster * 1.5)
        if (($cluster -band 1) -eq 0) {
            $disk[$position] = [byte]($value -band 0xff)
            $disk[$position + 1] = [byte](($disk[$position + 1] -band 0xf0) -bor (($value -shr 8) -band 0x0f))
        } else {
            $disk[$position] = [byte](($disk[$position] -band 0x0f) -bor (($value -band 0x0f) -shl 4))
            $disk[$position + 1] = [byte](($value -shr 4) -band 0xff)
        }
        [void]$allowed.Add($position)
        [void]$allowed.Add($position + 1)
    }
}

function Find-FreeCluster {
    $limit = [int][Math]::Floor(($disk.Length - $dataOffset) / $clusterBytes) + 2
    for ($candidate = 2; $candidate -lt $limit; $candidate++) {
        if ((Get-Fat12Next $candidate) -eq 0) { return $candidate }
    }
    throw 'The floppy has no free clusters for the larger loader.'
}

foreach ($name in @('COMMANDO.DAT', 'COMMANDO.EXE', 'STARTC.COM', 'STARTC0.COM')) {
    $parts = $name.Split('.')
    $dosName = $parts[0].PadRight(8) + $parts[1].PadRight(3)
    $entry = -1
    for ($index = 0; $index -lt $rootEntries; $index++) {
        $candidate = $rootOffset + $index * 32
        if ($disk[$candidate] -eq 0) { break }
        if ($disk[$candidate] -eq 0xe5) { continue }
        if ([Text.Encoding]::ASCII.GetString($disk, $candidate, 11) -eq $dosName) {
            $entry = $candidate
            break
        }
    }
    if ($entry -lt 0) { throw "Missing floppy entry: $name" }
    $file = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot ("run\$name")))
    $cluster = [int][BitConverter]::ToUInt16($disk, $entry + 26)
    $visited = [Collections.Generic.HashSet[int]]::new()
    $positions = [Collections.Generic.List[int]]::new()
    $offset = 0
    while ($offset -lt $file.Length -and $cluster -ge 2 -and $cluster -lt 0xff8) {
        if (-not $visited.Add($cluster)) { throw "FAT loop in $name" }
        $at = $dataOffset + ($cluster - 2) * $clusterBytes
        if ($at + $clusterBytes -gt $disk.Length) { throw "Invalid cluster in $name" }
        $count = [Math]::Min($clusterBytes, $file.Length - $offset)
        if ($count -gt 0) {
            [Array]::Copy($file, $offset, $disk, $at, $count)
            $positions.Add($at)
            for ($byte = 0; $byte -lt $count; $byte++) { [void]$allowed.Add($at + $byte) }
        }
        $offset += $count
        $next = Get-Fat12Next $cluster
        if ($offset -lt $file.Length -and $next -ge 0xff8) {
            $next = Find-FreeCluster
            Set-Fat12Next $cluster $next
            Set-Fat12Next $next 0xfff
        }
        $cluster = $next
    }
    if ($offset -ne $file.Length) {
        throw "The existing cluster chain cannot hold $name (copied $offset of $($file.Length), visited $($visited.Count))."
    }
    [Array]::Copy([BitConverter]::GetBytes([uint32]$file.Length), 0, $disk, $entry + 28, 4)
    for ($byte = 28; $byte -lt 32; $byte++) { [void]$allowed.Add($entry + $byte) }
    $stagedFiles[$name] = @{ Data = $file; Clusters = $positions }
    Write-Host ("Staged {0}: {1} bytes in {2} clusters." -f $name, $file.Length, $visited.Count)
}

[IO.File]::WriteAllBytes($output, $disk)
$verify = [IO.File]::ReadAllBytes($output)
for ($index = 0; $index -lt $fatBytes; $index++) {
    if ($verify[$fatOffset + $index] -ne $verify[$fatOffset + $fatBytes + $index]) {
        throw 'The staged FAT copies differ.'
    }
}
for ($index = 0; $index -lt $verify.Length; $index++) {
    if ($verify[$index] -ne $original[$index] -and -not $allowed.Contains($index)) {
        throw ("Unexpected floppy change at image byte {0:X}." -f $index)
    }
}
foreach ($name in $stagedFiles.Keys) {
    $file = $stagedFiles[$name].Data
    $offset = 0
    foreach ($at in $stagedFiles[$name].Clusters) {
        $count = [Math]::Min($clusterBytes, $file.Length - $offset)
        for ($byte = 0; $byte -lt $count; $byte++) {
            if ($verify[$at + $byte] -ne $file[$offset + $byte]) {
                throw "Floppy read-back mismatch in $name."
            }
        }
        $offset += $count
    }
    if ($offset -ne $file.Length) { throw "Incomplete floppy read-back in $name." }
}
Write-Host "Wrote $output"
