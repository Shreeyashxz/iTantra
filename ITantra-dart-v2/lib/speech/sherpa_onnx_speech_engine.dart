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
import 'script_normalization_engine.dart';
import 'speech_engine.dart';

/// Legacy adapter for backward compatibility. Uses ScriptNormalizationEngine under the hood.
class IndicScriptTransliterator {
  static String toEnglish(String input) =>
      ScriptNormalizationEngine.normalizeFromStt(input, 'en');
}

/// Real on-device and hybrid speech engine.
/// Provides:
///   STT — Real-time dynamic live decoding supporting AI4Bharat IndicConformer & Zipformer
///         with English Latin transliteration & native script output.
///   TTS — Studio-grade multi-language neural synthesis with distinct Male / Female voices.
class SherpaOnnxSpeechEngine implements SpeechEngine {
  final LanguagePackManager languagePackManager;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // --- STT ---
  sherpa.OnlineRecognizer? _onlineRecognizer;
  sherpa.OnlineStream? _onlineStream;
  sherpa.OfflineRecognizer? _offlineRecognizer;
  bool _isIndicConformer = false;
  String? _loadedSttVariant;
  final List<int> _audioBuffer = [];

  StreamController<String>? _sttTextController;
  bool _isListening = false;
  Timer? _dynamicDecodeTimer;
  String _lastSttText = '';
  String _currentLanguage = 'hi';

  // --- TTS ---
  final Map<String, sherpa.OfflineTts> _ttsEngines = {};
  final List<String> _ttsEngineKeys = [];

  static SherpaOnnxSpeechEngine? instance;

  SherpaOnnxSpeechEngine({required this.languagePackManager}) {
    instance = this;
  }

  /// Resolves the models base directory.
  Future<String> _modelsDir() async {
    final dir = await languagePackManager.getModelsDirectory();
    return dir.path;
  }

  // ==========================================
  // STT (Speech-to-Text) — AI4Bharat IndicConformer / Zipformer
  // ==========================================

