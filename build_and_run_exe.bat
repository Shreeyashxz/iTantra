@echo off
setlocal
echo ========================================================
echo    iTantra - Build and Run Windows Executable
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
if exist "ITantra-dart\pubspec.yaml" cd /d "ITantra-dart"
echo [*] Project Directory: %CD%
echo.

REM 3. Build Windows Application
echo [*] Building Windows Release Executable (flutter build windows)...
echo ========================================================
cmd.exe /c "flutter build windows"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Flutter Windows build failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo ========================================================
echo.

REM 4. Locate and Run Executable
set "EXE_DIR=%CD%\build\windows\x64\runner\Release"
set "EXE_PATH=%EXE_DIR%\itantra_dart.exe"

if not exist "%EXE_PATH%" (
    echo [ERROR] Executable not found at: "%EXE_PATH%"
    pause
    exit /b 1
)

echo [*] Launching itantra_dart.exe...
cd /d "%EXE_DIR%"
start "" "%EXE_PATH%"

echo.
echo ========================================================
echo [SUCCESS] iTantra application built and launched!
echo ========================================================
ping -n 3 127.0.0.1 >nul
