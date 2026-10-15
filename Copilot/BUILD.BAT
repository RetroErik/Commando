@echo off
setlocal
cd /d "%~dp0"
where nasm >nul 2>nul
if not errorlevel 1 (
    nasm -f bin -Wall -Werror -w-reloc-abs-word cmusic.asm -o CMUSIC.COM
    if errorlevel 1 exit /b 1
    exit /b 0
)
if exist "%LOCALAPPDATA%\bin\NASM\nasm.exe" (
    "%LOCALAPPDATA%\bin\NASM\nasm.exe" -f bin -Wall -Werror -w-reloc-abs-word cmusic.asm -o CMUSIC.COM
    if errorlevel 1 exit /b 1
    exit /b 0
)
echo ERROR: NASM is required. Add nasm.exe to PATH.
exit /b 1
