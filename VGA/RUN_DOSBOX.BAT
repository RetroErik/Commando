@echo off
rem Run the experimental VGA Commando build in DOSBox 0.74-3 (VGA machine, unlimited cycles).
cd /d "%~dp0"
"C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe" -conf dosbox-vga.conf
