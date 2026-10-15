@echo off
..\cmusic > launch.out
if errorlevel 8 goto failed
if not errorlevel 7 goto failed
..\cmusic /N > baseline.out
if errorlevel 8 goto failed
if not errorlevel 7 goto failed
..\cmusic /? > help.out
if errorlevel 1 goto failed
..\cmusic /INVALID > invalid.out
if not errorlevel 1 goto failed
echo PASS: child execution, fast game timer, cleanup, exit code, baseline, help, invalid option. > exec.out
goto end
:failed
echo FAIL: launcher integration. > exec.out
:end
