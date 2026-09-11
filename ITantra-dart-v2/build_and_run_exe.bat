@echo off
setlocal EnableDelayedExpansion
echo ========================================================
echo       iTantra - Windows Interactive Build ^& Runner
echo ========================================================
echo.

REM 1. Terminate any running instance of the app to avoid file lock
echo [*] Checking for running instances of itantra_dart.exe...
taskkill /F /IM itantra_dart.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo [*] Terminated active instance of itantra_dart.exe.
)

REM 2. Switch to project directory
cd /d "%~dp0"
echo [*] Project Directory: %CD%
echo.

echo Select Execution Mode:
echo   [1] Interactive Dev Mode (Hot Reload 'r', Hot Restart 'R') [DEFAULT]
echo   [2] Build Release & Launch Standalone EXE
echo.

set "MODE=1"
set /p "MODE=Enter choice (1/2, default 1): "

if "%MODE%"=="2" goto RELEASE_MODE
goto DEV_MODE

:DEV_MODE
echo.
echo ========================================================
echo [*] Starting Flutter Interactive Windows Session...
echo [*] Interactive Keybindings once running:
echo       [r]  Hot Reload (instant UI updates)
echo       [R]  Hot Restart (full app restart)
echo       [v]  Open Flutter DevTools in browser
echo       [w]  Dump widget hierarchy
echo       [q]  Quit and close app
echo ========================================================
echo.
flutter run -d windows
goto END

:RELEASE_MODE
echo.
echo [*] Building Windows Release Executable (flutter build windows --release)...
echo ========================================================
cmd.exe /c "flutter build windows --release"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Flutter Windows build failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo ========================================================
echo.

set "EXE_DIR=%CD%\build\windows\x64\runner\Release"
set "EXE_PATH=%EXE_DIR%\itantra_dart.exe"

if not exist "%EXE_PATH%" (
    echo [ERROR] Executable not found at: "%EXE_PATH%"
    pause
    exit /b 1
)

echo [*] Launching standalone itantra_dart.exe...
cd /d "%EXE_DIR%"
start "" "%EXE_PATH%"

echo.
echo ========================================================
echo [SUCCESS] iTantra application built and launched!
echo ========================================================
ping -n 3 127.0.0.1 >nul
goto END

:END
