import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'language_pack_manager.dart';
import 'os_native_tts_service.dart';
import 'script_normalization_engine.dart';
import 'speech_engine.dart';



/// Real on-device and hybrid speech engine.
/// Provides:
///   STT — Offline neural speech recognition supporting AI4Bharat IndicConformer (NeMo CTC)
///         with English Latin transliteration & native script output.
///   TTS — Studio-grade multi-language neural synthesis with distinct Male / Female voices.
class SherpaOnnxSpeechEngine implements SpeechEngine {
  final LanguagePackManager languagePackManager;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // --- STT ---
  sherpa.OfflineRecognizer? _offlineRecognizer;
  bool _isIndicConformer = false;
  String? _loadedSttVariant;
  // Cap ~60s at 16kHz to prevent OOM on long PTT holds (960k int16).
  static const int _maxAudioSamples = 16 * 1000 * 60;
  final List<int> _audioBuffer = [];

  StreamController<String>? _sttTextController;
  bool _isListening = false;
  String _currentLanguage = 'hi';

  // --- TTS ---
  final Map<String, sherpa.OfflineTts> _ttsEngines = {};
  final List<String> _ttsEngineKeys = [];
  // Serialize concurrent speak requests so bursts queue instead of cutting.
  Future<void> _ttsLock = Future.value();

  SherpaOnnxSpeechEngine({required this.languagePackManager});

  /// Resolves the models base directory.
  Future<String> _modelsDir() async {
    final dir = await languagePackManager.getModelsDirectory();
    return dir.path;
  }

  // ==========================================
  // STT (Speech-to-Text) — AI4Bharat IndicConformer
  // ==========================================

