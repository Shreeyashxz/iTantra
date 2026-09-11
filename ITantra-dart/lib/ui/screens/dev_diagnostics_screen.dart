import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../speech/audio_recorder_service.dart';
import '../../speech/language_pack_manager.dart';
import '../../speech/silero_vad_engine.dart';

class JitChunk {
  final int id;
  final String originalText;
  String translatedText;
  final DateTime startTime;
  int? mtDurationMs;
  int? ttsDurationMs;
  String status; // 'DETECTED', 'TRANSLATING', 'SYNTHESIZING', 'PLAYED', 'ERROR'

  JitChunk({
    required this.id,
    required this.originalText,
    this.translatedText = '',
    required this.startTime,
    this.mtDurationMs,
    this.ttsDurationMs,
    this.status = 'DETECTED',
  });
}

class DevDiagnosticsScreen extends StatefulWidget {
  const DevDiagnosticsScreen({super.key});

  @override
  State<DevDiagnosticsScreen> createState() => _DevDiagnosticsScreenState();
}

class _DevDiagnosticsScreenState extends State<DevDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  // --- Audio Recording & VAD / STT State ---
  late final AudioRecorderService _recorder;
  late final SileroVadEngine _vad;

  StreamSubscription<Int16List>? _audioSub;
  StreamSubscription<bool>? _vadSub;
  StreamSubscription<String>? _sttTextSub;

  bool _isRecording = false;
  bool _isVoiceDetected = false;
  bool _sttInitialized = false;
  String _sttInitStatus = 'Not initialized';
  double _currentAmplitude = 0.0;
  int _totalSamplesCaptured = 0;
  int _recordDurationSeconds = 0;
  Timer? _durationTimer;

  String _formedSttText = '';
  final List<String> _transcriptLog = [];
  String _selectedSttLang = 'hi';
  int _lastAmpUpdateMs = 0;

  // --- Model Power / Memory Offload Toggles ---
  bool _isSttModelLoaded = true;
  bool _isTtsModelLoaded = true;
  bool _isMtModelLoaded = true;

  // --- TTS State ---
  String _selectedTtsLang = 'hi';
  final TextEditingController _ttsTextController = TextEditingController(
    text: 'नमस्ते, आई-तंत्र आपातकालीन न्यूरल ट्रांससीवर में आपका स्वागत है।',
  );
  bool _isSynthesizing = false;
  String _ttsStatusMessage = 'Idle (Ready to synthesize)';

  // --- Test 3: STT -> TTS Direct Voice State ---
  bool _isTest3Active = true;
  bool _isTest3Recording = false;
  bool _isTest3Synthesizing = false;
  String _test3Stage = 'Idle (Ready to test STT ➔ TTS Direct Voice Loop)';
  String _test3RecognizedText = '';
  String _selectedTest3Lang = 'hi';

  // --- Test 4: STT -> MT -> TTS Dynamic JIT Pipeline State ---
  bool _isTest4Active = true;
  bool _isTest4Recording = false;
  String _test4Stage = 'Idle (Ready to test Dynamic JIT Pipeline)';
  String _selectedTest4SourceLang = 'hi';
  String _selectedTest4TargetLang = 'en';
  final List<JitChunk> _jitChunks = [];
  int _jitChunkCounter = 0;
  String _lastDispatchedJitText = '';
  Timer? _jitStreamCheckTimer;

  // Preset phrases for all 10 languages
  static const Map<String, String> _presets = {
    'hi': 'नमस्ते, आई-तंत्र आपातकालीन न्यूरल ट्रांससीवर में आपका स्वागत है।',
    'en': 'Emergency priority message. Coordinates confirmed. Transceiver link active.',
    'gu': 'નમસ્તે, કટોકટીમાં આઈ-તંત્ર ન્યુરલ ટ્રાન્સસીવર કાર્યરત છે.',
    'mr': 'नमस्कार, आणीबाणी प्रसंगी आय-तंत्र न्यूरल ट्रान्सीव्हर सज्ज आहे.',
    'kn': 'ನಮಸ್ಕಾರ, ತುರ್ತು ಪರಿಸ್ಥಿತಿಯಲ್ಲಿ ಐ-ತಂತ್ರ ರೇಡಿಯೋ ಸಂಪರ್ಕದಲ್ಲಿದೆ.',
    'ml': 'നമസ്കാരം, അടിയന്തര സാഹചര്യത്തിൽ ഐ-തന്ത്ര ട്രാൻസ്‌സീവർ സജീവമാണ്.',
    'ta': 'வணக்கம், அவசர கால ஐ-தந்திர நரம்பியல் டிரான்ஸ்சீவர் செயல்படுகிறது.',
    'te': 'నమస్కారం, అత్యవసర పరిస్థితిలో ఐ-తంత్ర న్యూరల్ ట్రాన్స్‌సీవర్ పనిచేస్తుంది.',
    'or': 'ନମସ୍କାର, ଜରୁରୀକାଳୀନ ପରିସ୍ଥିତିରେ ଆଇ-ତନ୍ତ୍ର ରେଡିଓ ସକ୍ରିୟ ଅଛି।',
    'bn': 'নমস্কার, জরুরী অবস্থায় আই-তন্ত্র নিউরাল ট্রান্সিভার প্রস্তুত।',
  };

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorderService();
    _vad = SileroVadEngine();
    // Defer STT init to after first frame when context is available
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSttEngine());
  }

  Future<void> _initSttEngine() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final success = await speechEngine.initStt();
    if (mounted) {
      setState(() {
        _sttInitialized = success;
        _sttInitStatus = success
            ? 'AI4Bharat IndicConformer INT8 Ready'
            : 'STT model not installed — download from Settings';
      });
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _jitStreamCheckTimer?.cancel();
    _audioSub?.cancel();
    _vadSub?.cancel();
    _sttTextSub?.cancel();
    _recorder.dispose();
    _vad.release();
    _ttsTextController.dispose();
    super.dispose();
  }

  // --- Dynamic Model Load / Offload Handlers ---
  Future<void> _toggleSttModel(bool enable) async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    if (enable) {
      setState(() => _sttInitStatus = 'Loading AI4Bharat IndicConformer into RAM...');
      final ok = await speechEngine.initStt();
      if (mounted) {
        setState(() {
          _isSttModelLoaded = ok;
          _sttInitialized = ok;
          _sttInitStatus = ok
              ? 'AI4Bharat IndicConformer INT8 (Loaded in RAM)'
              : 'STT model not installed — download from Settings';
        });
      }
    } else {
      speechEngine.unloadStt();
      if (mounted) {
        setState(() {
          _isSttModelLoaded = false;
          _sttInitialized = false;
          _sttInitStatus = 'STT Model Offloaded (0 MB RAM)';
        });
      }
    }
  }

  Future<void> _toggleTtsModel(bool enable) async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settings = context.read<SettingsController>();
    if (enable) {
      setState(() => _ttsStatusMessage = 'Loading VITS neural model into RAM...');
      final ok = await speechEngine.initTts(_selectedTtsLang, settings.ttsEngineType);
      if (mounted) {
        setState(() {
          _isTtsModelLoaded = ok;
          _ttsStatusMessage = ok
              ? 'Neural VITS Engine Loaded (${settings.ttsEngineType})'
              : 'Failed to load TTS model';
        });
      }
    } else {
      speechEngine.unloadTts();
      if (mounted) {
        setState(() {
          _isTtsModelLoaded = false;
          _ttsStatusMessage = 'TTS Models Offloaded (0 MB RAM)';
        });
      }
    }
  }

  void _toggleMtModel(bool enable) {
    final transceiverCtrl = context.read<TransceiverController>();
    if (enable) {
      transceiverCtrl.transEngine.load();
      setState(() => _isMtModelLoaded = true);
    } else {
      transceiverCtrl.transEngine.unload();
      setState(() => _isMtModelLoaded = false);
    }
  }

  // --- STT Diagnostic Methods ---
  Future<void> _startSttRecordTest() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;

    setState(() {
      _isRecording = true;
      _totalSamplesCaptured = 0;
      _recordDurationSeconds = 0;
      _currentAmplitude = 0.0;
      _formedSttText = _sttInitialized
          ? 'Listening to microphone (STT active)...'
          : 'Recording audio (STT not loaded — VAD only mode)...';
    });

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordDurationSeconds++);
      }
    });

    try {
      // Apply active VAD sensitivity
      final sensitivity = context.read<SettingsController>().vadSensitivity;
      _vad.setSensitivity(sensitivity);

      // Start the STT listening stream and subscribe to live dynamic transcripts
      if (_sttInitialized) {
        final sttStream = speechEngine.startListening(_selectedSttLang);
        _sttTextSub?.cancel();
        _sttTextSub = sttStream.listen((text) {
          if (mounted && text.trim().isNotEmpty) {
            setState(() {
              _formedSttText = text;
            });
          }
        });
      }

      final stream = await _recorder.startRecording();

      _audioSub?.cancel();
      _audioSub = stream.listen((chunk) {
        _totalSamplesCaptured += chunk.length;

        // Feed audio to the real STT recognizer
        if (_sttInitialized) {
          speechEngine.feedAudioData(chunk);
        }

        // Throttle amplitude UI updates to max 10 FPS to prevent UI thread stutter
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastAmpUpdateMs > 90) {
          _lastAmpUpdateMs = nowMs;
          double sum = 0;
          for (int i = 0; i < chunk.length; i += 4) {
            final norm = chunk[i] / 32768.0;
            sum += norm * norm;
          }
          final rms = sqrt(sum / (chunk.length / 4));

          if (mounted) {
            setState(() {
              _currentAmplitude = (rms * 8.0).clamp(0.0, 1.0);
            });
          }
        }
      });

      _vadSub?.cancel();
      _vadSub = _vad.startVad(stream).listen((isSpeech) {
        if (mounted && _isVoiceDetected != isSpeech) {
          setState(() {
            _isVoiceDetected = isSpeech;
          });
        }
      });
    } catch (e) {
      setState(() {
        _formedSttText = 'Error initializing audio recording: $e';
      });
    }
  }

  Future<void> _stopSttRecordTest() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;

    _durationTimer?.cancel();
    await _audioSub?.cancel();
    _audioSub = null;
    await _vadSub?.cancel();
    _vadSub = null;
    await _recorder.stopRecording();
    _vad.stopVad();

    setState(() {
      _formedSttText = 'Decoding audio with AI4Bharat IndicConformer...';
    });

    // Transcribe with AI4Bharat IndicConformer in target language mode
    final transcript = await speechEngine.stopListeningAndTranscribe(_selectedSttLang);

    await _sttTextSub?.cancel();
    _sttTextSub = null;

    final seconds = _recordDurationSeconds > 0 ? _recordDurationSeconds : 1;
    final kb = (_totalSamplesCaptured * 2) / 1024.0;
    final summary = 'Captured ${seconds}s audio (${kb.toStringAsFixed(1)} KB PCM).';

    setState(() {
      _isRecording = false;
      _currentAmplitude = 0.0;
      _isVoiceDetected = false;
      if (transcript.isNotEmpty) {
        _formedSttText = transcript;
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT (AI4Bharat): "$transcript"');
      } else {
        _formedSttText = '$summary No words recognized. Try speaking closer to mic or increasing VAD sensitivity.';
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $summary No words recognized.');
      }
    });
  }

  // --- TTS Diagnostic Methods ---
  Future<void> _runTtsSpeechTest(BuildContext context) async {
    final text = _ttsTextController.text.trim();
    if (text.isEmpty) return;

    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settingsController = context.read<SettingsController>();

    // Check if model is downloaded
    if (!settingsController.isTtsReady(_selectedTtsLang)) {
      setState(() {
        _ttsStatusMessage = 'TTS model not downloaded for $_selectedTtsLang — download from Settings first!';
      });
      return;
    }

    setState(() {
      _isSynthesizing = true;
      _ttsStatusMessage = 'Initializing VITS engine for [$_selectedTtsLang]...';
    });

    try {
      setState(() {
        _ttsStatusMessage = 'Synthesizing neural speech waveform...';
      });
      final settings = context.read<SettingsController>();
      final gender = settings.ttsGender;
      final engineType = settings.ttsEngineType;
      await speechEngine.synthesizeSpeech(text, _selectedTtsLang, gender, engineType);
      setState(() {
        _isSynthesizing = false;
        _ttsStatusMessage = 'Audio playing ($gender, $engineType): "${text.length > 60 ? '${text.substring(0, 60)}...' : text}"';
      });
      _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] TTS [$_selectedTtsLang]: $text');
    } catch (e) {
      setState(() {
        _isSynthesizing = false;
        _ttsStatusMessage = 'TTS Error: $e';
      });
      _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] TTS ERROR: $e');
    }
  }

  void _stopTtsPlayback(BuildContext context) {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    speechEngine.stopSpeech();
    setState(() {
      _isSynthesizing = false;
      _isTest3Synthesizing = false;
      _ttsStatusMessage = 'Audio playback stopped';
      if (_isTest3Recording || _isTest3Synthesizing) {
        _test3Stage = 'Playback stopped.';
      }
    });
  }

  // ==========================================================
  // SECTION 3: STT ➔ TTS Direct Voice Test Methods (No MT)
  // ==========================================================
  Future<void> _startTest3Record() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settings = context.read<SettingsController>();

    if (!_isSttModelLoaded) {
      await _toggleSttModel(true);
    }
    if (!_isTtsModelLoaded) {
      await _toggleTtsModel(true);
    }
    if (!mounted) return;

    setState(() {
      _isTest3Recording = true;
      _isTest3Synthesizing = false;
      _test3Stage = 'Stage 1: 🎙️ Listening in [$_selectedTest3Lang]... Speak into microphone!';
      _test3RecognizedText = '';
      _totalSamplesCaptured = 0;
      _currentAmplitude = 0.0;
    });

    _vad.setSensitivity(settings.vadSensitivity);

    try {
      final sttStream = speechEngine.startListening(_selectedTest3Lang);
      _sttTextSub?.cancel();
      _sttTextSub = sttStream.listen((text) {
        if (mounted && text.trim().isNotEmpty) {
          setState(() => _test3RecognizedText = text);
        }
      });

      final stream = await _recorder.startRecording();
      _audioSub?.cancel();
      _audioSub = stream.listen((chunk) {
        _totalSamplesCaptured += chunk.length;
        speechEngine.feedAudioData(chunk);

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastAmpUpdateMs > 90) {
          _lastAmpUpdateMs = nowMs;
          double sum = 0;
          for (int i = 0; i < chunk.length; i += 4) {
            final norm = chunk[i] / 32768.0;
            sum += norm * norm;
          }
          final rms = sqrt(sum / (chunk.length / 4));
          if (mounted) {
            setState(() => _currentAmplitude = (rms * 8.0).clamp(0.0, 1.0));
          }
        }
      });

      _vadSub?.cancel();
      _vadSub = _vad.startVad(stream).listen((isSpeech) {
        if (mounted && _isVoiceDetected != isSpeech) {
          setState(() => _isVoiceDetected = isSpeech);
        }
      });
    } catch (e) {
      setState(() {
        _isTest3Recording = false;
        _test3Stage = 'Error starting Test 3 recording: $e';
      });
    }
  }

  Future<void> _stopTest3AndSpeak() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settings = context.read<SettingsController>();

    await _audioSub?.cancel();
    _audioSub = null;
    await _vadSub?.cancel();
    _vadSub = null;
    await _recorder.stopRecording();
    _vad.stopVad();

    setState(() {
      _isTest3Recording = false;
      _currentAmplitude = 0.0;
      _isVoiceDetected = false;
      _test3Stage = 'Stage 2: 🧠 Decoding speech with IndicConformer...';
    });

    final transcript = await speechEngine.stopListeningAndTranscribe(_selectedTest3Lang);
    await _sttTextSub?.cancel();
    _sttTextSub = null;

    final recognized = transcript.trim().isNotEmpty
        ? transcript.trim()
        : (_test3RecognizedText.trim().isNotEmpty
            ? _test3RecognizedText.trim()
            : (_presets[_selectedTest3Lang] ?? 'आपातकालीन सहायता'));

    setState(() {
      _test3RecognizedText = recognized;
      _isTest3Synthesizing = true;
      _test3Stage = 'Stage 3: 🔊 Synthesizing & speaking directly in [$_selectedTest3Lang] (MT Bypassed)...';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->TTS Recognized: "$recognized"');

    try {
      final gender = settings.ttsGender;
      final engineType = settings.ttsEngineType;
      await speechEngine.synthesizeSpeech(recognized, _selectedTest3Lang, gender, engineType);
      if (mounted) {
        setState(() {
          _isTest3Synthesizing = false;
          _test3Stage = 'Stage 4: ✅ Direct Playback Complete! Spoke in [$_selectedTest3Lang] ($gender, $engineType).';
        });
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->TTS Complete: Spoke in $_selectedTest3Lang');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTest3Synthesizing = false;
          _test3Stage = 'TTS Error during playback: $e';
        });
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->TTS Error: $e');
      }
    }
  }

  Future<void> _runMockTest3(String sampleText) async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settings = context.read<SettingsController>();

    setState(() {
      _test3RecognizedText = sampleText;
      _isTest3Synthesizing = true;
      _test3Stage = 'Simulated STT: "$sampleText" -> Synthesizing directly in [$_selectedTest3Lang]...';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Mock STT->TTS: "$sampleText"');

    try {
      final gender = settings.ttsGender;
      final engineType = settings.ttsEngineType;
      await speechEngine.synthesizeSpeech(sampleText, _selectedTest3Lang, gender, engineType);
      if (mounted) {
        setState(() {
          _isTest3Synthesizing = false;
          _test3Stage = '✅ Complete! Spoke directly in [$_selectedTest3Lang] ($gender, $engineType).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTest3Synthesizing = false;
          _test3Stage = 'Mock TTS Error: $e';
        });
      }
    }
  }

  // ==========================================================
  // SECTION 4: STT ➔ MT ➔ TTS Dynamic JIT Pipeline Methods
  // ==========================================================
  Future<void> _startTest4JitPipeline() async {
    final transceiverCtrl = context.read<TransceiverController>();
    final speechEngine = transceiverCtrl.speechEngine;
    final settings = context.read<SettingsController>();

    if (!_isSttModelLoaded) await _toggleSttModel(true);
    if (!_isTtsModelLoaded) await _toggleTtsModel(true);
    if (!_isMtModelLoaded) _toggleMtModel(true);
    if (!mounted) return;

    setState(() {
      _isTest4Recording = true;
      _test4Stage = '⚡ JIT Pipeline Active: Listening in [$_selectedTest4SourceLang]... Segments stream to MT & TTS Just-In-Time!';
      _jitChunks.clear();
      _jitChunkCounter = 0;
      _lastDispatchedJitText = '';
      _totalSamplesCaptured = 0;
      _currentAmplitude = 0.0;
    });

    _vad.setSensitivity(settings.vadSensitivity);

    try {
      final sttStream = speechEngine.startListening(_selectedTest4SourceLang);
      _sttTextSub?.cancel();
      _sttTextSub = sttStream.listen((text) {
        _handleIncomingSttJitText(text);
      });

      final stream = await _recorder.startRecording();
      _audioSub?.cancel();
      _audioSub = stream.listen((chunk) {
        _totalSamplesCaptured += chunk.length;
        speechEngine.feedAudioData(chunk);

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastAmpUpdateMs > 90) {
          _lastAmpUpdateMs = nowMs;
          double sum = 0;
          for (int i = 0; i < chunk.length; i += 4) {
            final norm = chunk[i] / 32768.0;
            sum += norm * norm;
          }
          final rms = sqrt(sum / (chunk.length / 4));
          if (mounted) {
            setState(() => _currentAmplitude = (rms * 8.0).clamp(0.0, 1.0));
          }
        }
      });

      _vadSub?.cancel();
      _vadSub = _vad.startVad(stream).listen((isSpeech) {
        if (mounted && _isVoiceDetected != isSpeech) {
          setState(() => _isVoiceDetected = isSpeech);
        }
      });
    } catch (e) {
      setState(() {
        _isTest4Recording = false;
        _test4Stage = 'Error starting Test 4 JIT Pipeline: $e';
      });
    }
  }

  void _handleIncomingSttJitText(String fullText) {
    final trimmed = fullText.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.length > _lastDispatchedJitText.length) {
      final delta = trimmed.substring(_lastDispatchedJitText.length).trim();
      final words = delta.split(' ');
      if (words.length >= 2 || delta.endsWith('.') || delta.endsWith('?') || delta.endsWith(',')) {
        _lastDispatchedJitText = trimmed;
        _dispatchJitChunk(delta);
      }
    }
  }

  Future<void> _dispatchJitChunk(String chunkText) async {
    if (chunkText.trim().isEmpty) return;
    _jitChunkCounter++;
    final chunk = JitChunk(
      id: _jitChunkCounter,
      originalText: chunkText,
      startTime: DateTime.now(),
      status: 'TRANSLATING (MT)',
    );

    setState(() {
      _jitChunks.insert(0, chunk);
      _test4Stage = '⚡ JIT Chunk #${chunk.id} dispatched to IndicTrans MT...';
    });

    final transceiverCtrl = context.read<TransceiverController>();
    final speechEngine = transceiverCtrl.speechEngine;
    final settings = context.read<SettingsController>();

    final mtStart = DateTime.now();
    String translated = chunkText;
    if (_selectedTest4SourceLang != _selectedTest4TargetLang) {
      try {
        translated = await transceiverCtrl.transEngine.translate(
          text: chunkText,
          sourceLang: _selectedTest4SourceLang,
          targetLang: _selectedTest4TargetLang,
        );
      } catch (e) {
        translated = chunkText;
      }
    }
    chunk.mtDurationMs = DateTime.now().difference(mtStart).inMilliseconds;
    chunk.translatedText = translated;
    chunk.status = 'SYNTHESIZING (TTS)';
    if (mounted) setState(() {});

    final ttsStart = DateTime.now();
    try {
      final gender = settings.ttsGender;
      final engineType = settings.ttsEngineType;
      await speechEngine.synthesizeSpeech(translated, _selectedTest4TargetLang, gender, engineType);
      chunk.ttsDurationMs = DateTime.now().difference(ttsStart).inMilliseconds;
      chunk.status = 'COMPLETED';
      if (mounted) {
        setState(() {
          _test4Stage = '⚡ JIT Chunk #${chunk.id} played in [$_selectedTest4TargetLang] (MT: ${chunk.mtDurationMs}ms | TTS: ${chunk.ttsDurationMs}ms)!';
        });
      }
      _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] JIT Chunk #${chunk.id}: "$chunkText" ➔ "$translated" (${chunk.mtDurationMs}ms+${chunk.ttsDurationMs}ms)');
    } catch (e) {
      chunk.status = 'ERROR: $e';
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopTest4JitPipeline() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;

    _jitStreamCheckTimer?.cancel();
    _jitStreamCheckTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _vadSub?.cancel();
    _vadSub = null;
    await _recorder.stopRecording();
    _vad.stopVad();

    setState(() {
      _isTest4Recording = false;
      _currentAmplitude = 0.0;
      _isVoiceDetected = false;
      _test4Stage = '⚡ JIT: Finalizing remaining speech buffer...';
    });

    final finalTranscript = await speechEngine.stopListeningAndTranscribe(_selectedTest4SourceLang);
    await _sttTextSub?.cancel();
    _sttTextSub = null;

    if (finalTranscript.length > _lastDispatchedJitText.length) {
      final remaining = finalTranscript.substring(_lastDispatchedJitText.length).trim();
      if (remaining.isNotEmpty) {
        await _dispatchJitChunk(remaining);
      }
    } else if (_jitChunks.isEmpty && finalTranscript.trim().isNotEmpty) {
      await _dispatchJitChunk(finalTranscript.trim());
    }

    setState(() {
      _test4Stage = '✅ Dynamic JIT Pipeline Finished! Processed ${_jitChunks.length} chunks in real-time.';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Test 4 JIT: ${_jitChunks.length} chunks processed in total.');
  }

  Future<void> _runMockJitStreamTest() async {
    final phrases = [
      'नमस्ते, नियंत्रण कक्ष से संपर्क करें।',
      'आपातकालीन सहायता दल रवाना हो चुका है।',
      'सभी इकाइयाँ अपने स्थान पर सुरक्षित रहें।',
    ];

    setState(() {
      _jitChunks.clear();
      _jitChunkCounter = 0;
      _test4Stage = '⚡ Simulating Dynamic JIT Stream across 3 incoming speech clauses...';
    });

    for (final phrase in phrases) {
      await _dispatchJitChunk(phrase);
      await Future.delayed(const Duration(milliseconds: 400));
    }

    setState(() {
      _test4Stage = '✅ Mock Dynamic JIT Pipeline Complete! Processed ${_jitChunks.length} clauses Just-In-Time.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsController = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer & Audio Diagnostics'),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.build_rounded, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'DEV MODE',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==========================================
            // SECTION 1: STT (Speech-to-Text) TEST CARD
            // ==========================================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _isRecording ? Colors.red : theme.colorScheme.outlineVariant,
                  width: _isRecording ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.mic_none_rounded,
                                color: _isRecording ? Colors.red : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '1. STT Diagnostic Test',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // STT Model Power / Offload Toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isSttModelLoaded
                                    ? Colors.green.withAlpha(35)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isSttModelLoaded ? Colors.green : theme.colorScheme.outline,
                                ),
                              ),
                              child: Text(
                                _isSttModelLoaded ? 'STT LOADED' : 'OFFLOADED',
                                style: TextStyle(
                                  color: _isSttModelLoaded ? Colors.green : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _isSttModelLoaded,
                              activeThumbColor: Colors.green,
                              onChanged: (val) => _toggleSttModel(val),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tests microphone capture on Windows, real-time PCM audio streaming (16kHz 16-bit mono), Silero VAD energy gating, and text formation.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Engine: $_sttInitStatus (Dynamic Real-Time Detection: Active)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _sttInitialized ? const Color(0xFF00E676) : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // STT Language & Mode Selector
                    Row(
                      children: [
                        const Text('Language:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('हिन्दी (Hindi)', style: TextStyle(fontSize: 11)),
                          selected: _selectedSttLang == 'hi',
                          onSelected: (val) {
                            if (val) setState(() => _selectedSttLang = 'hi');
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('English (Latin)', style: TextStyle(fontSize: 11)),
                          selected: _selectedSttLang == 'en',
                          onSelected: (val) {
                            if (val) setState(() => _selectedSttLang = 'en');
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('मराठी (Marathi)', style: TextStyle(fontSize: 11)),
                          selected: _selectedSttLang == 'mr',
                          onSelected: (val) {
                            if (val) setState(() => _selectedSttLang = 'mr');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Audio Level Meter (VU Meter)
                    Row(
                      children: [
                        Text(
                          'Mic Input Level:',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _currentAmplitude,
                              minHeight: 12,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              color: _currentAmplitude > 0.6
                                  ? Colors.red
                                  : (_currentAmplitude > 0.2 ? Colors.green : Colors.blue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(_currentAmplitude * 100).toInt()}%',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // VAD Sensitivity Slider
                    Row(
                      children: [
                        const Text('VAD Sensitivity:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: settingsController.vadSensitivity,
                            min: 0.1,
                            max: 1.0,
                            divisions: 9,
                            label: '${(settingsController.vadSensitivity * 100).toInt()}%',
                            onChanged: (val) {
                              settingsController.updateVadSensitivity(val);
                              _vad.setSensitivity(val);
                            },
                          ),
                        ),
                        Text(
                          '${(settingsController.vadSensitivity * 100).toInt()}%',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // VAD Status & Sample Counters
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isVoiceDetected
                                ? Colors.green.withAlpha(40)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isVoiceDetected ? Colors.green : theme.colorScheme.outline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isVoiceDetected ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded,
                                size: 14,
                                color: _isVoiceDetected ? Colors.green : theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isVoiceDetected ? 'VAD: VOICE DETECTED' : 'VAD: SILENCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isVoiceDetected ? Colors.green : theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Samples: $_totalSamplesCaptured | 16 kHz',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Formed Text Output Area
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Transcribed Text Formation (${_selectedSttLang.toUpperCase()}):',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_isRecording)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red, width: 0.8),
                                  ),
                                  child: const Text(
                                    '● LIVE DYNAMIC STREAMING',
                                    style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formedSttText.isEmpty ? 'No audio captured yet.' : _formedSttText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: _formedSttText.startsWith('Error')
                                  ? Colors.red
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Record Controls & Quick Loopback Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isRecording ? _stopSttRecordTest : _startSttRecordTest,
                            icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
                            label: Text(_isRecording ? 'STOP & TRANSCRIBE' : 'START RECORD TEST'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecording ? Colors.red : theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (_formedSttText.isNotEmpty && !_formedSttText.startsWith('Listening') && !_formedSttText.startsWith('Captured')) {
                              _ttsTextController.text = _formedSttText;
                              _runTtsSpeechTest(context);
                            } else {
                              setState(() {
                                _formedSttText = 'Injected test utterance: "Emergency alert from ground station."';
                                _transcriptLog.insert(0, '[MOCK TEST] Injected test utterance');
                              });
                            }
                          },
                          icon: const Icon(Icons.volume_up_rounded, size: 16),
                          label: Text(
                            _formedSttText.isNotEmpty && !_formedSttText.startsWith('Listening') && !_formedSttText.startsWith('Captured')
                                ? 'Send to TTS ▶'
                                : 'Inject Frame',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==========================================
            // SECTION 2: TTS (Text-to-Speech) TEST CARD
            // ==========================================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.volume_up_rounded, color: theme.colorScheme.secondary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '2. TTS Diagnostic Test',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // TTS Model Power / Offload Toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isTtsModelLoaded
                                    ? Colors.green.withAlpha(35)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isTtsModelLoaded ? Colors.green : theme.colorScheme.outline,
                                ),
                              ),
                              child: Text(
                                _isTtsModelLoaded ? 'VITS LOADED' : 'OFFLOADED',
                                style: TextStyle(
                                  color: _isTtsModelLoaded ? Colors.green : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _isTtsModelLoaded,
                              activeThumbColor: Colors.green,
                              onChanged: (val) => _toggleTtsModel(val),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tests neural speech synthesis across all 10 SIH Indian languages with audio waveform playback on Windows speakers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // Active TTS Model Selector
                    Row(
                      children: [
                        Text('TTS Engine:', style: theme.textTheme.labelMedium),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.hub_rounded, size: 14),
                          label: const Text('AI4Bharat Rasa-13', style: TextStyle(fontSize: 11)),
                          selected: settingsController.ttsEngineType == 'AI4BHARAT_RASA',
                          onSelected: (selected) async {
                            if (selected) {
                              await settingsController.updateTtsEngineType('AI4BHARAT_RASA');
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: const Icon(Icons.language_rounded, size: 14),
                          label: const Text('Meta MMS', style: TextStyle(fontSize: 11)),
                          selected: settingsController.ttsEngineType == 'META_MMS',
                          onSelected: (selected) async {
                            if (selected) {
                              await settingsController.updateTtsEngineType('META_MMS');
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: const Icon(Icons.volume_up_rounded, size: 14),
                          label: const Text('OS Native', style: TextStyle(fontSize: 11)),
                          selected: settingsController.ttsEngineType == 'OS_NATIVE',
                          onSelected: (selected) async {
                            if (selected) {
                              await settingsController.updateTtsEngineType('OS_NATIVE');
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Language & Gender Selectors
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('diag_tts_$_selectedTtsLang'),
                            initialValue: _selectedTtsLang,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Language',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: LanguagePackManager.supportedLanguages.map((lang) {
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Text(
                                  '${lang.nativeName} (${lang.englishName})',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedTtsLang = val;
                                  _ttsTextController.text = _presets[val] ?? '';
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: settingsController.ttsGender,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Voice',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'FEMALE', child: Text('👩 Female')),
                              DropdownMenuItem(value: 'MALE', child: Text('👨 Male')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                settingsController.updateTtsGender(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (settingsController.ttsEngineType == 'AI4BHARAT_RASA' &&
                        const {'gu', 'or', 'en'}.contains(_selectedTtsLang))
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade700, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rasa-13 lacks ${_selectedTtsLang.toUpperCase()} (Gujarati / Odia / English). The engine will automatically route synthesis to Meta MMS / OS Native fallback.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Quick Preset Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.emergency_rounded, size: 14, color: Colors.red),
                          label: const Text('Emergency Preset', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() {
                              _ttsTextController.text = _presets[_selectedTtsLang] ?? 'Emergency alert!';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.numbers_rounded, size: 14),
                          label: const Text('Coordinates Preset', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() {
                              _ttsTextController.text =
                                  'Sector 4. Latitude 28.6139, Longitude 77.2090. All units stand by.';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Text Input Area
                    TextField(
                      controller: _ttsTextController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Text to Synthesize',
                        border: OutlineInputBorder(),
                        hintText: 'Type words in English or Indian native script...',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Status Message
                    Text(
                      _ttsStatusMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // TTS Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSynthesizing ? null : () => _runTtsSpeechTest(context),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('SYNTHESIZE & SPEAK'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _stopTtsPlayback(context),
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('STOP AUDIO'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==========================================
            // SECTION 3: STT -> TTS DIRECT VOICE TEST CARD
            // ==========================================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _isTest3Recording || _isTest3Synthesizing
                      ? Colors.indigo.shade700
                      : theme.colorScheme.outlineVariant,
                  width: _isTest3Recording || _isTest3Synthesizing ? 1.5 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.record_voice_over_rounded,
                                color: _isTest3Recording || _isTest3Synthesizing
                                    ? Colors.indigo.shade700
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '3. STT ➔ TTS Direct Voice Test',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Test 3 Power Toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isTest3Active
                                    ? Colors.indigo.withAlpha(35)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isTest3Active ? Colors.indigo : theme.colorScheme.outline,
                                ),
                              ),
                              child: Text(
                                _isTest3Active ? 'ACTIVE' : 'OFFLOADED',
                                style: TextStyle(
                                  color: _isTest3Active ? Colors.indigo : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _isTest3Active,
                              activeThumbColor: Colors.indigo,
                              onChanged: (val) {
                                setState(() => _isTest3Active = val);
                                if (!val) {
                                  _toggleSttModel(false);
                                  _toggleTtsModel(false);
                                } else {
                                  _toggleSttModel(true);
                                  _toggleTtsModel(true);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Direct voice loopback test: Voice ➔ IndicConformer STT ➔ Neural TTS. Bypasses Machine Translation entirely for zero-latency direct repeat in the same language.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Language & Voice Selector Row for Test 3
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedTest3Lang,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Language (Speak & Playback)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: LanguagePackManager.supportedLanguages.map((lang) {
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Text(
                                  '${lang.englishName} (${lang.nativeName})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                            onChanged: _isTest3Active
                                ? (val) {
                                    if (val != null) setState(() => _selectedTest3Lang = val);
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: settingsController.ttsGender,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Voice',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'FEMALE', child: Text('👩 Female', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'MALE', child: Text('👨 Male', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: _isTest3Active
                                ? (val) {
                                    if (val != null) {
                                      settingsController.updateTtsGender(val);
                                      setState(() {});
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Mic Level Meter for Test 3
                    if (_isTest3Recording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Text('Mic Level:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: _currentAmplitude,
                                backgroundColor: Colors.grey.withAlpha(50),
                                valueColor: const AlwaysStoppedAnimation(Colors.indigo),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isVoiceDetected ? 'SPEECH' : 'SILENCE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isVoiceDetected ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Test 3 Results Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isTest3Recording || _isTest3Synthesizing
                              ? Colors.indigo.shade700
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🎙️ Recognized Speech (${_selectedTest3Lang.toUpperCase()}):',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.indigo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_isTest3Recording)
                                const Text(
                                  '● LISTENING',
                                  style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              if (_isTest3Synthesizing)
                                const Text(
                                  '● PLAYING VOICE',
                                  style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _test3RecognizedText.isEmpty
                                ? 'Press "RECORD & SPEAK DIRECTLY" and speak into microphone...'
                                : _test3RecognizedText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Text(
                            _test3Stage,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: _test3Stage.startsWith('Error')
                                  ? Colors.red
                                  : _test3Stage.contains('Complete')
                                      ? Colors.green
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Test 3 Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !_isTest3Active || _isTest3Synthesizing
                                ? null
                                : _isTest3Recording
                                    ? _stopTest3AndSpeak
                                    : _startTest3Record,
                            icon: Icon(
                              _isTest3Recording ? Icons.stop_rounded : Icons.record_voice_over_rounded,
                            ),
                            label: Text(
                              _isTest3Recording ? 'STOP & SPEAK (STT➔TTS)' : 'RECORD & DIRECT SPEAK',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isTest3Recording ? Colors.red : Colors.indigo.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: !_isTest3Active || _isTest3Recording || _isTest3Synthesizing
                              ? null
                              : () {
                                  final sample = _presets[_selectedTest3Lang] ?? 'आपातकालीन सहायता संकेत सक्रिय है।';
                                  _runMockTest3(sample);
                                },
                          child: const Text('Simulate Direct'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==========================================
            // SECTION 4: STT -> MT -> TTS DYNAMIC JIT PIPELINE CARD
            // ==========================================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _isTest4Recording || _jitChunks.any((c) => c.status != 'COMPLETED')
                      ? Colors.teal.shade700
                      : theme.colorScheme.outlineVariant,
                  width: _isTest4Recording ? 1.5 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                color: _isTest4Recording ? Colors.red : Colors.teal.shade700,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '4. STT ➔ MT ➔ TTS Dynamic JIT Pipeline',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Test 4 Full-Stack Power Toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isTest4Active
                                    ? Colors.teal.withAlpha(35)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isTest4Active ? Colors.teal : theme.colorScheme.outline,
                                ),
                              ),
                              child: Text(
                                _isTest4Active ? 'JIT ACTIVE' : 'OFFLOADED',
                                style: TextStyle(
                                  color: _isTest4Active ? Colors.teal : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _isTest4Active,
                              activeThumbColor: Colors.teal,
                              onChanged: (val) {
                                setState(() => _isTest4Active = val);
                                if (!val) {
                                  _toggleSttModel(false);
                                  _toggleMtModel(false);
                                  _toggleTtsModel(false);
                                } else {
                                  _toggleSttModel(true);
                                  _toggleMtModel(true);
                                  _toggleTtsModel(true);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Just-In-Time (JIT) dynamic streaming pipeline: As speech is spoken into the microphone, detected clauses stream to MT and TTS concurrently in real-time, synthesizing playback without waiting for complete recording.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Visual JIT Pipeline Flow Diagram
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPipelineNode(
                            icon: Icons.mic_rounded,
                            label: '1. Voice',
                            isActive: _isTest4Recording,
                            isDone: !_isTest4Recording && _jitChunks.isNotEmpty,
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.graphic_eq_rounded,
                            label: '2. [JIT] STT',
                            isActive: _isTest4Recording,
                            isDone: _jitChunks.isNotEmpty,
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.translate_rounded,
                            label: '3. [JIT] MT',
                            isActive: _jitChunks.any((c) => c.status.contains('TRANSLAT')),
                            isDone: _jitChunks.any((c) => c.status == 'COMPLETED'),
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.volume_up_rounded,
                            label: '4. [JIT] TTS',
                            isActive: _jitChunks.any((c) => c.status.contains('SYNTHESIZ')),
                            isDone: _jitChunks.any((c) => c.status == 'COMPLETED'),
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.hearing_rounded,
                            label: '5. Audio Out',
                            isActive: _jitChunks.any((c) => c.status == 'COMPLETED'),
                            isDone: _test4Stage.contains('Finished') || _test4Stage.contains('Complete'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Source & Target Language Selector Row for Test 4
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedTest4SourceLang,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Source (Speak)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: LanguagePackManager.supportedLanguages.map((lang) {
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Text(
                                  '${lang.englishName} (${lang.code})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                            onChanged: _isTest4Active
                                ? (val) {
                                    if (val != null) setState(() => _selectedTest4SourceLang = val);
                                  }
                                : null,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.teal, size: 18),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedTest4TargetLang,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Target (Translate)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: LanguagePackManager.supportedLanguages.map((lang) {
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Text(
                                  '${lang.englishName} (${lang.code})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                            onChanged: _isTest4Active
                                ? (val) {
                                    if (val != null) setState(() => _selectedTest4TargetLang = val);
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: settingsController.ttsGender,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Voice',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'FEMALE', child: Text('👩 Female', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'MALE', child: Text('👨 Male', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: _isTest4Active
                                ? (val) {
                                    if (val != null) {
                                      settingsController.updateTtsGender(val);
                                      setState(() {});
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Test 4 Mic Meter
                    if (_isTest4Recording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Text('JIT Mic Input:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: _currentAmplitude,
                                backgroundColor: Colors.grey.withAlpha(50),
                                valueColor: const AlwaysStoppedAnimation(Colors.teal),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isVoiceDetected ? 'STREAMING' : 'LISTENING',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isVoiceDetected ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Real-time JIT Streaming Chunk Monitor
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 110, maxHeight: 220),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isTest4Recording ? Colors.teal.shade700 : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '⚡ Real-Time JIT Streaming Chunks (${_jitChunks.length}):',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _isTest4Recording ? '● JIT COMPILING' : 'READY',
                                style: TextStyle(
                                  color: _isTest4Recording ? Colors.green : theme.colorScheme.outline,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _jitChunks.isEmpty
                                ? Center(
                                    child: Text(
                                      'No speech chunks streamed yet. Press "START DYNAMIC JIT PIPELINE" to speak or "Simulate JIT Stream".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _jitChunks.length,
                                    itemBuilder: (context, index) {
                                      final c = _jitChunks[index];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: c.status == 'COMPLETED'
                                              ? Colors.teal.withAlpha(20)
                                              : Colors.amber.withAlpha(25),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: c.status == 'COMPLETED' ? Colors.teal.shade300 : Colors.amber,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Chunk #${c.id} [${c.status}]',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: c.status == 'COMPLETED' ? Colors.teal : Colors.amber.shade900,
                                                  ),
                                                ),
                                                if (c.mtDurationMs != null)
                                                  Text(
                                                    'MT: ${c.mtDurationMs}ms ${c.ttsDurationMs != null ? '| TTS: ${c.ttsDurationMs}ms' : ''}',
                                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '🎙️ "${c.originalText}"',
                                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                            ),
                                            if (c.translatedText.isNotEmpty)
                                              Text(
                                                '➔ 🌐 "${c.translatedText}"',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.teal,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _test4Stage,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: _test4Stage.contains('Error')
                                  ? Colors.red
                                  : _test4Stage.contains('Finished') || _test4Stage.contains('Complete')
                                      ? Colors.green
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Test 4 Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !_isTest4Active
                                ? null
                                : _isTest4Recording
                                    ? _stopTest4JitPipeline
                                    : _startTest4JitPipeline,
                            icon: Icon(_isTest4Recording ? Icons.stop_rounded : Icons.bolt_rounded),
                            label: Text(
                              _isTest4Recording ? 'STOP JIT STREAM' : 'START DYNAMIC JIT PIPELINE',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isTest4Recording ? Colors.red : Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: !_isTest4Active || _isTest4Recording
                              ? null
                              : _runMockJitStreamTest,
                          child: const Text('Simulate JIT Stream'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==========================================
            // SECTION 3: RECENT DIAGNOSTIC LOGS
            // ==========================================
            Text(
              'Diagnostic Activity Log',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              height: 140,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: _transcriptLog.isEmpty
                  ? const Center(
                      child: Text(
                        'No diagnostic events logged yet. Run a record or TTS test above.',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _transcriptLog.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _transcriptLog[index],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineNode({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isDone,
  }) {
    final color = isActive
        ? Colors.amber.shade700
        : isDone
            ? Colors.green
            : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(isActive ? 40 : (isDone ? 30 : 20)),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isActive ? 2 : 1),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
