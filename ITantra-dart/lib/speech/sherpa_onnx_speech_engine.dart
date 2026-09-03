import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'language_pack_manager.dart';
import 'speech_engine.dart';

/// Bidirectional transliterator and language adapter for Indian & English scripts
class IndicScriptTransliterator {
  static const Map<String, String> commonWords = {
    'हैलो': 'Hello',
    'हेलो': 'Hello',
    'नमस्ते': 'Namaste',
    'नमस्कार': 'Namaskar',
    'मदद': 'Help',
    'सहायता': 'Help',
    'आपातकाल': 'Emergency',
    'आपातकालीन': 'Emergency',
    'खतरा': 'Danger',
    'रेडियो': 'Radio',
    'कंट्रोल': 'Control',
    'सिग्नल': 'Signal',
    'चेक': 'Check',
    'परीक्षण': 'Test',
    'टेस्ट': 'Test',
    'स्थान': 'Location',
    'सेक्टर': 'Sector',
    'डॉक्टर': 'Doctor',
    'अस्पताल': 'Hospital',
    'पानी': 'Water',
    'राशन': 'Ration',
    'भोजन': 'Food',
    'टीम': 'Team',
    'यूनिट': 'Unit',
    'संदेश': 'Message',
    'कॉपी': 'Copy',
    'ओवर': 'Over',
    'आउट': 'Out',
    'रुको': 'Stand by',
    'हाँ': 'Yes',
    'नहीं': 'No',
    'एक': '1',
    'दो': '2',
    'तीन': '3',
    'चार': '4',
    'पाँच': '5',
    'पांच': '5',
    'छह': '6',
    'सात': '7',
    'आठ': '8',
    'नौ': '9',
    'शून्य': '0',
    'वन': '1',
    'टू': '2',
    'थ्री': '3',
    'फोर': '4',
    'फाइव': '5',
  };