  /// Initialize the STT recognizer from downloaded model files.
  Future<bool> initStt([String precision = 'INT8']) async {
    if (_offlineRecognizer != null) return true;

    // Prevent Windows 11 system32 DLL hijacking by pre-loading bundled onnxruntime.dll
    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final ortPath = p.join(exeDir, 'onnxruntime.dll');
        if (File(ortPath).existsSync()) {
          DynamicLibrary.open(ortPath);
        } else {
          // Fallback for `flutter run`
          final runPath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'onnxruntime.dll');
          final runPathRel = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'onnxruntime.dll');
          if (File(runPath).existsSync()) {
            DynamicLibrary.open(runPath);
          } else if (File(runPathRel).existsSync()) {
            DynamicLibrary.open(runPathRel);
          }
        }
      } catch (_) {}
    }

    try {
      final dir = await _modelsDir();
      final sttDir = p.join(dir, 'stt');

      final indicInt8 = p.join(sttDir, 'indic_conformer.onnx');
      final indicFp32 = p.join(sttDir, 'indic_conformer_fp32.onnx');
      final tokens = p.join(sttDir, 'tokens.txt');

      String? chosenIndicModel;
      if (precision.toUpperCase() == 'FP32') {
        if (File(indicFp32).existsSync()) {
          chosenIndicModel = indicFp32;
        } else if (File(indicInt8).existsSync()) {
          chosenIndicModel = indicInt8;
          debugPrint('[STT] FP32 model missing; falling back to INT8');
        }
      } else {
        if (File(indicInt8).existsSync()) {
          chosenIndicModel = indicInt8;
        } else if (File(indicFp32).existsSync()) {
          chosenIndicModel = indicFp32;
          debugPrint('[STT] INT8 model missing; falling back to FP32');
        }
      }

      if (chosenIndicModel != null && File(tokens).existsSync()) {
        final isFp32 = chosenIndicModel == indicFp32;
        debugPrint('[STT] Initializing AI4Bharat IndicConformer ${isFp32 ? "FP32" : "INT8"} model (NeMo CTC)...');
        final offlineConfig = sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: chosenIndicModel),
            tokens: tokens,
            numThreads: 2,
            debug: false,
          ),
        );
        _offlineRecognizer = sherpa.OfflineRecognizer(offlineConfig);
        _isIndicConformer = true;
        _loadedSttVariant = isFp32 ? 'IndicConformer FP32' : 'IndicConformer INT8';
        debugPrint('[STT] AI4Bharat IndicConformer (${isFp32 ? "FP32" : "INT8"}) OfflineRecognizer initialized successfully');
        return true;
      } else {
        debugPrint('[STT] Missing required STT model files in $sttDir');
        return false;
      }
    } catch (e) {
      debugPrint('[STT] Failed to initialize recognizer: $e');
      _offlineRecognizer = null;
      return false;
    }
  }

  @override
  Stream<String> startListening([String languageCode = 'hi']) {
    _currentLanguage = languageCode;
    final old = _sttTextController;
    if (old != null && !old.isClosed) {
      // Don't await in sync method; close in microtask to avoid "add after close".
      Future.microtask(() async {
        try {
          await old.close();
        } catch (_) {}
      });
    }
    _sttTextController = StreamController<String>.broadcast();
    _isListening = true;
    _audioBuffer.clear();

    return _sttTextController!.stream;
  }

  /// Feed raw PCM audio (16kHz, 16-bit mono) into the STT recognizer.
  void feedAudioData(Int16List samples) {
    if (!_isListening) return;

    // Buffer audio for final decoding (bounded — drop oldest on overflow).
    if (_audioBuffer.length + samples.length > _maxAudioSamples) {
      final overflow = _audioBuffer.length + samples.length - _maxAudioSamples;
      _audioBuffer.removeRange(0, overflow.clamp(0, _audioBuffer.length));
      debugPrint('[STT] Audio buffer capped at 60s — dropped oldest $overflow samples');
    }
    _audioBuffer.addAll(samples);
  }

  /// Ingests pre-formed transcribed text into the active listening stream.
  void pushTranscribedText(String text) {
    if (_isListening && _sttTextController != null && !_sttTextController!.isClosed) {
      _sttTextController!.add(text);
    }
  }

  @override
  Future<String> stopListeningAndTranscribe([String? languageCode]) async {
    final lang = languageCode ?? _currentLanguage;
    String finalTranscript = '';

    // Process buffered audio with AI4Bharat IndicConformer
    if (_isIndicConformer && _offlineRecognizer != null && _audioBuffer.isNotEmpty) {
      try {
        debugPrint('[STT] Final decoding ${_audioBuffer.length} samples with AI4Bharat IndicConformer for [$lang]...');
        final floatSamples = Float32List(_audioBuffer.length);
        for (int i = 0; i < _audioBuffer.length; i++) {
          floatSamples[i] = _audioBuffer[i] / 32768.0;
        }

        final stream = _offlineRecognizer!.createStream();
        stream.acceptWaveform(samples: floatSamples, sampleRate: 16000);
        _offlineRecognizer!.decode(stream);
        final rawResult = _offlineRecognizer!.getResult(stream).text.trim();
        stream.free();

        debugPrint('[STT] Raw IndicConformer output: "$rawResult"');

        if (rawResult.isNotEmpty) {
          finalTranscript = ScriptNormalizationEngine.normalizeFromStt(rawResult, lang);
          _sttTextController?.add(finalTranscript);
        }
      } catch (e) {
        debugPrint('[STT] Error final decoding with IndicConformer: $e');
      }
    }

    _isListening = false;
    _audioBuffer.clear();
    final ctrl = _sttTextController;
    _sttTextController = null;
    if (ctrl != null && !ctrl.isClosed) {
      try {
        await ctrl.close();
      } catch (_) {}
    }

    return finalTranscript;
  }

  @override
  Future<void> stopListening() async {
    await stopListeningAndTranscribe();
  }

  // ==========================================
  // TTS (Text-to-Speech) — Studio Native Voice Engine
  // ==========================================

  /// Initialize TTS for a given language from downloaded VITS ONNX model or OS Native.
  Future<bool> initTts(String languageCode, [String ttsEngineType = 'META_MMS']) async {
    // OS Native TTS does not require loading an ONNX model into memory
    if (ttsEngineType == 'OS_NATIVE') {
      await OsNativeTtsService.instance.init();
      return true;
    }

    // Guard: AI4Bharat Rasa-13 does not support Gujarati ('gu'), Odia ('or'), or English ('en')
    var effectiveEngineType = _getEffectiveTtsEngine(ttsEngineType, languageCode);
    if (languageCode == 'en' &&
        effectiveEngineType != 'AI4BHARAT_RASA' &&
        effectiveEngineType != 'OS_NATIVE') {
      effectiveEngineType = 'META_MMS';
    }

    // AI4Bharat Rasa-13 is universal across all 13 languages — deduplicate in RAM under a single key
    final engineKey = effectiveEngineType == 'AI4BHARAT_RASA'
        ? 'AI4BHARAT_RASA'
        : 'mms_$languageCode';

    if (_ttsEngines.containsKey(engineKey)) return true;

    // Prevent Windows 11 system32 DLL hijacking by pre-loading bundled onnxruntime.dll
    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final ortPath = p.join(exeDir, 'onnxruntime.dll');
        if (File(ortPath).existsSync()) {
          DynamicLibrary.open(ortPath);
        } else {
          // Fallback for `flutter run`
          final runPath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'onnxruntime.dll');
          final runPathRel = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'onnxruntime.dll');
          if (File(runPath).existsSync()) {
            DynamicLibrary.open(runPath);
          } else if (File(runPathRel).existsSync()) {
            DynamicLibrary.open(runPathRel);
          }
        }
      } catch (_) {}
    }

    try {
      final dir = await _modelsDir();

      final rasaDir = p.join(dir, 'tts', 'rasa13');
      final rasaModel = p.join(rasaDir, 'vits.onnx');
      final rasaTokens = p.join(rasaDir, 'tokens.txt');

      // NOTE: dev-workspace File('converted_models/...') fallback removed —
      // invalid on Android (CWD is '/'). Models must be under app-support/models.

      final mmsDir = p.join(dir, 'tts', languageCode);
      final mmsModel = p.join(mmsDir, 'vits.onnx');
      final mmsTokens = p.join(mmsDir, 'tokens.txt');

      String model;
      String tokens;

      if (effectiveEngineType == 'AI4BHARAT_RASA') {
        if (File(rasaModel).existsSync() &&
            File(rasaTokens).existsSync() &&
            File(rasaModel).lengthSync() > 10 * 1024 * 1024) {
          model = rasaModel;
          tokens = rasaTokens;
        } else if (File(mmsModel).existsSync() &&
            File(mmsTokens).existsSync() &&
            File(mmsModel).lengthSync() > 10 * 1024 * 1024) {
          model = mmsModel;
          tokens = mmsTokens;
        } else {
          debugPrint('[TTS] AI4Bharat Rasa-13 model not found on disk');
          return false;
        }
      } else {
        // META_MMS requested
        if (File(mmsModel).existsSync() &&
            File(mmsTokens).existsSync() &&
            File(mmsModel).lengthSync() > 10 * 1024 * 1024) {
          model = mmsModel;
          tokens = mmsTokens;
        } else {
          debugPrint('[TTS] Meta MMS model not available or incomplete for $languageCode, falling back to Rasa-13');
          final ok = await initTts(languageCode, 'AI4BHARAT_RASA');
          if (ok && _ttsEngines.containsKey('AI4BHARAT_RASA')) {
            _ttsEngines[engineKey] = _ttsEngines['AI4BHARAT_RASA']!;
          }
          return ok;
        }
      }

      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: model,
            lexicon: '', // Character-based models must not receive 0-byte lexicon files
            tokens: tokens,
            lengthScale: 1.0,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
          ),
          numThreads: 2,
          debug: false,
        ),
      );

      // Cap active in-memory TTS engines to 2 to prevent RAM bloat on mobile
      if (_ttsEngines.length >= 2) {
        final oldestKey = _ttsEngineKeys.removeAt(0);
        final oldEngine = _ttsEngines.remove(oldestKey);
        try {
          oldEngine?.free();
          debugPrint('[TTS] Evicted oldest TTS engine from RAM: $oldestKey');
        } catch (e) {
          debugPrint('[TTS] Error freeing evicted engine: $e');
        }
      }

      _ttsEngines[engineKey] = sherpa.OfflineTts(config);
      _ttsEngineKeys.add(engineKey);
      debugPrint('[TTS] Initialized $effectiveEngineType ($engineKey) for $languageCode successfully');
      return true;
    } catch (e) {
      debugPrint('[TTS] VITS engine init error for $languageCode ($effectiveEngineType): $e');
      return false;
    }
  }

  @override
  Future<void> synthesizeSpeech(
    String text,
    String languageCode, [
    String gender = 'FEMALE',
    String ttsEngineType = 'META_MMS',
  ]) async {
    // Queue: concurrent inbound packets share one AudioPlayer.
    final completer = Completer<void>();
    final prev = _ttsLock;
    _ttsLock = completer.future.then((_) {}, onError: (_) {});
    await prev;
    try {
      await _synthesizeInner(text, languageCode, gender, ttsEngineType);
      completer.complete();
    } catch (e) {
      debugPrint('[TTS] synthesize error: $e');
      completer.complete();
    }
  }

  Future<void> _synthesizeInner(
    String text,
    String languageCode, [
    String gender = 'FEMALE',
    String ttsEngineType = 'META_MMS',
  ]) async {
    if (text.trim().isEmpty) return;

    // Guard: AI4Bharat Rasa-13 does not support Gujarati ('gu'), Odia ('or'), or English ('en')
    var effectiveEngine = _getEffectiveTtsEngine(ttsEngineType, languageCode);
    if (languageCode == 'en' &&
        effectiveEngine != 'AI4BHARAT_RASA' &&
        effectiveEngine != 'OS_NATIVE') {
      effectiveEngine = 'META_MMS';
    }

    // 0. OS Native TTS (Android TextToSpeech / Windows SAPI / OneCore)
    if (effectiveEngine == 'OS_NATIVE') {
      final spoke = await OsNativeTtsService.instance.speak(text, languageCode, gender);
      if (spoke) return;
      debugPrint('[TTS] OS Native TTS spoke or fell back to ONNX model.');
      effectiveEngine = 'META_MMS';
    }

    final engineKey = effectiveEngine == 'AI4BHARAT_RASA'
        ? 'AI4BHARAT_RASA'
        : 'mms_$languageCode';

    // 1. On-device neural VITS model (AI4Bharat Rasa-13 or Meta MMS)
    try {
      final ready = await initTts(languageCode, effectiveEngine);
      sherpa.OfflineTts? tts = _ttsEngines[engineKey];
      if (tts == null && _ttsEngines.containsKey('AI4BHARAT_RASA')) {
        tts = _ttsEngines['AI4BHARAT_RASA'];
      }
      if (tts == null && _ttsEngines.containsKey('mms_$languageCode')) {
        tts = _ttsEngines['mms_$languageCode'];
      }
      if (tts == null && _ttsEngines.isNotEmpty) {
        tts = _ttsEngines.values.first;
      }

      if (ready && tts != null) {
        final isMale = gender.toUpperCase() == 'MALE';
        final isRasa = effectiveEngine == 'AI4BHARAT_RASA';

        // Speaker ID routing:
        // - AI4Bharat Rasa-13 is multi-speaker (sid: 0 = Female, sid: 1 = Male)
        // - Meta MMS is strictly single-speaker (sid MUST be locked to 0)
        final speakerId = isRasa ? (isMale ? 1 : 0) : 0;

        // Cadence tuned for tactical communication (per rules.md):
        // - Rasa-13: 0.92 for baritone male, 1.02 for soprano female
        // - MMS: 0.95 for male, 1.02 for female
        final speed = isRasa
            ? (isMale ? 0.92 : 1.02)
            : (isMale ? 0.95 : 1.02);

        final normalizedText = ScriptNormalizationEngine.prepareTextForTts(
          text,
          languageCode,
          effectiveEngine,
        );

        final audio = tts.generate(text: normalizedText, sid: speakerId, speed: speed);
        if (audio.samples.isNotEmpty) {
          debugPrint(
            '[TTS] Synthesized ${audio.samples.length} samples at ${audio.sampleRate}Hz '
            'via $effectiveEngine for $languageCode (gender: $gender, sid: $speakerId, speed: $speed)',
          );
          await _playGeneratedAudio(
            audio.samples,
            audio.sampleRate,
            isMale: isMale,
            isRasa: isRasa,
          );
          return;
        } else {
          debugPrint('[TTS] VITS generator returned empty samples for text: "$text"');
        }
      }
    } catch (e) {
      debugPrint('[TTS] On-device VITS synthesis error: $e');
    }

    // 2. Strict Offline Fallback: If on-device neural VITS model is not ready, notify user
    debugPrint(
      '[TTS] On-device VITS model for $languageCode ($effectiveEngine) not ready or pack not downloaded. '
      'Please ensure model pack is installed in Settings.',
    );
  }

  /// Writes the generated Float32 samples to a WAV file and plays it via AudioPlayer.
  Future<void> _playGeneratedAudio(
    Float32List samples,
    int sampleRate, {
    bool isMale = false,
    bool isRasa = false,
  }) async {
    final tempDir = await getApplicationSupportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final wavPath = p.join(tempDir.path, 'tts_output_$timestamp.wav');

    // Stop previous playback before overwriting — serializes TTS so concurrent
    // calls don't delete a file still being played.
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    final int16Samples = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      int16Samples[i] = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    }

    // Apply a 25ms linear fade-out to the end of the audio buffer
    // This smoothly drops amplitude to zero, eliminating clicks, DC offset pops, and trailing "aa" vocoder schwas
    final fadeLength = math.min(int16Samples.length, (sampleRate * 0.025).round());
    final fadeStart = int16Samples.length - fadeLength;
    for (int i = fadeStart; i < int16Samples.length; i++) {
      final factor = (int16Samples.length - 1 - i) / fadeLength;
      int16Samples[i] = (int16Samples[i] * factor).toInt();
    }

    // Gender physical formant adjustment for single-speaker MMS (rules.md Section 4.2):
    // Rasa-13 already synthesizes the true neural male voice via sid: 1, so no sample rate scaling is needed.
    // For single-speaker Meta MMS, scale sample rate subtly by 0.91 (Male baritone) or 1.04 (Female soprano).
    final int effectiveSampleRate = isRasa
        ? sampleRate
        : (isMale ? (sampleRate * 0.91).round() : (sampleRate * 1.04).round());

    final wavData = _buildWav(int16Samples, effectiveSampleRate, 1);
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(wavData, flush: true);

    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setPlaybackRate(1.0);
      await _audioPlayer.play(DeviceFileSource(wavPath));
      debugPrint('[TTS] AudioPlayer playback active for: $wavPath (sampleRate: ${effectiveSampleRate}Hz)');
    } catch (e) {
      debugPrint('[TTS] AudioPlayer error: $e');
    }

    // Background cleanup: delete only files older than 5 minutes.
    // Previous logic deleted every other tts_output_*.wav immediately,
    // which raced with concurrent playback and cut audio.
    Future.microtask(() async {
      try {
        final now = DateTime.now();
        await for (final file in tempDir.list()) {
          if (file is File &&
              file.path.contains('tts_output_') &&
              file.path.endsWith('.wav') &&
              file.path != wavPath) {
            try {
              final stat = await file.stat();
              if (now.difference(stat.modified).inMinutes >= 5) {
                await file.delete();
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    });
  }

  /// Build a minimal WAV file from 16-bit PCM samples.
  Uint8List _buildWav(Int16List samples, int sampleRate, int channels) {
    final dataSize = samples.length * 2;
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);
    int offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // R
    buffer.setUint8(offset++, 0x49); // I
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint32(offset, fileSize - 8, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // W
    buffer.setUint8(offset++, 0x41); // A
    buffer.setUint8(offset++, 0x56); // V
    buffer.setUint8(offset++, 0x45); // E

    // fmt chunk
    buffer.setUint8(offset++, 0x66); // f
    buffer.setUint8(offset++, 0x6D); // m
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x20); // (space)
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4; // chunk size
    buffer.setUint16(offset, 1, Endian.little);
    offset += 2; // PCM format
    buffer.setUint16(offset, channels, Endian.little);
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, sampleRate * channels * 2, Endian.little);
    offset += 4; // byte rate
    buffer.setUint16(offset, channels * 2, Endian.little);
    offset += 2; // block align
    buffer.setUint16(offset, 16, Endian.little);
    offset += 2; // bits per sample

    // data chunk
    buffer.setUint8(offset++, 0x64); // d
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    for (int i = 0; i < samples.length; i++) {
      buffer.setInt16(offset, samples[i], Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }


  @override
  Future<void> stopSpeech() async {
    await _audioPlayer.stop();
  }

  @override
  bool get isSttLoaded => _offlineRecognizer != null;

  @override
  String? get loadedSttVariant => _loadedSttVariant;

  @override
  void unloadStt() {
    try {
      _offlineRecognizer?.free();
    } catch (_) {}
    _offlineRecognizer = null;
    _isIndicConformer = false;
    _loadedSttVariant = null;
    _audioBuffer.clear();
    debugPrint('[STT] Recognizer models successfully offloaded from RAM');
  }

  @override
  bool get isTtsLoaded => _ttsEngines.isNotEmpty;

  @override
  List<String> get loadedTtsKeys => List.unmodifiable(_ttsEngines.keys);

  @override
  bool isTtsKeyLoaded(String key) {
    if (key.toUpperCase().contains('OS_NATIVE')) return true;
    return _ttsEngines.containsKey(key);
  }

  @override
  void unloadTtsKey(String key) {
    if (_ttsEngines.containsKey(key)) {
      final tts = _ttsEngines.remove(key);
      _ttsEngineKeys.remove(key);
      try {
        tts?.free();
        debugPrint('[TTS] Specific model $key offloaded from RAM');
      } catch (e) {
        debugPrint('[TTS] Error freeing model $key: $e');
      }
    }
  }

  @override
  void unloadTts() {
    for (final tts in _ttsEngines.values) {
      try {
        tts.free();
      } catch (_) {}
    }
    _ttsEngines.clear();
    _ttsEngineKeys.clear();
    debugPrint('[TTS] Neural VITS models successfully offloaded from RAM');
  }

  String _getEffectiveTtsEngine(String engineType, String languageCode) {
    if (engineType != 'AI4BHARAT_RASA') return engineType;
    const unsupportedRasaLangs = {'gu', 'or', 'en'};
    if (unsupportedRasaLangs.contains(languageCode.toLowerCase())) {
      final langName = LanguagePackManager.supportedLanguages
          .firstWhere((l) => l.code == languageCode.toLowerCase(),
              orElse: () => LanguageMetadata(
                  code: languageCode,
                  iso3: '',
                  englishName: languageCode,
                  nativeName: ''))
          .englishName;
      debugPrint(
        '⚠️ [TTS WARNING] AI4Bharat Rasa-13 does NOT support $langName ($languageCode). '
        'Bypassing Rasa-13 to prevent silence or pronunciation distortion. Automatically falling back to Meta MMS-TTS.',
      );
      return 'META_MMS';
    }
    return engineType;
  }

  @override
  Future<void> release() async {
    await stopListening();
    await stopSpeech();
    unloadStt();
    unloadTts();
    await _audioPlayer.dispose();
  }
}
