# iTantra — Flutter & Dart Application (ITantra-dart)

> **Core Cross-Platform App for SIH 26173 (ISRO)**  
> Indian Multilingual TTS & STT Aided Neural Transceiver Radio Access for Low-Bitrate Links.

For complete project documentation, ISRO benchmark scorecards, and architectural diagrams, please see the [Root README](../README.md).

---

## Quick Reference

### Architecture Modules
- **`lib/network/`**:
  - `transceiver_manager.dart`: Manages peer-to-peer TCP communication on port `8888`. Includes 32-bit IP tie-breaking to avoid connection collisions and socket detachment race guards.
  - `wifi_mesh_manager.dart`: Handles UDP beacon discovery on port `8889` with Windows OS Error 1231 recovery.
- **`lib/speech/`**:
  - `comm_pipeline.dart`: The core transmission pipeline: Audio Input → STT → Semantic Packet → Peer Transit → MT / Transliteration → TTS → Voice Output.
  - `script_normalization_engine.dart`: Normalizes scripts and handles Indic-to-Indic transliteration for Rasa-13.
  - `stt_engine.dart` & `tts_engine.dart`: Speech recognition and synthesis abstractions supporting AI4Bharat Rasa-13 and Meta MMS.
- **`lib/ui/screens/transceiver_screen.dart`**:
  - Walkie-talkie half-duplex Hold-to-Talk interface.
  - Live TTS Switch (Rasa-13 ↔ MMS) in AppBar.
  - Live Language Selector & Machine Translation (MT) toggle.
- **`lib/alerts/`**:
  - High-priority non-interruptible emergency alert receiver and dispatcher.

---

## Quick Start

```bash
# Get packages
flutter pub get

# Run test suite
flutter test

# Run on Windows
flutter run -d windows

# Run on Android
flutter run -d android
```
