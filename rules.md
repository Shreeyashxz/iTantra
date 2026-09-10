# iTantra Architectural & Engineering Rules (rules.md)
**Project Title**: iTantra (Smart India Hackathon SIH 26173)  
**System Type**: Mission-Critical Disaster Mesh Voice Transceiver (10 Indian Languages)  
**Target Environments**: Android (Arm64-v8a / armeabi-v7a) & Desktop Testing (Windows x64 Portrait)  

---

## 1. Zero Cloud Dependency (Air-Gapped Operation)
1. **No External Network Calls During Mission Execution**:
   - The entire pipeline—Speech-to-Text (STT), Machine Translation (MT), Voice Activity Detection (VAD), and Text-to-Speech (TTS)—MUST run locally on the edge device.
   - Network calls are strictly restricted to the initial optional one-time language pack download screen (`SettingsScreen` / `LanguagePackManager`).
2. **Deterministic Offline Fallbacks**:
   - Every neural model must have an instant disaster-resilient fallback:
     - STT: AI4Bharat IndicConformer INT8 $\rightarrow$ Zipformer $\rightarrow$ Transliteration.
     - MT: IndicTrans2 INT8 ONNX $\rightarrow$ 10-Language Tactical Disaster Concept Lexicon.
     - TTS: AI4Bharat Rasa-13 $\rightarrow$ Meta MMS single-speaker $\rightarrow$ Tone alert.

---

## 2. Portrait Orientation & UI Constraints
1. **Fixed Portrait Orientation**:
   - All mobile layouts must lock to `DeviceOrientation.portraitUp` and `DeviceOrientation.portraitDown`.
   - The native Windows desktop runner must initialize in a phone-emulating portrait aspect ratio (`450 x 850 px`) using `Win32Window::Size(450, 850)`.
2. **Mission-Critical First-Glance Feedback**:
   - Vital tactical indicators must always be visible without scrolling:
     - Mesh Link Status & Latency (`RTT ms`, `~160 bps`).
     - Live VAD Status Badge (`VAD: VOICE DETECTED` vs `VAD: LISTENING (HANDS-FREE)`).
     - MT Status & Quick Switch Pill (`MT ACTIVE` vs `MT BYPASSED`).
     - JIT Pipeline Trigger Button (`RUN JIT`).
     - Center PTT/VAD Button with Radar Pulse Rings.

---

## 3. Just-In-Time (JIT) Pipeline Rules
1. **End-to-End Orchestration**:
   - The JIT pipeline chains:  
     $$\text{Audio Input} \xrightarrow{\text{Silero VAD}} \text{IndicConformer STT} \xrightarrow{\text{IndicTrans2 MT}} \text{Wi-Fi Mesh / BLE Fallback} \xrightarrow{\text{Rasa / MMS TTS}} \text{Speaker Out}$$
2. **Pre-Warming & Concurrency**:
   - Machine Translation and TTS engine warm-up MUST execute concurrently via `Future.wait([translationFuture, ttsWarmUp])`.
   - The active language's TTS engine must be asynchronously pre-warmed upon app startup to eliminate synthesis cold-start delay.
3. **Dedicated JIT Test Button**:
   - The UI provides dual JIT triggers:
     - Top AppBar `RUN JIT` IconButton.
     - Action Bar `RUN JIT` Pill with instant haptic/visual SnackBar feedback showing the active translation pair and delivery status.

---

## 4. Speech Engine & Model Rules
1. **Voice Activity Detection (VAD)**:
   - Primary: Silero VAD ONNX (32ms frames @ 16kHz, threshold `0.5`).
   - Secondary: Dynamic adaptive RMS noise-floor tracking (`max(0.015, baseline * 2.8)`).
   - Lookback Ring Buffer: Always retain the preceding 5 frames (~160ms) so onset syllables are not clipped.
   - Hangover: Auto-transmits after 1.2 seconds of silence in hands-free mode.
2. **Meta MMS Speech Synthesis (Single-Speaker)**:
   - Meta MMS checkpoints (`hin`, `eng`, etc.) are strictly **single-speaker**.
   - The speaker ID (`sid`) parameter MUST be locked to `0`. Passing `sid > 0` causes out-of-bounds ONNX errors or silent output.
   - Gender differentiation for MMS is achieved through physical formant and pitch scaling in `_playGeneratedAudio`.
3. **AI4Bharat Rasa-13 Speech Synthesis (Multi-Speaker)**:
   - Covers 13 Indian languages in one unified ~123MB model.
   - Uses multi-speaker routing (`sid: 0` for Female, `sid: 1` for Male).
   - Cadence is tuned for tactical deliberation (`0.92` baritone male / `1.02` soprano female).
   - Model resolution must automatically inspect the workspace folder (`converted_models/vits_rasa13_6in.onnx`) if app data storage has not been populated.
4. **Memory Retention Cap**:
   - To prevent memory leaks on Android devices with 2GB–4GB RAM, active in-memory `OfflineTts` instances must be capped at 2, evicting the oldest via `.free()`.

---

## 5. Mesh & Dual-Transport Rules
1. **Primary Transport (Wi-Fi Direct / Mesh)**:
   - High throughput UDP/TCP sockets (port `8888`) across the local subnet.
   - Used for zero-latency point-to-point and multi-hop tactical packet dissemination.
2. **Secondary Transport (BLE GATT Fallback)**:
   - Seamless failover when Wi-Fi Direct is disabled, jammed, or out of range.
   - Automated MTU packet fragmentation: packets larger than 180 bytes are sliced into numbered chunks and reassembled via a sliding buffer.
3. **Bandwidth Economy**:
   - Text packets consume only ~160 bps (under 250 bytes per utterance), outperforming legacy analog audio and uncompressed voice streams by orders of magnitude.

---

## 6. Build & Deployment Rules
1. **Cross-Platform Parity**:
   - No Windows-exclusive APIs inside `lib/`. All platform-specific system calls must check `Platform.isWindows` or `Platform.isAndroid`.
   - Database operations on desktop use `sqflite_common_ffi`, while mobile uses standard `sqflite`.
2. **Native Library Safety**:
   - On Windows: `onnxruntime.dll` and `sherpa-onnx.dll` are loaded from the executable directory.
   - On Android: ProGuard rules preserve Sherpa-ONNX JNI bindings (`com.k2fsa.sherpa.onnx.**`), Protobuf Lite, and native `.so` shared libraries.

*(Note: Keep this document updated as new requirements and optimizations are implemented.)*
