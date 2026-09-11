# Project Directives for AI Agents

## Target Platform: Android
- **CRITICAL:** This project is built for **Android mobile and field devices**.
- **PROHIBITED:** NEVER use Windows-specific dependencies, APIs, or shell scripts (e.g. `powershell`, SAPI, Windows COM, hardcoded Windows paths).
- All features must run natively on Android using Flutter cross-platform packages (`sqflite`, `record`, `audioplayers`, `sherpa_onnx`).
- For detailed platform architecture, see [PLATFORM_ANDROID_REQUIREMENTS.md](file:///d:/My%20FIles/Softwares/iTantra/ITantra-dart/PLATFORM_ANDROID_REQUIREMENTS.md).

## Development Testing Workflow: Automatic Restart
- **MANDATORY:** After compiling or applying changes, ALWAYS stop any running Windows app instance and launch the updated app executable immediately (`taskkill /F /IM itantra_dart.exe 2>$null; Start-Sleep -Seconds 1; Start-Process 'build\windows\x64\runner\Release\itantra_dart.exe'`) so the user immediately sees the fresh changes.
