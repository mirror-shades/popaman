@echo off
setlocal enabledelayedexpansion

REM Get the directory of the batch file
set "portman=%~dp0"
if "%portman:~-1%"=="\" set "portman=%portman:~0,-1%"

REM Set PORTMAN_HOME environment variable
setx PORTMAN_HOME "%portman%"

REM Set the paths
set "bin_path=%portman%\bin"

REM Add PORTMAN_HOME\bin to PATH if not already present
echo %PATH% | findstr /I /C:"%bin_path%" >nul
if errorlevel 1 (
    setx PATH "%PATH%;%bin_path%"
    echo Added %bin_path% to PATH.
) else (
    echo %bin_path% is already in PATH.
)
endlocal