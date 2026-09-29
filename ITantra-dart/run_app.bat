@echo off
setlocal
echo ========================================================
echo Launching iTantra Windows App...
echo ========================================================

REM Kill any currently running instance
taskkill /F /IM itantra_dart.exe >nul 2>&1

set "EXE_DIR=%~dp0build\windows\x64\runner\Release"
set "EXE_PATH=%EXE_DIR%\itantra_dart.exe"

if not exist "%EXE_PATH%" (
    echo.
    echo [WARNING] Release executable not found at:
    echo "%EXE_PATH%"
    echo.
    echo The Windows release binary has not been built yet.
    set /p "DO_BUILD=Would you like to build it now? (Y/N, default Y): "
    if /i "%DO_BUILD%"=="n" (
        echo [INFO] Build cancelled by user.
        pause
        exit /b 1
    )
    echo.
    echo [*] Building Windows release application...
    echo ========================================================
    cd /d "%~dp0"
    call flutter build windows --release
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] Flutter Windows build failed with exit code %errorlevel%.
        pause
        exit /b %errorlevel%
    )
    echo ========================================================
)

if not exist "%EXE_PATH%" (
    echo [ERROR] Executable still not found at:
    echo "%EXE_PATH%"
    pause
    exit /b 1
)

echo Starting itantra_dart.exe...
cd /d "%EXE_DIR%"
start "" "%EXE_PATH%"

echo [SUCCESS] iTantra application launched!
ping -n 3 127.0.0.1 >nul

