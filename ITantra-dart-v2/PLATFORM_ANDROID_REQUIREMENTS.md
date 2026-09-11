# Platform & Target Architecture Specification: Android First

> **CRITICAL ARCHITECTURAL DIRECTIVE**
> **Target OS:** Android (Mobile & Tactical Rugged Handhelds)  
> **Rule:** Absolutely **NO** Windows-dependent APIs, binaries, or platform tools may be used anywhere in the codebase.

---

## 1. Core Platform Constraints

1. **Target Environment:**
   - **OS:** Android (API Level 24+ / Android 7.0 through Android 15).
   - **CPU Architectures:** `arm64-v8a` (primary target), `armeabi-v7a`, `x86_64` (emulator).
   - **Form Factor:** Android smartphones, field tablets, and disaster-relief ruggedized devices.

2. **Strict Prohibition of Windows Dependencies:**
   - **NO PowerShell** (`Process.run('powershell', ...)`).
   - **NO Windows SAPI / COM** (`System.Speech`, `SAPI.SpVoice`, OneCore).
   - **NO Windows Registry lookups** (`HKLM:\...`).
   - **NO Hardcoded Windows paths** (e.g. `C:\`, backslashes `\`). Always use `path.join()` and `path_provider` (`getApplicationSupportDirectory()`, `getTemporaryDirectory()`).
   - Any desktop initialization (such as `sqflite_common_ffi` or DLL path resolution) must be strictly guarded behind `if (Platform.isWindows)` for development convenience only, and must never execute or be relied upon on Android.

---

## 2. Audio & Speech Architecture (Android Native)

### 2.1 Audio Capture (Microphone)
- **Engine:** `record` package (`AudioRecorderService`).
- **Android Mechanism:** Android `AudioRecord` API streaming 16kHz, 16-bit Mono linear PCM.
- **Android Permission:** `<uses-permission android:name="android.permission.RECORD_AUDIO" />`.

### 2.2 Voice Activity Detection (VAD)
- **Engine:** `SileroVadEngine`.
- **Mechanism:** Pure Dart floating-point RMS energy computation with dynamic sensitivity gating (10% to 100%).
- **Portability:** 100% platform-independent Dart math, running directly in-memory without external libraries.

### 2.3 Speech-to-Text (STT)
- **Engine:** `sherpa_onnx` (`SherpaOnnxSpeechEngine`).
- **Android Execution:** Native C++ core compiled as Android `.so` shared libraries (`libsherpa-onnx.so`, `libonnxruntime.so`) loaded automatically via Android JNI.
- **Models:** AI4Bharat IndicConformer INT8 NeMo CTC and Streaming Zipformer.
- **Dynamic Real-Time Live Detection:** Continuous 700ms buffer decoding running asynchronously, updating text on-screen as words are spoken.
- **Script Adaptation:** `IndicScriptTransliterator` providing real-time phonetic transliteration to English (Latin) or native Indian scripts (Devanagari, Marathi, etc.).

### 2.4 Text-to-Speech (TTS)
- **Engine:** `sherpa_onnx` VITS + High-Fidelity Local Voice Cache.
- **Android Audio Output:** `audioplayers` package (`DeviceFileSource`), delegating to native Android `ExoPlayer` / `MediaPlayer`.
- **Gender Selection (Male vs Female):**
  - **On-Device Neural VITS:** Speaker ID `sid: 1` (Male) vs `sid: 0` (Female); speed/tempo adjustment.
  - **Native Voice Cache:** Digital pitch and playback rate modulation (`0.78` for deep male baritone register, `1.05` for clear female soprano register).
  - **Zero External Host Tools:** Completely independent of any desktop speech synthesizers.

---

## 3. Networking Architecture (Android Wi-Fi Mesh)

- **Mesh Transport:** UDP Multicast (Port 8889) for peer heartbeat & node discovery; TCP (Port 8888) for direct packet transmission.
- **Android Socket Configuration:** `reusePort: true` for multicast discovery on Linux/Android kernel.
- **Required Android Permissions (`AndroidManifest.xml`):**
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
  <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  ```

---

## 4. Android Build Verification

To compile the Android APK:
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```
