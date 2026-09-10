@echo off
setlocal
echo ========================================================
echo    iTantra - Build Android APK
echo ========================================================
echo.

REM 1. Switch to project directory
cd /d "%~dp0"
if exist "ITantra-dart\pubspec.yaml" cd /d "ITantra-dart"
echo [*] Project Directory: %CD%
echo.

REM 2. Determine build arguments
set "BUILD_ARGS=--release"
if not "%~1"=="" (
    set "BUILD_ARGS=%*"
)

echo [*] Building Android APK (flutter build apk %BUILD_ARGS%)...
echo ========================================================
cmd.exe /c "flutter build apk %BUILD_ARGS%"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Flutter build apk failed with exit code %errorlevel%.
    pause
    exit /b %errorlevel%
)
echo ========================================================
echo.

REM 3. Locate output APK
set "APK_DIR=%CD%\build\app\outputs\flutter-apk"
set "RELEASE_APK=%APK_DIR%\app-release.apk"

echo ========================================================
echo [SUCCESS] APK built successfully!
echo ========================================================
if exist "%RELEASE_APK%" (
    echo [*] Output APK: "%RELEASE_APK%"
    for %%F in ("%RELEASE_APK%") do (
        echo [*] File Size : %%~zF bytes
    )
) else (
    echo [*] Output Directory: "%APK_DIR%"
)
echo ========================================================
echo.

REM 4. Open containing folder in Windows Explorer
if exist "%APK_DIR%" (
    echo [*] Opening APK folder in File Explorer...
    start "" explorer.exe "%APK_DIR%"
)

pause
