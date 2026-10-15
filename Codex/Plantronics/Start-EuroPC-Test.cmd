@echo off
rem By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
rem Starts an isolated copy of the EuroPC configuration. Its hard disk
rem automatically switches to A: and runs the patched STARTC.COM.
start "" /D "D:\86Box-Windows-64-b9001" "D:\86Box-Windows-64-b9001\86Box.exe" --vmpath "%~dp0test\EuroPC-autoboot"
