param(
    [string]$Nasm = "$env:LOCALAPPDATA\bin\NASM\nasm.exe",
    [string]$DosBox = "${env:ProgramFiles(x86)}\DOSBox-0.74-3\DOSBox.exe"
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (-not (Test-Path -LiteralPath $Nasm)) { throw "NASM not found: $Nasm" }
    if (-not (Test-Path -LiteralPath $DosBox)) { throw "DOSBox not found: $DosBox" }
    $flags = @('-f', 'bin', '-Wall', '-Werror', '-w-reloc-abs-word')
    & $Nasm @flags cmusic.asm -o CMUSIC.COM
    if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
    & $Nasm @flags -DMUSIC_TEST cmusic.asm -o test\PLAYER.COM
    if ($LASTEXITCODE -ne 0) { throw 'Player test build failed.' }
    & $Nasm @flags test\game-stub.asm -o test\STARTC.COM
    if ($LASTEXITCODE -ne 0) { throw 'Game timer stub build failed.' }
    # The file checks need placeholders; no commercial game files are copied.
    Copy-Item -LiteralPath test\STARTC.COM -Destination test\COMMANDO.EXE
    Copy-Item -LiteralPath test\STARTC.COM -Destination test\COMMANDO.DAT

    function Invoke-DosTest([string[]]$Commands, [switch]$NoOpl) {
        $arguments = '-conf "' + "$PSScriptRoot\dosbox-music.conf" + '"'
        if ($NoOpl) {
            $arguments += ' -conf "' + "$PSScriptRoot\test\no-opl.conf" + '"'
        }
        $arguments += ' -c "mount c \"' + $PSScriptRoot + '\"" -c "c:"'
        foreach ($command in $Commands) { $arguments += ' -c "' + $command + '"' }
        $arguments += ' -c "exit"'
        $process = Start-Process -FilePath $DosBox -ArgumentList $arguments -PassThru
        if (-not $process.WaitForExit(60000)) {
            Stop-Process -Id $process.Id
            throw 'DOSBox test timed out.'
        }
        if ($process.ExitCode -ne 0) { throw "DOSBox exited with code $($process.ExitCode)." }
    }

    $logs = @('player.out', 'exec.out', 'launch.out', 'baseline.out',
              'help.out', 'invalid.out', 'missing.out', 'noopl.out')
    foreach ($log in $logs) {
        $path = Join-Path 'test' $log
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Invoke-DosTest @('test\player > test\player.out', 'cd test', 'call checks')
    Invoke-DosTest @('cmusic > test\missing.out', 'cd test', '..\cmusic > noopl.out') -NoOpl

    $checks = @{
        'player.out' = '^PASS:'
        'exec.out' = '^PASS:'
        'launch.out' = 'Game returned; launcher cleanup completed\.'
        'baseline.out' = 'Game returned; launcher cleanup completed\.'
        'help.out' = 'CMUSIC /P'
        'invalid.out' = 'CMUSIC /\?'
        'missing.out' = 'ERROR: Cannot read STARTC\.COM'
        'noopl.out' = 'ERROR: AdLib/OPL hardware not detected'
    }
    foreach ($log in $checks.Keys) {
        $text = Get-Content -LiteralPath (Join-Path 'test' $log) -Raw
        if ($text -notmatch $checks[$log]) { throw "Unexpected test output in $log`: $text" }
    }
    Get-Content -LiteralPath test\player.out, test\exec.out
    Write-Output 'PASS: missing-file and missing-AdLib errors.'
} finally {
    Pop-Location
}
