# Re-create the README video clips (docs\video): 10 s of the game's demo for CGA, Plantronics, VGA+CMS and VGA+AdLib.
# Needs DOSBox 0.74-3 (set DOSBOX_EXE if installed elsewhere), ffmpeg (set FFMPEG), the original game files in "Original game files"
# and the Plantronics build in ..\Codex\Plantronics\run.  Do not touch the keyboard while the DOSBox windows are open.
#   .\tools\make_readme_videos.ps1
param([string]$Ffmpeg = $(if ($env:FFMPEG) { $env:FFMPEG } else { 'C:\ffmpeg\ffmpeg.exe' }))
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$orig = Join-Path (Split-Path -Parent $here) 'Original game files'
$plan = Join-Path (Split-Path -Parent $here) 'Codex\Plantronics\run'
$rel = Join-Path $here 'releases\v1.2'
$tmp = Join-Path $here 'test\clips'
$out = Join-Path $here 'docs\video'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $tmp, $out | Out-Null
$shot = Join-Path $PSScriptRoot 'dosbox_shot.ps1'

# DOSBox video capture (AVI with sound): 'pause' holds the game until the capture key has been sent; no gameplay keys are sent,
# so the clip is the game's own demo.  M selects the sound device in the VGA build (speaker -> CMS -> AdLib).
$rec = @(@{ At = 2.5; Vid = $true }, @{ At = 15.5; Vid = $true })
& $shot -Dir $orig -Run "pause`nSTARTC.COM" -Out "$tmp\cga" -Machine cga -PcSpeaker true -NoSound false -Steps $rec -Total 17.5
& $shot -Dir $plan -Run "pause`nSTARTC.COM" -Out "$tmp\plan_audio" -Machine cga -PcSpeaker true -NoSound false -Steps $rec -Total 17.5
& $shot -Dir $rel -Run "pause`nSTART.COM" -Out "$tmp\vga_cms" -Sb gb -NoSound false -Steps (@(@{ At = 3.2; Keys = 'm' }) + $rec) -Total 17.5
& $shot -Dir $rel -Run "pause`nSTART.COM" -Out "$tmp\vga_adlib" -Sb sb16 -NoSound false -Steps (@(@{ At = 3.2; Keys = 'm' }, @{ At = 4; Keys = 'm' }) + $rec) -Total 17.5

# The Plantronics picture comes from the emulator (DOSBox cannot show ColorPlus colours); see make_plantronics_clip.py
python (Join-Path $PSScriptRoot 'make_plantronics_clip.py') "$tmp\plan" 10

$clips = @{ cga = 'commando_cga_pc_speaker'; vga_cms = 'commando_vga_cms'; vga_adlib = 'commando_vga_adlib' }
foreach ($k in $clips.Keys) {
    & $Ffmpeg -hide_banner -loglevel error -y -ss 0.5 -t 10 -i "$tmp\$k\raw\commando_000.avi" -vf 'fps=30,format=yuv420p' -c:v libx264 -preset slow -crf 22 -c:a aac -b:a 128k -movflags +faststart "$out\$($clips[$k]).mp4"
}
& $Ffmpeg -hide_banner -loglevel error -y -i "$tmp\plan\commando_plantronics.mp4" -ss 0.5 -t 10 -i "$tmp\plan_audio\raw\commando_000.avi" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 128k -shortest -movflags +faststart "$out\commando_plantronics.mp4"

# Silent GIF previews at the native 320x200 for the README
foreach ($mp4 in Get-ChildItem $out -Filter *.mp4) {
    $gif = [IO.Path]::ChangeExtension($mp4.FullName, '.gif')
    & $Ffmpeg -hide_banner -loglevel error -y -i $mp4.FullName -vf 'fps=15,scale=320:200:flags=neighbor,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle' -loop 0 $gif
}
Get-ChildItem $out | Select-Object Name, Length
