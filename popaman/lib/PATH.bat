@echo off
setlocal enabledelayedexpansion

REM Get the directory of the batch file
set "popaman_path=%~dp0"
if "%popaman_path:~-1%"=="\" set "popaman_path=%popaman_path:~0,-1%"
cd "%popaman_path%"
cd ..
set "popaman_path=%cd%"

REM Set popaman_HOME environment variable
setx popaman_HOME "%popaman_path%"

REM Set the paths
set "bin_path=%popaman_path%\bin"

REM Get current PATH from registry
for /f "tokens=2*" %%a in ('reg query "HKEY_CURRENT_USER\Environment" /v PATH') do set "current_path=%%b"

REM Check if our bin_path is already present
echo !current_path! | findstr /I /C:"%bin_path%" >nul
if errorlevel 1 (
    REM Append to existing PATH (preserving all existing entries)
    setx PATH "!current_path!;%bin_path%"
    echo Added %bin_path% to PATH.
) else (
    echo %bin_path% is already in PATH.
)

echo.
echo popaman environment setup complete.
echo Please restart your command prompt or terminal for the changes to take effect.

endlocal
pause