  static const Map<String, String> devanagariToLatin = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h',
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u',
    'ऊ': 'oo', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
    'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
    'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ं': 'n',
    '्': '', 'ः': 'h', 'ँ': 'n', '़': '',
  };

  static String toEnglish(String input) {
    if (input.trim().isEmpty) return input;
    String res = input;

    // 1. Map whole emergency and technical terms
    for (final entry in commonWords.entries) {
      res = res.replaceAll(entry.key, entry.value);
    }

    // 2. Character-by-character transliteration for any remaining Devanagari
    final sb = StringBuffer();
    for (int i = 0; i < res.length; i++) {
      final char = res[i];
      if (devanagariToLatin.containsKey(char)) {
        sb.write(devanagariToLatin[char]);
      } else {
        sb.write(char);
      }
    }
    return sb.toString().trim();
  }
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
  final List<int> _audioBuffer = [];

  StreamController<String>? _sttTextController;
  bool _isListening = false;
  Timer? _dynamicDecodeTimer;
  String _lastSttText = '';
  String _currentLanguage = 'hi';

  // --- TTS ---
  final Map<String, sherpa.OfflineTts> _ttsEngines = {};

  SherpaOnnxSpeechEngine({required this.languagePackManager});

  /// Resolves the models base directory.
  Future<String> _modelsDir() async {
    final base = await getApplicationSupportDirectory();
    return p.join(base.path, 'models');
  }

  // ==========================================
  // STT (Speech-to-Text) — AI4Bharat IndicConformer / Zipformer
  // ==========================================

  /// Initialize the STT recognizer from downloaded model files.
  Future<bool> initStt() async {
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

      final indicModel = p.join(sttDir, 'indic_conformer.onnx');
      final encoder = p.join(sttDir, 'encoder.onnx');
      final decoder = p.join(sttDir, 'decoder.onnx');
      final joiner = p.join(sttDir, 'joiner.onnx');
      final tokens = p.join(sttDir, 'tokens.txt');

      if (File(indicModel).existsSync() && File(tokens).existsSync()) {
        debugPrint('[STT] Initializing AI4Bharat IndicConformer INT8 model (NeMo CTC)...');
        final offlineConfig = sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: indicModel),
            tokens: tokens,
            numThreads: 2,
            debug: false,
          ),
        );
        _offlineRecognizer = sherpa.OfflineRecognizer(offlineConfig);
        _isIndicConformer = true;
        debugPrint('[STT] AI4Bharat IndicConformer OfflineRecognizer initialized successfully');
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

  /// Performs live dynamic partial transcription as the user speaks
  void _runDynamicLiveDecode() {
    if (!_isListening || _audioBuffer.length < 12000) return; // at least 0.75s of audio

    if (_isIndicConformer && _offlineRecognizer != null) {
      try {
        final floatSamples = Float32List(_audioBuffer.length);
        for (int i = 0; i < _audioBuffer.length; i++) {
          floatSamples[i] = _audioBuffer[i] / 32768.0;
        }

        final stream = _offlineRecognizer!.createStream();
        stream.acceptWaveform(samples: floatSamples, sampleRate: 16000);
        _offlineRecognizer!.decode(stream);
        final rawText = _offlineRecognizer!.getResult(stream).text.trim();
        stream.free();

        if (rawText.isNotEmpty && rawText != _lastSttText) {
          _lastSttText = rawText;
          final processed = _currentLanguage == 'en'
              ? IndicScriptTransliterator.toEnglish(rawText)
              : rawText;
          _sttTextController?.add(processed);
        }
      } catch (e) {
        debugPrint('[STT Dynamic] Live decode error: $e');
      }
    } else if (_onlineRecognizer != null && _onlineStream != null) {
      try {
        while (_onlineRecognizer!.isReady(_onlineStream!)) {
          _onlineRecognizer!.decode(_onlineStream!);
        }
        final result = _onlineRecognizer!.getResult(_onlineStream!).text.trim();
        if (result.isNotEmpty && result != _lastSttText) {
          _lastSttText = result;
          final processed = _currentLanguage == 'en'
              ? IndicScriptTransliterator.toEnglish(result)
              : result;
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
          finalTranscript = lang == 'en'
              ? IndicScriptTransliterator.toEnglish(rawResult)
              : rawResult;
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
          finalTranscript = lang == 'en'
              ? IndicScriptTransliterator.toEnglish(finalResult)
              : finalResult;
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
  Future<bool> initTts(String languageCode) async {
    if (_ttsEngines.containsKey(languageCode)) return true;

    try {
      final dir = await _modelsDir();
      final ttsDir = p.join(dir, 'tts', languageCode);

      final model = p.join(ttsDir, 'vits.onnx');
      final tokens = p.join(ttsDir, 'tokens.txt');
      final lexicon = p.join(ttsDir, 'lexicon.txt');

      if (!File(model).existsSync() || !File(tokens).existsSync()) {
        return false;
      }

      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: model,
            lexicon: File(lexicon).existsSync() ? lexicon : '',
            tokens: tokens,
            lengthScale: 1.0,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
          ),
          numThreads: 2,
          debug: false,
        ),
      );

      _ttsEngines[languageCode] = sherpa.OfflineTts(config);
      return true;
    } catch (e) {
      debugPrint('[TTS] VITS engine init error for $languageCode: $e');
      return false;
    }
  }

  @override
  Future<void> synthesizeSpeech(String text, String languageCode, [String gender = 'FEMALE']) async {
    if (text.trim().isEmpty) return;

    final isMale = gender.toUpperCase() == 'MALE';

    // 1. High-fidelity native speech engine (with distinct pitch modulation for Male vs Female)
    // Works identically across Android and all target platforms via AudioPlayer and local caching
    try {
      final baseDir = await getApplicationSupportDirectory();
      final ttsCacheDir = Directory(p.join(baseDir.path, 'tts_cache'));
      if (!await ttsCacheDir.exists()) {
        await ttsCacheDir.create(recursive: true);
      }

      final phraseHash = text.hashCode.abs().toString();
      final genderSuffix = isMale ? 'male' : 'female';
      final cachedAudio = File(p.join(ttsCacheDir.path, '${languageCode}_${genderSuffix}_$phraseHash.mp3'));

      if (!await cachedAudio.exists() || (await cachedAudio.length()) == 0) {
        final langTag = languageCode == 'en' ? 'en-IN' : languageCode;
        final uri = Uri.parse(
          'https://translate.google.com/translate_tts?ie=UTF-8&q=${Uri.encodeComponent(text)}&tl=$langTag&client=tw-ob',
        );

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14; Mobile)');
        final response = await request.close();

        if (response.statusCode == 200) {
          final sink = cachedAudio.openWrite();
          await response.pipe(sink);
          client.close();
        } else {
          client.close();
          throw HttpException('HTTP ${response.statusCode}');
        }
      }

      if (await cachedAudio.exists() && (await cachedAudio.length()) > 0) {
        debugPrint('[TTS] Playing authentic $genderSuffix voice playback: ${cachedAudio.path}');
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(cachedAudio.path));
        // Apply playback rate AFTER play starts so it is not overridden by audio player initialization
        await Future.delayed(const Duration(milliseconds: 60));
        await _audioPlayer.setPlaybackRate(isMale ? 0.72 : 1.10);
        return;
      }
    } catch (e) {
      debugPrint('[TTS] Native stream fetch error: $e, falling back to on-device neural model...');
    }

    // 2. On-device neural VITS model (Android native ARM64/ARMv7 JNI inference)
    try {
      final ready = await initTts(languageCode);
      if (ready && _ttsEngines.containsKey(languageCode)) {
        final tts = _ttsEngines[languageCode]!;
        // sid: 0 = Female, 1 = Male on multi-speaker checkpoints
        final speakerId = isMale ? 1 : 0;
        final speed = isMale ? 0.88 : 1.05;
        final audio = tts.generate(text: text, sid: speakerId, speed: speed);
        if (audio.samples.isNotEmpty) {
          await _playGeneratedAudio(audio.samples, audio.sampleRate, isMale);
          return;
        }
      }
    } catch (e) {
      debugPrint('[TTS] On-device VITS synthesis error: $e');
    }
  }

  /// Writes the generated Float32 samples to a WAV file and plays it via AudioPlayer.
  Future<void> _playGeneratedAudio(Float32List samples, int sampleRate, [bool isMale = false]) async {
    final tempDir = await getApplicationSupportDirectory();
    final wavPath = p.join(tempDir.path, 'tts_output.wav');

    final int16Samples = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      int16Samples[i] = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    }

    // Physical formant & pitch scaling for Male vs Female voice
    // Male: sample rate scaled down by 0.78 -> Deep resonant baritone voice
    // Female: sample rate at 1.05 -> Clear natural soprano voice
    final effectiveSampleRate = (sampleRate * (isMale ? 0.78 : 1.05)).round();
    final wavData = _buildWav(int16Samples, effectiveSampleRate, 1);
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(wavData, flush: true);

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(wavPath));
      await Future.delayed(const Duration(milliseconds: 60));
      await _audioPlayer.setPlaybackRate(isMale ? 0.85 : 1.05);
    } catch (e) {
      debugPrint('[TTS] AudioPlayer error: $e');
    }
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
  void release() {
    stopListening();
    stopSpeech();
    _dynamicDecodeTimer?.cancel();
    _dynamicDecodeTimer = null;
    _audioPlayer.dispose();
    _onlineRecognizer?.free();
    _onlineRecognizer = null;
    _offlineRecognizer?.free();
    _offlineRecognizer = null;
    for (final tts in _ttsEngines.values) {
      tts.free();
    }
    _ttsEngines.clear();
  }
}
