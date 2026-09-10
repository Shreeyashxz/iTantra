@echo off
setlocal
echo ========================================================
echo Launching iTantra Windows App...
echo ========================================================

REM Kill any currently running instance
taskkill /F /IM itantra_dart.exe >nul 2>&1

set "EXE_DIR=%~dp0ITantra-dart\build\windows\x64\runner\Release"
set "EXE_PATH=%EXE_DIR%\itantra_dart.exe"

if not exist "%EXE_PATH%" (
    echo [ERROR] Executable not found at:
    echo "%EXE_PATH%"
    echo Please build the Windows app first.
    pause
    exit /b 1
)

echo Starting itantra_dart.exe...
cd /d "%EXE_DIR%"
start "" "%EXE_PATH%"

ping -n 3 127.0.0.1 >nul

