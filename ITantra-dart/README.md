# iTantra — Flutter & Dart Application (ITantra-dart)

> **Core Cross-Platform App for SIH 26173 (ISRO)**  
> Indian Multilingual TTS & STT Aided Neural Transceiver Radio Access for Low-Bitrate Links.

For complete project documentation, ISRO benchmark scorecards, and architectural diagrams, please see:
- 📖 [Comprehensive Architecture & Pipeline Specification](ITANTRA_ARCHITECTURE.md)
- 🛰️ [Root README](../README.md)

---

## Quick Reference

### Architecture Modules
- **`lib/network/`**:
  - `transceiver_manager.dart`: Manages peer-to-peer TCP communication on port `8888`. Includes 32-bit IP tie-breaking to avoid connection collisions and socket detachment race guards.
  - `wifi_mesh_manager.dart`: Handles UDP beacon discovery on port `8889` with network recovery.
- **`lib/speech/`**:
  - `comm_pipeline.dart`: The core transmission pipeline: Audio Input (16kHz PCM) → VAD → STT (AI4Bharat IndicConformer) → Semantic Compression (~160 bps) → Peer Transit → Machine Translation / Script Normalization → Neural TTS → Voice Output.
  - `sherpa_onnx_speech_engine.dart`: On-device speech runtime integrating AI4Bharat IndicConformer (INT8 NeMo CTC) for STT and neural VITS (AI4Bharat Rasa-13 / Meta MMS) for TTS.
  - `speech_engine.dart`: Core abstraction interface defining STT and TTS lifecycle contracts.
  - `language_pack_manager.dart`: Autonomous management and download of multi-language ONNX models.
  - `script_normalization_engine.dart`: Script normalization and phonetic transliteration across Indian scripts and Latin English.
- **`lib/translation/`**:
  - `machine_translation_engine.dart`: Offline ONNX machine translation powered by AI4Bharat IndicTrans2.
- **`lib/vad/`**:
  - `silero_vad_engine.dart`: In-memory pure-Dart RMS and energy-based Voice Activity Detection.
- **`lib/ui/screens/`**:
  - `transceiver_screen.dart`: Walkie-talkie half-duplex Hold-to-Talk interface with live translation and model switching.
  - `model_test_lab_screen.dart`: Diagnostic testing lab for benchmarking STT, TTS, MT, and VAD models with live audio analysis.
  - `settings_screen.dart`: Storage, precision tuning (INT8/FP32), language pack management, and technical specifications.
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

---

## Future Roadmap & Reference Catalogs (ITantra-dart-v2)

- [Open-Source Models & Techniques Catalog](../ITantra-dart-v2/OPEN_SOURCE_MODELS_CATALOG.md) — Comprehensive offline-first model alternatives, benchmarks, and future upgrade options (STT, TTS, MT, Transliteration, VAD, Neural Codecs, LID).
- [Bhashini API Models Analysis](../ITantra-dart-v2/BHASHINI_MODELS_ANALYSIS.md) — Detailed mapping of cloud-hosted Bhashini microservices for fallback, benchmarking, and future voice cloning integration.


