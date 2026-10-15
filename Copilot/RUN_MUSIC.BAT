@echo off
setlocal
cd /d "%~dp0"
set "DOSBOX=%ProgramFiles(x86)%\DOSBox-0.74-3\DOSBox.exe"
if not exist "%DOSBOX%" (
    echo ERROR: DOSBox 0.74-3 was not found at "%DOSBOX%".
    echo Edit DOSBOX in this launcher to match your installation.
    exit /b 1
)
if not exist CMUSIC.COM (
    echo ERROR: CMUSIC.COM is missing. Run BUILD.BAT first.
    exit /b 1
)
"%DOSBOX%" -conf "%~dp0dosbox-music.conf" -c "mount c \"%~dp0..\Original game files\"" -c "mount d \"%~dp0.\"" -c "c:" -c "d:\cmusic"
