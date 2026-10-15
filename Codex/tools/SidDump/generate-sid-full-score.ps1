$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $PSScriptRoot 'Program.cs'
$sid = Join-Path $project '..\Original game files\Commando.sid'
$output = Join-Path $PSScriptRoot 'sidmusic-envelope-full.bin'
Add-Type -Path $source -ErrorAction Stop
$arguments = [string[]]@($sid, '1', '24050', $output, '--cms-envelope')
$result = [Program]::Main($arguments)
if ($result -ne 0) { throw "SID full score generation failed with code $result." }
Write-Host "Generated $output"
