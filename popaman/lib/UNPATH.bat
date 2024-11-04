@echo off
setlocal enabledelayedexpansion

REM Get the directory of the batch file
set "popaman_path=%~dp0"
if "%popaman_path:~-1%"=="\" set "popaman_path=%popaman_path:~0,-1%"
cd "%popaman_path%"
cd ..
set "popaman_path=%cd%"

REM Set the paths
set "bin_path=%popaman_path%\bin"

REM Get current PATH from registry
for /f "tokens=2*" %%a in ('reg query "HKEY_CURRENT_USER\Environment" /v PATH') do set "current_path=%%b"

REM Remove popaman_HOME environment variable
reg delete "HKEY_CURRENT_USER\Environment" /v popaman_HOME /f >nul 2>&1

REM Remove bin_path from PATH if present
set "new_path=!current_path!"
set "new_path=!new_path:;%bin_path%=!"
set "new_path=!new_path:%bin_path%;=!"
set "new_path=!new_path:%bin_path%=!"

REM Update PATH only if it was changed
if not "!new_path!"=="!current_path!" (
    setx PATH "!new_path!"
    echo Removed %bin_path% from PATH.
) else (
    echo %bin_path% was not found in PATH.
)

echo.
echo popaman environment cleanup complete.
echo Please restart your command prompt or terminal for the changes to take effect.

endlocal
pause