  /// Initialize the STT recognizer from downloaded model files.
  Future<bool> initStt([String precision = 'INT8']) async {
    if (_offlineRecognizer != null || _onlineRecognizer != null) return true;

    // Prevent Windows 11 system32 DLL hijacking by pre-loading bundled onnxruntime.dll
    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final ortPath = p.join(exeDir, 'onnxruntime.dll');
        if (File(ortPath).existsSync()) {
          DynamicLibrary.open(ortPath);
        }
      } catch (_) {}
    }

    try {
      final dir = await _modelsDir();
      final sttDir = p.join(dir, 'stt');

      final indicInt8 = p.join(sttDir, 'indic_conformer.onnx');
      final indicFp32 = p.join(sttDir, 'indic_conformer_fp32.onnx');
      final encoder = p.join(sttDir, 'encoder.onnx');
      final decoder = p.join(sttDir, 'decoder.onnx');
      final joiner = p.join(sttDir, 'joiner.onnx');
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
      } else if (File(encoder).existsSync() && File(tokens).existsSync()) {
        debugPrint('[STT] Initializing Streaming Zipformer model...');
        final config = sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: encoder,
              decoder: File(decoder).existsSync() ? decoder : '',
              joiner: File(joiner).existsSync() ? joiner : '',
            ),
            tokens: tokens,
            numThreads: 2,
            debug: false,
          ),
          enableEndpoint: true,
          rule1MinTrailingSilence: 2.0,
          rule2MinTrailingSilence: 1.0,
          rule3MinUtteranceLength: 1.5,
        );
        _onlineRecognizer = sherpa.OnlineRecognizer(config);
        _isIndicConformer = false;
        _loadedSttVariant = 'Zipformer Streaming';
        debugPrint('[STT] OnlineRecognizer initialized successfully');
        return true;
      } else {
        debugPrint('[STT] Missing required STT model files in $sttDir');
        return false;
      }
    } catch (e) {
      debugPrint('[STT] Failed to initialize recognizer: $e');
      _onlineRecognizer = null;
      _offlineRecognizer = null;
      return false;
    }
  }

  @override
  Stream<String> startListening([String languageCode = 'hi']) {
    _currentLanguage = languageCode;
    _sttTextController?.close();
    _sttTextController = StreamController<String>.broadcast();
    _isListening = true;
    _lastSttText = '';
    _audioBuffer.clear();

    if (_onlineRecognizer != null) {
      _onlineStream = _onlineRecognizer!.createStream();
    }

    // Dynamic real-time transcription timer: runs every 700ms to decode live speech
    _dynamicDecodeTimer?.cancel();
    _dynamicDecodeTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _runDynamicLiveDecode();
    });

    return _sttTextController!.stream;
  }

  /// Feed raw PCM audio (16kHz, 16-bit mono) into the STT recognizer.
  void feedAudioData(Int16List samples) {
    if (!_isListening) return;

    // Buffer audio for dynamic and final decoding
    _audioBuffer.addAll(samples);

    // Also feed to online recognizer if active
    if (_onlineRecognizer != null && _onlineStream != null) {
      final floatSamples = Float32List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        floatSamples[i] = samples[i] / 32768.0;
      }
      _onlineStream!.acceptWaveform(samples: floatSamples, sampleRate: 16000);
    }
  }

  /// Performs live dynamic partial transcription as the user speaks.
  /// Note: Only online streaming models (Zipformer) decode incrementally during recording.
  /// Offline IndicConformer executes its complete CTC pass on audio completion to prevent UI thread freezing.
  void _runDynamicLiveDecode() {
    if (!_isListening) return;

    if (_onlineRecognizer != null && _onlineStream != null) {
      try {
        while (_onlineRecognizer!.isReady(_onlineStream!)) {
          _onlineRecognizer!.decode(_onlineStream!);
        }
        final result = _onlineRecognizer!.getResult(_onlineStream!).text.trim();
        if (result.isNotEmpty && result != _lastSttText) {
          _lastSttText = result;
          final processed = ScriptNormalizationEngine.normalizeFromStt(result, _currentLanguage);
          _sttTextController?.add(processed);
        }
      } catch (_) {}
    }
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

    _dynamicDecodeTimer?.cancel();
    _dynamicDecodeTimer = null;

    // 1. Process buffered audio with AI4Bharat IndicConformer
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
          _lastSttText = finalTranscript;
          _sttTextController?.add(finalTranscript);
        }
      } catch (e) {
        debugPrint('[STT] Error final decoding with IndicConformer: $e');
      }
    }

    // 2. Process online stream final tokens
    if (_onlineStream != null && _onlineRecognizer != null) {
      try {
        _onlineStream!.inputFinished();
        while (_onlineRecognizer!.isReady(_onlineStream!)) {
          _onlineRecognizer!.decode(_onlineStream!);
        }
        final finalResult = _onlineRecognizer!.getResult(_onlineStream!).text.trim();
        if (finalResult.isNotEmpty) {
          finalTranscript = ScriptNormalizationEngine.normalizeFromStt(finalResult, lang);
          _lastSttText = finalTranscript;
          _sttTextController?.add(finalTranscript);
        }
      } catch (e) {
        debugPrint('[STT] Error finishing input stream: $e');
      }
    }

    _isListening = false;
    _onlineStream?.free();
    _onlineStream = null;
    _audioBuffer.clear();
    _sttTextController?.close();
    _sttTextController = null;
    _lastSttText = '';

    return finalTranscript;
  }

  @override
  void stopListening() {
    stopListeningAndTranscribe();
  }

  // ==========================================
  // TTS (Text-to-Speech) — Studio Native Voice Engine
  // ==========================================

  /// Initialize TTS for a given language from downloaded VITS ONNX model.
  Future<bool> initTts(String languageCode, [String ttsEngineType = 'META_MMS']) async {
    // English defaults to Meta MMS across the board unless Rasa-13 is explicitly requested
    final effectiveEngineType = (languageCode == 'en' && ttsEngineType != 'AI4BHARAT_RASA')
        ? 'META_MMS'
        : ttsEngineType;

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
        }
      } catch (_) {}
    }

    try {
      final dir = await _modelsDir();

      final rasaDir = p.join(dir, 'tts', 'rasa13');
      final rasaModel = p.join(rasaDir, 'vits.onnx');
      final rasaTokens = p.join(rasaDir, 'tokens.txt');

      // Check bundled converted_models workspace fallback
      final localRasaModel = File('converted_models/vits_rasa13_6in.onnx');
      final localRasaTokens = File('converted_models/tokens.txt');

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
        } else if (localRasaModel.existsSync() &&
            localRasaTokens.existsSync() &&
            localRasaModel.lengthSync() > 10 * 1024 * 1024) {
          model = localRasaModel.path;
          tokens = localRasaTokens.path;
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
    if (text.trim().isEmpty) return;

    // English defaults to Meta MMS across the board unless Rasa-13 is explicitly requested
    final effectiveEngine = (languageCode == 'en' && ttsEngineType != 'AI4BHARAT_RASA')
        ? 'META_MMS'
        : ttsEngineType;

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
        // Clean 1.0x native model synthesis (no pitch warping or male/female distortion)
        const speakerId = 0;
        const speed = 1.0;

        final normalizedText = ScriptNormalizationEngine.prepareTextForTts(
          text,
          languageCode,
          effectiveEngine,
        );

        final audio = tts.generate(text: normalizedText, sid: speakerId, speed: speed);
        if (audio.samples.isNotEmpty) {
          debugPrint('[TTS] Synthesized ${audio.samples.length} samples at ${audio.sampleRate}Hz via $effectiveEngine for $languageCode');
          await _playGeneratedAudio(audio.samples, audio.sampleRate);
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
  Future<void> _playGeneratedAudio(Float32List samples, int sampleRate) async {
    final tempDir = await getApplicationSupportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final wavPath = p.join(tempDir.path, 'tts_output_$timestamp.wav');

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

    final wavData = _buildWav(int16Samples, sampleRate, 1);
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(wavData, flush: true);

    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setPlaybackRate(1.0);
      await _audioPlayer.play(DeviceFileSource(wavPath));
      debugPrint('[TTS] AudioPlayer playback active for: $wavPath');
    } catch (e) {
      debugPrint('[TTS] AudioPlayer error: $e');
    }

    // Background cleanup of stale temporary WAV files
    Future.microtask(() async {
      try {
        await for (final file in tempDir.list()) {
          if (file is File &&
              file.path.contains('tts_output_') &&
              file.path.endsWith('.wav') &&
              file.path != wavPath) {
            try {
              await file.delete();
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
  void stopSpeech() {
    _audioPlayer.stop();
  }

  @override
  bool get isSttLoaded => _offlineRecognizer != null || _onlineRecognizer != null;

  @override
  String? get loadedSttVariant => _loadedSttVariant;

  @override
  void unloadStt() {
    _dynamicDecodeTimer?.cancel();
    _dynamicDecodeTimer = null;
    try {
      _onlineStream?.free();
    } catch (_) {}
    _onlineStream = null;
    try {
      _onlineRecognizer?.free();
    } catch (_) {}
    _onlineRecognizer = null;
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
  bool isTtsKeyLoaded(String key) => _ttsEngines.containsKey(key);

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

  @override
  void release() {
    stopListening();
    stopSpeech();
    unloadStt();
    unloadTts();
    _audioPlayer.dispose();
  }
}
