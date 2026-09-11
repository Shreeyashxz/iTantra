import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../speech/audio_recorder_service.dart';
import '../../speech/indic_trans_engine.dart';
import '../../speech/language_pack_manager.dart';
import '../../speech/sherpa_onnx_speech_engine.dart';
import '../../speech/silero_vad_engine.dart';
import '../theme/app_theme.dart';

class ModelTestLabScreen extends StatefulWidget {
  const ModelTestLabScreen({super.key});

  @override
  State<ModelTestLabScreen> createState() => _ModelTestLabScreenState();
}

class _ModelTestLabScreenState extends State<ModelTestLabScreen> {
  // --- Core Services ---
  late final AudioRecorderService _recorder;
  late final SileroVadEngine _vad;

  StreamSubscription<Int16List>? _audioSub;
  StreamSubscription<bool>? _vadSub;
  StreamSubscription<String>? _sttSub;

  // --- Live Recording State ---
  int? _activeRecordingTest; // 1, 3, 4, or 6
  bool _isVoiceDetected = false;
  double _currentAmplitude = 0.0;
  int _lastAmpUpdateMs = 0;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  int _totalSamplesCaptured = 0;

  // --- Model Engine In-Memory Statuses ---
  bool _isSttLoaded = false;
  bool _isSttLoading = false;
  bool _isMtLoaded = true;
  String _activeTtsKey = '';

  // --- Installed Model Check Status ---
  late final LanguagePackManager _lpm;
  Map<String, bool> _installedModels = {};
  bool _isScanningFiles = false;

  // --- Preset Phrases for All 10 Supported Languages ---
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
    'bn': 'নমস্কার, জরুরী অবস্থায় আই-তন্ত্র न्यूरल ट्रान्सीভার প্রস্তুত।',
  };

  // --- Expanded Card States ---
  final Map<int, bool> _expanded = {
    1: true,
    2: false,
    3: false,
    4: false,
    5: false,
    6: false,
    7: false,
  };

  // --- Test 1: STT State ---
  bool _t1Active = true;
  String _t1Lang = 'hi';
  String _t1Transcript = '';
  int _t1LatencyMs = 0;

  // --- Test 2: TTS State (Default Meta MMS + English) ---
  bool _t2Active = true;
  String _t2Lang = 'en';
  String _t2Engine = 'META_MMS';
  String _t2Gender = 'FEMALE';
  final TextEditingController _t2Controller = TextEditingController(
    text: 'Emergency priority message. Coordinates confirmed. Transceiver link active.',
  );
  bool _t2IsRunning = false;
  String _t2Status = 'Idle (Ready to synthesize)';
  int _t2LatencyMs = 0;

  // --- Test 3: STT -> TTS Direct Voice (Default Meta MMS + English) ---
  bool _t3Active = true;
  String _t3Lang = 'en';
  String _t3Engine = 'META_MMS';
  String _t3Gender = 'FEMALE';
  final TextEditingController _t3Controller = TextEditingController(
    text: 'Emergency priority alert. Voice transceiver link healthy.',
  );
  String _t3RecognizedText = '';
  bool _t3IsSynthesizing = false;
  String _t3Status = 'Idle (Ready for mic loop)';
  int _t3SttMs = 0;
  int _t3TtsMs = 0;
  int _t3TotalMs = 0;

  // --- Test 4: STT -> MT -> TTS Full Voice Pipeline (Default Meta MMS + en target) ---
  bool _t4Active = true;
  String _t4SourceLang = 'hi';
  String _t4TargetLang = 'en';
  String _t4Engine = 'META_MMS';
  String _t4Gender = 'FEMALE';
  String _t4SourceText = '';
  String _t4TranslatedText = '';
  bool _t4IsSynthesizing = false;
  String _t4Status = 'Idle (Ready for voice pipeline)';
  int _t4SttMs = 0;
  int _t4MtMs = 0;
  int _t4TtsMs = 0;
  int _t4TotalMs = 0;

  // --- Test 5: Text -> MT -> TTS (NEW - Default Meta MMS + en target) ---
  bool _t5Active = true;
  String _t5SourceLang = 'hi';
  String _t5TargetLang = 'en';
  String _t5Engine = 'META_MMS';
  String _t5Gender = 'FEMALE';
  final TextEditingController _t5Controller = TextEditingController(
    text: 'नमस्ते, आई-तंत्र आपातकालीन न्यूरल ट्रांससीवर में आपका स्वागत है।',
  );
  String _t5TranslatedText = '';
  bool _t5IsRunning = false;
  String _t5Status = 'Idle (Ready to translate & speak)';
  int _t5MtMs = 0;
  int _t5TtsMs = 0;
  int _t5TotalMs = 0;

  // --- Test 6: STT -> MT -> Text (NEW) ---
  bool _t6Active = true;
  String _t6SourceLang = 'hi';
  String _t6TargetLang = 'en';
  String _t6SourceText = '';
  String _t6TranslatedText = '';
  bool _t6IsTranslating = false;
  String _t6Status = 'Idle (Ready for voice-to-text translation)';
  int _t6SttMs = 0;
  int _t6MtMs = 0;
  int _t6TotalMs = 0;

  // --- Test 7: Text -> MT -> Text (NEW) ---
  bool _t7Active = true;
  String _t7SourceLang = 'en';
  String _t7TargetLang = 'hi';
  final TextEditingController _t7Controller = TextEditingController(
    text: 'Emergency priority message. Coordinates confirmed. Transceiver link active.',
  );
  String _t7TranslatedText = '';
  bool _t7IsTranslating = false;
  String _t7Status = 'Idle (Ready to translate)';
  int _t7MtMs = 0;

  // --- Consolidated Activity Log ---
  final List<String> _activityLogs = [];

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorderService();
    _vad = SileroVadEngine();
    _lpm = LanguagePackManager();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final commVad = context.read<TransceiverController>().commPipeline.vadEngine;
      if (commVad is SileroVadEngine) {
        _vad = commVad;
      }
      final currentEngine = context.read<SettingsController>().ttsEngineType;
      setState(() {
        _t2Engine = currentEngine;
        _t3Engine = currentEngine;
        _t4Engine = currentEngine;
        _t5Engine = currentEngine;
      });
      _scanInstalledModels();
      _ensureSttLoaded();
      _ensureTtsLoaded(_t2Lang, currentEngine);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioSub?.cancel();
    _vadSub?.cancel();
    _sttSub?.cancel();
    _recorder.dispose();
    _vad.stopVad();
    _t2Controller.dispose();
    _t3Controller.dispose();
    _t5Controller.dispose();
    _t7Controller.dispose();
    super.dispose();
  }

  void _log(String msg) {
    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _activityLogs.insert(0, '[$timeStr] $msg');
      if (_activityLogs.length > 80) _activityLogs.removeLast();
    });
  }

  // =========================================================================
  // MODEL ENGINE MANAGEMENT (ON-DEMAND LAZY LOADING & UNLOADING)
  // =========================================================================

  Future<void> _scanInstalledModels() async {
    if (!mounted) return;
    setState(() => _isScanningFiles = true);
    final results = <String, bool>{};
    results['vad'] = true;
    results['stt_int8'] = await _lpm.isSttAvailable();
    results['stt_fp32'] = await _lpm.isSttFp32Available();
    results['mt_int8'] = await _lpm.isMtAvailable();
    results['mt_fp16'] = await _lpm.isMtFp16Available();
    results['mt'] = (results['mt_int8'] ?? false) || (results['mt_fp16'] ?? false);
    results['tts_rasa13'] = await _lpm.isRasa13Available();
    results['lid'] = await _lpm.isLidAvailable();
    for (final lang in LanguagePackManager.supportedLanguages) {
      results['tts_mms_${lang.code}'] = await _lpm.isMmsAvailable(lang.code);
    }
    if (mounted) {
      setState(() {
        _installedModels = results;
        _isScanningFiles = false;
      });
    }
  }

  // --- STT ---
  Future<bool> _loadStt([String? precisionOverride]) async {
    final precision = precisionOverride ?? context.read<SettingsController>().sttPrecision;
    setState(() => _isSttLoading = true);
    final speech = context.read<TransceiverController>().speechEngine;
    final ok = await speech.initStt(precision);
    if (mounted) {
      setState(() {
        _isSttLoading = false;
        _isSttLoaded = ok;
      });
    }
    _log('STT Model ($precision) load: ${ok ? "READY" : "FAILED"}');
    return ok;
  }

  Future<bool> _ensureSttLoaded() async {
    if (_isSttLoaded) return true;
    return _loadStt();
  }

  void _unloadStt() {
    final speech = context.read<TransceiverController>().speechEngine;
    speech.unloadStt();
    setState(() => _isSttLoaded = false);
    _log('STT Model offloaded from RAM');
  }

  // --- TTS ---
  Future<bool> _loadTts(String lang, String engineType) async {
    final key = '${lang}_$engineType';
    final speech = context.read<TransceiverController>().speechEngine;
    final ok = await speech.initTts(lang, engineType);
    if (mounted) {
      setState(() {
        _activeTtsKey = ok ? key : '';
      });
    }
    _log('TTS Model ($engineType, $lang) load: ${ok ? "READY" : "FAILED"}');
    return ok;
  }

  Future<bool> _ensureTtsLoaded(String lang, String engineType) async {
    final key = '${lang}_$engineType';
    final speech = context.read<TransceiverController>().speechEngine;
    if (speech.isTtsKeyLoaded(key)) return true;
    return _loadTts(lang, engineType);
  }

  void _unloadTtsKey(String key) {
    final speech = context.read<TransceiverController>().speechEngine;
    speech.unloadTtsKey(key);
    setState(() {
      if (_activeTtsKey == key) {
        _activeTtsKey = speech.loadedTtsKeys.isNotEmpty ? speech.loadedTtsKeys.first : '';
      }
    });
    _log('TTS Model [$key] offloaded from RAM');
  }

  void _unloadAllTts() {
    final speech = context.read<TransceiverController>().speechEngine;
    speech.unloadTts();
    setState(() {
      _activeTtsKey = '';
    });
    _log('All TTS Models offloaded from RAM');
  }

  // --- MT ---
  void _loadMt([String? precision]) {
    final trans = context.read<TransceiverController>().transEngine;
    trans.load(precision);
    setState(() => _isMtLoaded = true);
    _log('MT Model (${precision ?? trans.loadedPrecision}) loaded into RAM');
  }

  void _ensureMtLoaded() {
    if (_isMtLoaded) return;
    _loadMt();
  }

  void _unloadMt() {
    final trans = context.read<TransceiverController>().transEngine;
    trans.unload();
    setState(() => _isMtLoaded = false);
    _log('MT Model offloaded from RAM');
  }

  // --- VAD ---
  Future<void> _loadVad() async {
    final ok = await _vad.initNeuralVad();
    setState(() {});
    _log('Silero Neural VAD: ${ok ? "LOADED" : "FAILED"}');
  }

  void _unloadVad() {
    _vad.unloadNeuralVad();
    setState(() {});
    _log('Silero Neural VAD offloaded from RAM (using adaptive RMS fallback)');
  }

  // --- Purge All Models ---
  void _unloadAllModels() {
    _unloadVad();
    _unloadStt();
    _unloadMt();
    _unloadAllTts();
    setState(() {});
    _log('PURGE ALL: All neural models have been unloaded from system RAM (0 MB active)');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All neural models purged from RAM (0 MB active)'),
        backgroundColor: Colors.teal,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // =========================================================================
  // AUDIO RECORDING & REAL-TIME STT STREAMING ENGINE
  // =========================================================================

  Future<void> _startAudioCapture({
    required int testId,
    required String langCode,
    required ValueChanged<String> onLiveTranscript,
  }) async {
    // If another test is already recording, stop it first
    if (_activeRecordingTest != null) {
      await _stopAudioCapture();
      if (!mounted) return;
    }

    final speech = context.read<TransceiverController>().speechEngine;
    final settings = context.read<SettingsController>();

    await _ensureSttLoaded();
    if (!mounted) return;

    setState(() {
      _activeRecordingTest = testId;
      _recordSeconds = 0;
      _totalSamplesCaptured = 0;
      _currentAmplitude = 0.0;
      _isVoiceDetected = false;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    try {
      _vad.setSensitivity(settings.vadSensitivity);

      // Subscribe to live token updates from STT
      final stream = speech.startListening(langCode);
      _sttSub?.cancel();
      _sttSub = stream.listen((text) {
        if (mounted && text.trim().isNotEmpty) {
          onLiveTranscript(text);
        }
      });

      final micStream = await _recorder.startRecording();
      _audioSub?.cancel();
      _audioSub = micStream.listen((chunk) {
        _totalSamplesCaptured += chunk.length;
        speech.feedAudioData(chunk);

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastAmpUpdateMs > 80) {
          _lastAmpUpdateMs = now;
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
      _vadSub = _vad.startVad(micStream).listen((isVoice) {
        if (mounted && _isVoiceDetected != isVoice) {
          setState(() => _isVoiceDetected = isVoice);
        }
      });
    } catch (e) {
      _log('Error starting audio capture for Test #$testId: $e');
      await _stopAudioCapture();
    }
  }

  Future<String> _stopAudioCapture() async {
    final speech = context.read<TransceiverController>().speechEngine;

    _recordTimer?.cancel();
    _recordTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _vadSub?.cancel();
    _vadSub = null;
    await _recorder.stopRecording();
    _vad.stopVad();

    final testId = _activeRecordingTest;
    String langCode = 'hi';
    if (testId == 1) langCode = _t1Lang;
    if (testId == 3) langCode = _t3Lang;
    if (testId == 4) langCode = _t4SourceLang;
    if (testId == 6) langCode = _t6SourceLang;

    final decodeStart = DateTime.now();
    final transcript = await speech.stopListeningAndTranscribe(langCode);
    final decodeDuration = DateTime.now().difference(decodeStart).inMilliseconds;

    await _sttSub?.cancel();
    _sttSub = null;

    if (mounted) {
      setState(() {
        _activeRecordingTest = null;
        _currentAmplitude = 0.0;
        _isVoiceDetected = false;
      });
    }

    final kb = (_totalSamplesCaptured * 2) / 1024.0;
    _log('Test #$testId audio captured: ${_recordSeconds}s (${kb.toStringAsFixed(1)} KB PCM), decoded in ${decodeDuration}ms: "$transcript"');
    return transcript;
  }

  // =========================================================================
  // INDIVIDUAL TEST EXECUTIONS (ALL 7 UNIQUE TESTS)
  // =========================================================================

  // --- Test 1: STT (Speech -> Text) ---
  Future<void> _toggleT1Recording() async {
    if (_activeRecordingTest == 1) {
      final start = DateTime.now();
      final text = await _stopAudioCapture();
      final ms = DateTime.now().difference(start).inMilliseconds;
      setState(() {
        _t1Transcript = text.isNotEmpty ? text : '(No words recognized — try speaking closer)';
        _t1LatencyMs = ms;
      });
      _log('Test 1 STT Result: "$_t1Transcript" (${ms}ms)');
    } else {
      setState(() {
        _t1Transcript = 'Listening... Speak into microphone in [${_t1Lang.toUpperCase()}]';
        _t1LatencyMs = 0;
      });
      await _startAudioCapture(
        testId: 1,
        langCode: _t1Lang,
        onLiveTranscript: (live) {
          setState(() => _t1Transcript = live);
        },
      );
    }
  }

  // --- Test 2: TTS (Text -> Speech) ---
  Future<void> _runT2Tts() async {
    final text = _t2Controller.text.trim();
    if (text.isEmpty) return;

    await _ensureTtsLoaded(_t2Lang, _t2Engine);
    if (!mounted) return;
    final speech = context.read<TransceiverController>().speechEngine;

    setState(() {
      _t2IsRunning = true;
      _t2Status = 'Synthesizing with $_t2Engine ($_t2Gender, [$_t2Lang])...';
    });

    final start = DateTime.now();
    try {
      await speech.synthesizeSpeech(text, _t2Lang, _t2Gender, _t2Engine);
      final ms = DateTime.now().difference(start).inMilliseconds;
      if (mounted) {
        setState(() {
          _t2IsRunning = false;
          _t2LatencyMs = ms;
          _t2Status = 'Playback finished (${ms}ms synthesis)';
        });
      }
      _log('Test 2 TTS Spoke [$_t2Lang, $_t2Engine]: "$text" in ${ms}ms');
    } catch (e) {
      if (mounted) {
        setState(() {
          _t2IsRunning = false;
          _t2Status = 'TTS Error: $e';
        });
      }
      _log('Test 2 TTS Error: $e');
    }
  }

  void _stopTtsPlayback() {
    final speech = context.read<TransceiverController>().speechEngine;
    speech.stopSpeech();
    setState(() {
      _t2IsRunning = false;
      _t3IsSynthesizing = false;
      _t4IsSynthesizing = false;
      _t5IsRunning = false;
    });
    _log('Audio playback forcibly stopped');
  }

  // --- Test 3: STT -> TTS Direct Voice Loop (No MT) ---
  Future<void> _runT3DirectSynthesis([String? textOverride]) async {
    final text = (textOverride ?? _t3Controller.text).trim();
    if (text.isEmpty) {
      setState(() => _t3Status = 'Please enter text or speak into the microphone.');
      return;
    }

    await _ensureTtsLoaded(_t3Lang, _t3Engine);
    if (!mounted) return;
    final speech = context.read<TransceiverController>().speechEngine;

    setState(() {
      _t3RecognizedText = text;
      _t3IsSynthesizing = true;
      _t3Status = 'Synthesizing voice output in [$_t3Lang] with $_t3Engine...';
    });

    final ttsStart = DateTime.now();
    try {
      await speech.synthesizeSpeech(text, _t3Lang, _t3Gender, _t3Engine);
      final ttsMs = DateTime.now().difference(ttsStart).inMilliseconds;
      if (mounted) {
        setState(() {
          _t3IsSynthesizing = false;
          _t3TtsMs = ttsMs;
          _t3TotalMs = ttsMs;
          _t3Status = 'Voice output active! Spoke in [$_t3Lang] (${ttsMs}ms)';
        });
      }
      _log('Test 3 Voice Output [$_t3Lang, $_t3Engine]: "$text" in ${ttsMs}ms');
    } catch (e) {
      if (mounted) {
        setState(() {
          _t3IsSynthesizing = false;
          _t3Status = 'TTS Error: $e';
        });
      }
      _log('Test 3 Voice Output Error: $e');
    }
  }

  Future<void> _toggleT3Recording() async {
    if (_activeRecordingTest == 3) {
      final sttStart = DateTime.now();
      final transcript = await _stopAudioCapture();
      final sttMs = DateTime.now().difference(sttStart).inMilliseconds;

      final recognized = transcript.trim().isNotEmpty
          ? transcript.trim()
          : (_t3Controller.text.trim().isNotEmpty
              ? _t3Controller.text.trim()
              : _t3RecognizedText.trim());

      if (recognized.isEmpty) {
        setState(() {
          _t3Status = 'No speech detected — please speak or use "Direct Voice Output".';
        });
        return;
      }

      _t3Controller.text = recognized;
      setState(() {
        _t3RecognizedText = recognized;
        _t3SttMs = sttMs;
        _t3IsSynthesizing = true;
        _t3Status = 'Synthesizing decoded text directly in [$_t3Lang] with $_t3Engine...';
      });

      await _ensureTtsLoaded(_t3Lang, _t3Engine);
      if (!mounted) return;
      final speech = context.read<TransceiverController>().speechEngine;
      final ttsStart = DateTime.now();
      try {
        await speech.synthesizeSpeech(recognized, _t3Lang, _t3Gender, _t3Engine);
        final ttsMs = DateTime.now().difference(ttsStart).inMilliseconds;
        if (mounted) {
          setState(() {
            _t3IsSynthesizing = false;
            _t3TtsMs = ttsMs;
            _t3TotalMs = sttMs + ttsMs;
            _t3Status = 'Direct loopback voice output complete! Spoke in [$_t3Lang]';
          });
        }
        _log('Test 3 STT->TTS Loop: "$recognized" (STT: ${sttMs}ms, TTS: ${ttsMs}ms)');
      } catch (e) {
        if (mounted) {
          setState(() {
            _t3IsSynthesizing = false;
            _t3Status = 'TTS Loopback Error: $e';
          });
        }
        _log('Test 3 Error: $e');
      }
    } else {
      await _ensureSttLoaded();
      await _ensureTtsLoaded(_t3Lang, _t3Engine);
      setState(() {
        _t3RecognizedText = '';
        _t3Status = 'Listening in [$_t3Lang]... Speak now!';
        _t3SttMs = 0;
        _t3TtsMs = 0;
        _t3TotalMs = 0;
      });
      await _startAudioCapture(
        testId: 3,
        langCode: _t3Lang,
        onLiveTranscript: (live) {
          setState(() {
            _t3RecognizedText = live;
            _t3Controller.text = live;
          });
        },
      );
    }
  }

  // --- Test 4: STT -> MT -> TTS Full Voice Pipeline ---
  Future<void> _toggleT4Recording() async {
    if (_activeRecordingTest == 4) {
      final sttStart = DateTime.now();
      final transcript = await _stopAudioCapture();
      final sttMs = DateTime.now().difference(sttStart).inMilliseconds;

      final recognized = transcript.isNotEmpty ? transcript : _t4SourceText;
      if (recognized.trim().isEmpty) {
        setState(() => _t4Status = 'No speech detected — pipeline halted.');
        return;
      }

      setState(() {
        _t4SourceText = recognized;
        _t4SttMs = sttMs;
        _t4Status = 'Translating [$_t4SourceLang] ➔ [$_t4TargetLang] via IndicTrans MT...';
      });

      if (!mounted) return;
      final trans = context.read<TransceiverController>().transEngine;
      _ensureMtLoaded();

      final mtStart = DateTime.now();
      String translated = recognized;
      if (_t4SourceLang != _t4TargetLang) {
        try {
          translated = await trans.translate(
            text: recognized,
            sourceLang: _t4SourceLang,
            targetLang: _t4TargetLang,
          );
        } catch (e) {
          translated = recognized;
        }
      }
      final mtMs = DateTime.now().difference(mtStart).inMilliseconds;

      setState(() {
        _t4TranslatedText = translated;
        _t4MtMs = mtMs;
        _t4IsSynthesizing = true;
        _t4Status = 'Synthesizing translated speech in [$_t4TargetLang] with $_t4Engine...';
      });

      await _ensureTtsLoaded(_t4TargetLang, _t4Engine);
      if (!mounted) return;
      final speech = context.read<TransceiverController>().speechEngine;
      final ttsStart = DateTime.now();
      try {
        await speech.synthesizeSpeech(translated, _t4TargetLang, _t4Gender, _t4Engine);
        final ttsMs = DateTime.now().difference(ttsStart).inMilliseconds;
        if (mounted) {
          setState(() {
            _t4IsSynthesizing = false;
            _t4TtsMs = ttsMs;
            _t4TotalMs = sttMs + mtMs + ttsMs;
            _t4Status = 'Full pipeline complete! Spoke in [$_t4TargetLang]';
          });
        }
        _log('Test 4 Voice Pipeline: "$recognized" ➔ "$translated" (STT: ${sttMs}ms, MT: ${mtMs}ms, TTS: ${ttsMs}ms)');
      } catch (e) {
        if (mounted) {
          setState(() {
            _t4IsSynthesizing = false;
            _t4Status = 'TTS Pipeline Error: $e';
          });
        }
        _log('Test 4 Error: $e');
      }
    } else {
      await _ensureSttLoaded();
      _ensureMtLoaded();
      await _ensureTtsLoaded(_t4TargetLang, _t4Engine);
      setState(() {
        _t4SourceText = '';
        _t4TranslatedText = '';
        _t4Status = 'Listening in [$_t4SourceLang]... Speak now!';
        _t4SttMs = 0;
        _t4MtMs = 0;
        _t4TtsMs = 0;
        _t4TotalMs = 0;
      });
      await _startAudioCapture(
        testId: 4,
        langCode: _t4SourceLang,
        onLiveTranscript: (live) {
          setState(() => _t4SourceText = live);
        },
      );
    }
  }

  // --- Test 5: Text -> MT -> TTS (NEW) ---
  Future<void> _runT5TextMtTts() async {
    final text = _t5Controller.text.trim();
    if (text.isEmpty) return;

    _ensureMtLoaded();
    await _ensureTtsLoaded(_t5TargetLang, _t5Engine);
    if (!mounted) return;

    setState(() {
      _t5IsRunning = true;
      _t5Status = 'Translating [$_t5SourceLang] ➔ [$_t5TargetLang] via IndicTrans MT...';
    });

    final trans = context.read<TransceiverController>().transEngine;
    final mtStart = DateTime.now();
    String translated = text;
    if (_t5SourceLang != _t5TargetLang) {
      try {
        translated = await trans.translate(
          text: text,
          sourceLang: _t5SourceLang,
          targetLang: _t5TargetLang,
        );
      } catch (e) {
        translated = text;
      }
    }
    final mtMs = DateTime.now().difference(mtStart).inMilliseconds;

    setState(() {
      _t5TranslatedText = translated;
      _t5MtMs = mtMs;
      _t5Status = 'Synthesizing audio in [$_t5TargetLang] via $_t5Engine...';
    });

    if (!mounted) return;
    final speech = context.read<TransceiverController>().speechEngine;
    final ttsStart = DateTime.now();
    try {
      await speech.synthesizeSpeech(translated, _t5TargetLang, _t5Gender, _t5Engine);
      final ttsMs = DateTime.now().difference(ttsStart).inMilliseconds;
      if (mounted) {
        setState(() {
          _t5IsRunning = false;
          _t5TtsMs = ttsMs;
          _t5TotalMs = mtMs + ttsMs;
          _t5Status = 'Complete! Translated & spoken in [$_t5TargetLang]';
        });
      }
      _log('Test 5 Text->MT->TTS: "$text" ➔ "$translated" (MT: ${mtMs}ms, TTS: ${ttsMs}ms)');
    } catch (e) {
      if (mounted) {
        setState(() {
          _t5IsRunning = false;
          _t5Status = 'Error in Test 5: $e';
        });
      }
      _log('Test 5 Error: $e');
    }
  }

  // --- Test 6: STT -> MT -> Text (NEW) ---
  Future<void> _toggleT6Recording() async {
    if (_activeRecordingTest == 6) {
      final sttStart = DateTime.now();
      final transcript = await _stopAudioCapture();
      final sttMs = DateTime.now().difference(sttStart).inMilliseconds;

      final recognized = transcript.isNotEmpty ? transcript : _t6SourceText;
      if (recognized.trim().isEmpty) {
        setState(() => _t6Status = 'No speech recognized.');
        return;
      }

      setState(() {
        _t6SourceText = recognized;
        _t6SttMs = sttMs;
        _t6IsTranslating = true;
        _t6Status = 'Translating [$_t6SourceLang] ➔ [$_t6TargetLang] via IndicTrans MT...';
      });

      _ensureMtLoaded();
      if (!mounted) return;
      final trans = context.read<TransceiverController>().transEngine;
      final mtStart = DateTime.now();
      String translated = recognized;
      if (_t6SourceLang != _t6TargetLang) {
        try {
          translated = await trans.translate(
            text: recognized,
            sourceLang: _t6SourceLang,
            targetLang: _t6TargetLang,
          );
        } catch (e) {
          translated = recognized;
        }
      }
      final mtMs = DateTime.now().difference(mtStart).inMilliseconds;

      if (mounted) {
        setState(() {
          _t6TranslatedText = translated;
          _t6MtMs = mtMs;
          _t6TotalMs = sttMs + mtMs;
          _t6IsTranslating = false;
          _t6Status = 'Translation complete (No TTS audio)';
        });
      }
      _log('Test 6 STT->MT->Text: "$recognized" ➔ "$translated" (STT: ${sttMs}ms, MT: ${mtMs}ms)');
    } else {
      await _ensureSttLoaded();
      _ensureMtLoaded();
      setState(() {
        _t6SourceText = '';
        _t6TranslatedText = '';
        _t6Status = 'Listening in [$_t6SourceLang]... Speak now!';
        _t6SttMs = 0;
        _t6MtMs = 0;
        _t6TotalMs = 0;
      });
      await _startAudioCapture(
        testId: 6,
        langCode: _t6SourceLang,
        onLiveTranscript: (live) {
          setState(() => _t6SourceText = live);
        },
      );
    }
  }

  // --- Test 7: Text -> MT -> Text (NEW) ---
  Future<void> _runT7TextMtText() async {
    final text = _t7Controller.text.trim();
    if (text.isEmpty) return;

    _ensureMtLoaded();
    setState(() {
      _t7IsTranslating = true;
      _t7Status = 'Translating [$_t7SourceLang] ➔ [$_t7TargetLang]...';
    });

    final trans = context.read<TransceiverController>().transEngine;
    final start = DateTime.now();
    String translated = text;
    if (_t7SourceLang != _t7TargetLang) {
      try {
        translated = await trans.translate(
          text: text,
          sourceLang: _t7SourceLang,
          targetLang: _t7TargetLang,
        );
      } catch (e) {
        translated = text;
      }
    }
    final ms = DateTime.now().difference(start).inMilliseconds;

    if (mounted) {
      setState(() {
        _t7TranslatedText = translated;
        _t7MtMs = ms;
        _t7IsTranslating = false;
        _t7Status = 'Translation finished in ${ms}ms';
      });
    }
    _log('Test 7 Pure MT: "$text" ➔ "$translated" in ${ms}ms');
  }

  // =========================================================================
  // UI BUILDERS: RESPONSIVE PORTRAIT-FIRST WIDGETS
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Neural Speech & Dev Diagnostics',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              '7 Unique Pipelines • Expert Model Diagnostics Lab',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
            tooltip: 'Stop any active audio synthesis',
            onPressed: _stopTtsPlayback,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Model RAM Status',
            onPressed: () {
              setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: [
            // Top Live Model Status Dashboard
            _buildModelStatusDashboard(theme, isDark),
            const SizedBox(height: 14),

            // Section Header
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: 18, color: AppTheme.accentCyan),
                const SizedBox(width: 8),
                Text(
                  'TEST PIPELINES (7 UNIQUE CONFIGURATIONS)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppTheme.accentCyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Card 1: STT (Speech -> Text)
            _buildCard1Stt(theme, isDark),
            const SizedBox(height: 12),

            // Card 2: TTS (Text -> Speech)
            _buildCard2Tts(theme, isDark),
            const SizedBox(height: 12),

            // Card 3: STT -> TTS Direct Voice Loop
            _buildCard3SttTts(theme, isDark),
            const SizedBox(height: 12),

            // Card 4: STT -> MT -> TTS Voice JIT Pipeline
            _buildCard4SttMtTts(theme, isDark),
            const SizedBox(height: 12),

            // Card 5: Text -> MT -> TTS (NEW)
            _buildCard5TextMtTts(theme, isDark),
            const SizedBox(height: 12),

            // Card 6: STT -> MT -> Text (NEW)
            _buildCard6SttMtText(theme, isDark),
            const SizedBox(height: 12),

            // Card 7: Text -> MT -> Text (NEW)
            _buildCard7TextMtText(theme, isDark),
            const SizedBox(height: 16),

            // Bottom Consolidated Activity Log
            _buildActivityLogSection(theme, isDark),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // --- Top Model Status Dashboard & Live Memory Manager ---
  Widget _buildModelStatusDashboard(ThemeData theme, bool isDark) {
    final transceiver = context.watch<TransceiverController>();
    final speech = transceiver.speechEngine;
    final mt = transceiver.transEngine;
    final vad = _vad;

    final loadedTtsKeys = speech.loadedTtsKeys;
    final isSttLoaded = speech.isSttLoaded;
    final sttVariant = speech.loadedSttVariant ?? (_isSttLoaded ? 'IndicConformer' : null);
    final isMtLoaded = mt.isLoaded;
    final isVadLoaded = vad.isNeuralActive;

    // Calculate dynamic memory footprint
    int activeRamMb = 0;
    int activeModelsCount = 0;
    if (isVadLoaded) {
      activeRamMb += 5;
      activeModelsCount++;
    }
    if (isSttLoaded) {
      activeModelsCount++;
      if (sttVariant == 'IndicConformer FP32') {
        activeRamMb += 550;
      } else if (sttVariant == 'Zipformer Streaming') {
        activeRamMb += 120;
      } else {
        activeRamMb += 180;
      }
    }
    final mtPrecision = mt.loadedPrecision;
    if (isMtLoaded) {
      activeRamMb += (mtPrecision == 'FP16' ? 220 : 110);
      activeModelsCount++;
    }
    for (final key in loadedTtsKeys) {
      activeModelsCount++;
      if (key.contains('RASA')) {
        activeRamMb += 160;
      } else {
        activeRamMb += 145;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with RAM counter & Purge All button
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.memory_rounded, size: 20, color: AppTheme.accentCyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEURAL MODELS & RAM MONITOR',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppTheme.accentCyan,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: activeModelsCount > 0 ? AppTheme.telemetryGreen : Colors.grey,
                              boxShadow: activeModelsCount > 0
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.telemetryGreen.withAlpha(120),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            activeModelsCount > 0
                                ? '$activeModelsCount Active in RAM • ~$activeRamMb MB Allocated'
                                : '0 Active Models • 0 MB RAM (Clean State)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: activeModelsCount > 0 ? AppTheme.telemetryGreen : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (activeModelsCount > 0)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.cleaning_services_rounded, size: 14),
                    label: const Text('Purge All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _unloadAllModels,
                  ),
                const SizedBox(width: 6),
                IconButton(
                  icon: _isScanningFiles
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Rescan model files & memory status',
                  onPressed: _scanInstalledModels,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Active Models Chip Bar (shows live loaded instances with 1-tap unload)
          if (activeModelsCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: isDark ? Colors.black.withAlpha(40) : Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENTLY LOADED IN RAM (TAP TO UNLOAD EACH):',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isVadLoaded)
                        _buildActiveModelChip(
                          label: 'Silero VAD (~5 MB)',
                          color: const Color(0xFF00E676),
                          onUnload: _unloadVad,
                        ),
                      if (isSttLoaded)
                        _buildActiveModelChip(
                          label: 'STT: ${sttVariant ?? "IndicConformer"} (~${sttVariant == "IndicConformer FP32" ? 550 : 180} MB)',
                          color: Colors.lightBlueAccent,
                          onUnload: _unloadStt,
                        ),
                      if (isMtLoaded)
                        _buildActiveModelChip(
                          label: 'MT: IndicTrans2 $mtPrecision (~${mtPrecision == "FP16" ? 220 : 110} MB)',
                          color: Colors.amberAccent,
                          onUnload: _unloadMt,
                        ),
                      ...loadedTtsKeys.map((key) {
                        final isRasa = key.contains('RASA');
                        final parts = key.split('_');
                        final lang = parts.isNotEmpty ? parts[0] : '';
                        final label = isRasa
                            ? 'TTS: Rasa-13 Universal (~160 MB)'
                            : 'TTS: Meta MMS [$lang] (~145 MB)';
                        return _buildActiveModelChip(
                          label: label,
                          color: isRasa ? const Color(0xFFFF5252) : const Color(0xFFAB47BC),
                          onUnload: () => _unloadTtsKey(key),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(height: 1),

          // Models Fleet Detailed Controls
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. VAD Row
                _buildModelControlTile(
                  icon: Icons.graphic_eq_rounded,
                  iconColor: const Color(0xFF00E676),
                  title: 'Silero Neural VAD',
                  subtitle: isVadLoaded
                      ? 'Active in RAM (~5 MB) • Real-time 512-sample neural voice detection'
                      : 'Offloaded (0 MB) • Using Pure-Dart RMS Energy Fallback',
                  isLoaded: isVadLoaded,
                  isInstalled: true,
                  onLoad: _loadVad,
                  onUnload: _unloadVad,
                ),
                const Divider(height: 18),

                // 2. STT Section
                _buildSttModelSection(theme, isDark, speech),
                const Divider(height: 18),

                // 3. MT Section
                _buildMtModelSection(theme, isDark, mt),
                const Divider(height: 18),

                // 4. TTS Fleet Section
                _buildTtsFleetSection(theme, isDark, speech),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveModelChip({
    required String label,
    required Color color,
    required VoidCallback onUnload,
  }) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onUnload,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withAlpha(60),
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelControlTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isLoaded,
    required bool isInstalled,
    required VoidCallback onLoad,
    required VoidCallback onUnload,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLoaded ? AppTheme.telemetryGreen.withAlpha(30) : Colors.grey.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isLoaded ? AppTheme.telemetryGreen : Colors.grey,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      isLoaded ? 'IN RAM' : (isInstalled ? 'OFFLOADED' : 'NOT INSTALLED'),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isLoaded ? AppTheme.telemetryGreen : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isLoaded)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onUnload,
            child: const Text('Unload', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          )
        else if (isInstalled)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: iconColor.withAlpha(200),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onLoad,
            child: const Text('Load', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _buildSttModelSection(ThemeData theme, bool isDark, SherpaOnnxSpeechEngine speech) {
    final isSttLoaded = speech.isSttLoaded;
    final activeVariant = speech.loadedSttVariant ?? (_isSttLoaded ? 'IndicConformer' : null);
    final isInt8Active = isSttLoaded && activeVariant != null && activeVariant.contains('INT8');
    final isFp32Active = isSttLoaded && activeVariant != null && activeVariant.contains('FP32');

    final isInt8Installed = _installedModels['stt_int8'] ?? false;
    final isFp32Installed = _installedModels['stt_fp32'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.lightBlueAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.mic_rounded, size: 20, color: Colors.lightBlueAccent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'AI4Bharat IndicConformer STT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSttLoaded ? AppTheme.telemetryGreen.withAlpha(30) : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSttLoaded ? AppTheme.telemetryGreen : Colors.grey,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isSttLoaded ? 'ACTIVE IN RAM' : 'OFFLOADED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isSttLoaded ? AppTheme.telemetryGreen : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSttLoaded
                        ? 'Active Variant: $activeVariant • Offline CTC transcription'
                        : 'No STT engine in RAM • Offloaded (0 MB)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (isSttLoaded)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _unloadStt,
                child: const Text('Unload STT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Two sub-cards: INT8 and FP32
        Row(
          children: [
            Expanded(
              child: _buildSttVariantCard(
                title: 'INT8 Fast (~180 MB)',
                isInstalled: isInt8Installed,
                isActive: isInt8Active,
                isLoading: _isSttLoading && isInt8Active,
                onLoad: () => _loadStt('INT8'),
                onUnload: _unloadStt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSttVariantCard(
                title: 'FP32 Studio (~550 MB)',
                isInstalled: isFp32Installed,
                isActive: isFp32Active,
                isLoading: _isSttLoading && isFp32Active,
                onLoad: () => _loadStt('FP32'),
                onUnload: _unloadStt,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSttVariantCard({
    required String title,
    required bool isInstalled,
    required bool isActive,
    required bool isLoading,
    required VoidCallback onLoad,
    required VoidCallback onUnload,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive ? Colors.lightBlueAccent.withAlpha(25) : Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? Colors.lightBlueAccent : Colors.grey.withAlpha(50),
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.lightBlueAccent : null,
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppTheme.telemetryGreen
                      : (isInstalled ? Colors.blueGrey : Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isInstalled ? (isActive ? 'Active in RAM' : 'On Disk') : 'Not Installed',
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? AppTheme.telemetryGreen : Colors.grey,
                ),
              ),
              if (isActive)
                InkWell(
                  onTap: onUnload,
                  child: const Text(
                    'Unload',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                )
              else if (isInstalled)
                InkWell(
                  onTap: onLoad,
                  child: const Text(
                    'Load',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMtModelSection(ThemeData theme, bool isDark, IndicTransEngine mt) {
    final isMtLoaded = mt.isLoaded;
    final activePrecision = mt.loadedPrecision; // 'INT8' or 'FP16'
    final isInt8Active = isMtLoaded && activePrecision == 'INT8';
    final isFp16Active = isMtLoaded && activePrecision == 'FP16';

    final isInt8Installed = _installedModels['mt_int8'] ?? false;
    final isFp16Installed = _installedModels['mt_fp16'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.translate_rounded, size: 20, color: Colors.amberAccent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'AI4Bharat IndicTrans2 MT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isMtLoaded ? AppTheme.telemetryGreen.withAlpha(30) : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isMtLoaded ? AppTheme.telemetryGreen : Colors.grey,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isMtLoaded ? 'ACTIVE IN RAM' : 'OFFLOADED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isMtLoaded ? AppTheme.telemetryGreen : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isMtLoaded
                        ? 'Active Variant: IndicTrans2 $activePrecision • Neural translation across 10 Indic languages'
                        : 'Offloaded (0 MB) • Tactical emergency lexicon fallback only',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (isMtLoaded)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _unloadMt,
                child: const Text('Unload MT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Two sub-cards: INT8 and FP16
        Row(
          children: [
            Expanded(
              child: _buildMtVariantCard(
                title: 'INT8 Fast (~110 MB)',
                isInstalled: isInt8Installed,
                isActive: isInt8Active,
                onLoad: () => _loadMt('INT8'),
                onUnload: _unloadMt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMtVariantCard(
                title: 'FP16 Studio (~220 MB)',
                isInstalled: isFp16Installed,
                isActive: isFp16Active,
                onLoad: () => _loadMt('FP16'),
                onUnload: _unloadMt,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMtVariantCard({
    required String title,
    required bool isInstalled,
    required bool isActive,
    required VoidCallback onLoad,
    required VoidCallback onUnload,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive ? Colors.amberAccent.withAlpha(25) : Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? Colors.amberAccent : Colors.grey.withAlpha(50),
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.amberAccent : null,
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppTheme.telemetryGreen
                      : (isInstalled ? Colors.blueGrey : Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isInstalled ? (isActive ? 'Active in RAM' : 'On Disk') : 'Not Installed',
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? AppTheme.telemetryGreen : Colors.grey,
                ),
              ),
              if (isActive)
                InkWell(
                  onTap: onUnload,
                  child: const Text(
                    'Unload',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                )
              else if (isInstalled)
                InkWell(
                  onTap: onLoad,
                  child: const Text(
                    'Load',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent,
                    ),
                  ),
                )
              else
                const Text(
                  'In Settings',
                  style: TextStyle(fontSize: 9, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTtsFleetSection(ThemeData theme, bool isDark, SherpaOnnxSpeechEngine speech) {
    final loadedKeys = speech.loadedTtsKeys;
    final isRasaLoaded = loadedKeys.any((k) => k.contains('RASA'));
    final isRasaInstalled = _installedModels['tts_rasa13'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFAB47BC).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.record_voice_over_rounded, size: 20, color: Color(0xFFAB47BC)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Neural TTS Engine Fleet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: loadedKeys.isNotEmpty
                              ? AppTheme.telemetryGreen.withAlpha(30)
                              : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: loadedKeys.isNotEmpty ? AppTheme.telemetryGreen : Colors.grey,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          loadedKeys.isNotEmpty ? '${loadedKeys.length} LOADED' : 'OFFLOADED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: loadedKeys.isNotEmpty ? AppTheme.telemetryGreen : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loadedKeys.isNotEmpty
                        ? '${loadedKeys.length} engine(s) active in RAM • Multi-voice speech synthesis'
                        : 'No TTS engine in RAM • Offloaded (0 MB)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (loadedKeys.isNotEmpty)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _unloadAllTts,
                child: const Text('Unload All TTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Sub-tier 1: Universal AI4Bharat Rasa-13 Model
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isRasaLoaded ? const Color(0xFFFF5252).withAlpha(20) : Colors.black.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isRasaLoaded ? const Color(0xFFFF5252) : Colors.grey.withAlpha(50),
              width: isRasaLoaded ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'AI4Bharat Rasa-13 Universal VITS (~160 MB)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (isRasaLoaded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.telemetryGreen.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.telemetryGreen),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Universal multi-accent Indic synthesizer • 1024 voices • 13 Indic languages',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isRasaLoaded)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    for (final k in loadedKeys.where((k) => k.contains('RASA')).toList()) {
                      _unloadTtsKey(k);
                    }
                  },
                  child: const Text('Unload', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                )
              else if (isRasaInstalled)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252).withAlpha(200),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () async {
                    context.read<SettingsController>().updateTtsEngineType('AI4BHARAT_RASA');
                    await _loadTts('hi', 'AI4BHARAT_RASA');
                    if (mounted) {
                      setState(() {
                        _t2Engine = 'AI4BHARAT_RASA';
                        _t3Engine = 'AI4BHARAT_RASA';
                        _t4Engine = 'AI4BHARAT_RASA';
                        _t5Engine = 'AI4BHARAT_RASA';
                      });
                    }
                  },
                  child: const Text('Load', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                )
              else
                const Text('Not Installed', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Sub-tier 2: Meta MMS Per-Language Models Grid
        Text(
          'META MMS DEDICATED MODELS (~145 MB EACH):',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LanguagePackManager.supportedLanguages.map((meta) {
            final key = '${meta.code}_META_MMS';
            final isLoaded = speech.isTtsKeyLoaded(key);
            final isInstalled = _installedModels['tts_mms_${meta.code}'] ?? false;

            return _buildMmsLanguageCard(
              meta: meta,
              isLoaded: isLoaded,
              isInstalled: isInstalled,
              onLoad: () async {
                context.read<SettingsController>().updateTtsEngineType('META_MMS');
                await _loadTts(meta.code, 'META_MMS');
                if (mounted) {
                  setState(() {
                    _t2Engine = 'META_MMS';
                    _t2Lang = meta.code;
                    _t3Engine = 'META_MMS';
                    _t3Lang = meta.code;
                    _t4Engine = 'META_MMS';
                    _t5Engine = 'META_MMS';
                  });
                }
              },
              onUnload: () => _unloadTtsKey(key),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Sub-tier 3: OS Native TTS
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withAlpha(15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF00E5FF).withAlpha(50),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'OS Native TTS Engine (Windows OneCore / Android TTS / iOS)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.telemetryGreen.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ALWAYS READY (0 MB)',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.telemetryGreen),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Zero-download built-in OS speech synthesis • Covers Gujarati, Odia, English & all 10 SIH languages',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF).withAlpha(180),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () async {
                  context.read<SettingsController>().updateTtsEngineType('OS_NATIVE');
                  await _loadTts('en', 'OS_NATIVE');
                  if (mounted) {
                    setState(() {
                      _t2Engine = 'OS_NATIVE';
                      _t3Engine = 'OS_NATIVE';
                      _t4Engine = 'OS_NATIVE';
                      _t5Engine = 'OS_NATIVE';
                    });
                  }
                },
                child: const Text('Use OS Native', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMmsLanguageCard({
    required LanguageMetadata meta,
    required bool isLoaded,
    required bool isInstalled,
    required VoidCallback onLoad,
    required VoidCallback onUnload,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLoaded ? const Color(0xFFAB47BC).withAlpha(30) : Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLoaded
              ? const Color(0xFFAB47BC)
              : (isInstalled ? Colors.grey.withAlpha(60) : Colors.grey.withAlpha(30)),
          width: isLoaded ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLoaded
                  ? AppTheme.telemetryGreen
                  : (isInstalled ? Colors.blueGrey : Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${meta.englishName} (${meta.code})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isLoaded ? FontWeight.bold : FontWeight.normal,
              color: isLoaded ? const Color(0xFFE1BEE7) : (isInstalled ? null : Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          if (isLoaded)
            InkWell(
              onTap: onUnload,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent, width: 0.8),
                ),
                child: const Text(
                  'Unload',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
              ),
            )
          else if (isInstalled)
            InkWell(
              onTap: onLoad,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFAB47BC).withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFAB47BC), width: 0.8),
                ),
                child: const Text(
                  'Load',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFE1BEE7)),
                ),
              ),
            )
          else
            const Text('N/A', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  // --- Helper: Responsive Language Wrap Selector ---
  Widget _buildLanguageSelector({
    required String title,
    required String selectedLang,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: LanguagePackManager.supportedLanguages.map((meta) {
            final isSelected = meta.code == selectedLang;
            return ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text(
                '${meta.code.toUpperCase()} • ${meta.nativeName}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.accentCyan.withAlpha(50),
              side: BorderSide(
                color: isSelected ? AppTheme.accentCyan : Colors.grey.withAlpha(50),
              ),
              onSelected: (_) => onSelected(meta.code),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Helper: Preset Phrase Quick-Pick ---
  Widget _buildPresetChips({
    required String langCode,
    required ValueChanged<String> onSelectPreset,
  }) {
    final phrase = _presets[langCode] ?? _presets['en']!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.flash_on_rounded, size: 14, color: Colors.amber),
        label: const Text('Load Standard Emergency Preset Phrase', style: TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        onPressed: () => onSelectPreset(phrase),
      ),
    );
  }

  // --- Helper: Standard Card Container ---
  Widget _buildTestCard({
    required int testId,
    required String title,
    required String subtitle,
    required Color accentColor,
    required bool isActive,
    required ValueChanged<bool> onToggleActive,
    required Widget body,
  }) {
    final isExpanded = _expanded[testId] ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? accentColor.withAlpha(80) : Colors.grey.withAlpha(40),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with switch and expand toggle
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() => _expanded[testId] = !isExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'T$testId',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: isActive,
                      activeThumbColor: accentColor,
                      activeTrackColor: accentColor.withAlpha(100),
                      onChanged: onToggleActive,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // Body
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: isActive
                  ? body
                  : Container(
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(Icons.power_settings_new, size: 28, color: Colors.grey),
                          const SizedBox(height: 6),
                          const Text(
                            'Test card disabled',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Toggle ON to load models and activate testing pipeline.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.black,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => onToggleActive(true),
                            child: const Text('Enable Test'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Helper: Mic Waveform & Amplitude Meter ---
  Widget _buildMicMeter({required bool isRecording}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isRecording ? Colors.red.withAlpha(20) : Colors.black.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecording ? Colors.redAccent.withAlpha(100) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isRecording ? Icons.mic : Icons.mic_off,
                    size: 16,
                    color: isRecording ? Colors.redAccent : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRecording ? 'RECORDING (${_recordSeconds}s)' : 'MIC STANDBY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isRecording ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _isVoiceDetected
                      ? AppTheme.telemetryGreen.withAlpha(30)
                      : Colors.grey.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isVoiceDetected ? 'VOICE DETECTED' : 'SILENCE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: _isVoiceDetected ? AppTheme.telemetryGreen : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isRecording ? _currentAmplitude : 0.0,
              minHeight: 6,
              backgroundColor: Colors.grey.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(
                _currentAmplitude > 0.6
                    ? Colors.redAccent
                    : (_currentAmplitude > 0.3 ? Colors.orangeAccent : AppTheme.telemetryGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: Output Text Box with Copy Action ---
  Widget _buildOutputWindow({
    required String title,
    required String content,
    List<Widget>? extraActions,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...?extraActions,
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy output text',
                    onPressed: content.isNotEmpty
                        ? () {
                            Clipboard.setData(ClipboardData(text: content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            content.isEmpty ? '(No output generated yet)' : content,
            style: TextStyle(
              fontSize: 13,
              fontStyle: content.isEmpty ? FontStyle.italic : FontStyle.normal,
              color: content.isEmpty ? Colors.grey : null,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: Latency Metrics Pill Bar ---
  Widget _buildMetricsBar(List<MapEntry<String, String>> metrics) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: metrics.map((m) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.accentCyan.withAlpha(50)),
          ),
          child: Text(
            '${m.key}: ${m.value}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppTheme.accentCyan,
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Helper: Warning banner when Rasa-13 is selected for unsupported languages (gu, or, en) ---
  Widget _buildRasaWarning(String engine, String lang) {
    if (engine != 'AI4BHARAT_RASA') return const SizedBox.shrink();
    if (!const {'gu', 'or', 'en'}.contains(lang.toLowerCase())) return const SizedBox.shrink();

    final langName = LanguagePackManager.supportedLanguages
        .firstWhere((l) => l.code == lang.toLowerCase(),
            orElse: () => LanguageMetadata(code: lang, iso3: '', englishName: lang.toUpperCase(), nativeName: ''))
        .englishName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
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
              'Rasa-13 lacks $langName ($lang). The audio engine will automatically route synthesis to Meta MMS / OS Native fallback.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // THE 7 TEST CARDS
  // =========================================================================

  // 1. STT Diagnostic
  Widget _buildCard1Stt(ThemeData theme, bool isDark) {
    final isRecording = _activeRecordingTest == 1;

    return _buildTestCard(
      testId: 1,
      title: 'STT (Speech ➔ Text)',
      subtitle: 'IndicConformer on-device speech transcription',
      accentColor: const Color(0xFF00E676),
      isActive: _t1Active,
      onToggleActive: (enable) {
        setState(() => _t1Active = enable);
        if (enable) _ensureSttLoaded();
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLanguageSelector(
            title: 'Decode Language (Select from all 10):',
            selectedLang: _t1Lang,
            onSelected: (l) {
              setState(() => _t1Lang = l);
              _log('Test 1 STT Language set to $l');
            },
          ),
          const SizedBox(height: 12),
          _buildMicMeter(isRecording: isRecording),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: Icon(isRecording ? Icons.stop : Icons.mic),
            label: Text(isRecording ? 'Stop & Decode Transcript' : 'Start Speaking (STT Test)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.redAccent : const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            onPressed: _toggleT1Recording,
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: 'RECOGNIZED TRANSCRIPT [${_t1Lang.toUpperCase()}]',
            content: _t1Transcript,
          ),
          if (_t1LatencyMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('STT Latency', '${_t1LatencyMs}ms'),
              MapEntry('Language', _t1Lang.toUpperCase()),
            ]),
          ],
        ],
      ),
    );
  }

  // 2. TTS Diagnostic (Default Meta MMS + English)
  Widget _buildCard2Tts(ThemeData theme, bool isDark) {
    return _buildTestCard(
      testId: 2,
      title: 'TTS (Text ➔ Speech)',
      subtitle: 'Neural VITS synthesis • Default: Meta MMS English',
      accentColor: const Color(0xFF448AFF),
      isActive: _t2Active,
      onToggleActive: (enable) {
        setState(() => _t2Active = enable);
        if (enable) _ensureTtsLoaded(_t2Lang, _t2Engine);
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('t2_$_t2Engine'),
                  initialValue: _t2Engine,
                  decoration: const InputDecoration(
                    labelText: 'TTS Engine',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'META_MMS', child: Text('Meta MMS VITS')),
                    DropdownMenuItem(value: 'AI4BHARAT_RASA', child: Text('AI4Bharat Rasa-13')),
                    DropdownMenuItem(value: 'OS_NATIVE', child: Text('OS Native (System)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _t2Engine = val);
                      context.read<SettingsController>().updateTtsEngineType(val);
                      _ensureTtsLoaded(_t2Lang, val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'FEMALE', label: Text('F', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'MALE', label: Text('M', style: TextStyle(fontSize: 11))),
                ],
                selected: {_t2Gender},
                onSelectionChanged: (set) => setState(() => _t2Gender = set.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'TTS Target Language (All 10 Languages):',
            selectedLang: _t2Lang,
            onSelected: (l) {
              setState(() {
                _t2Lang = l;
                _t2Controller.text = _presets[l] ?? _presets['en']!;
              });
              _ensureTtsLoaded(l, _t2Engine);
            },
          ),
          _buildRasaWarning(_t2Engine, _t2Lang),
          _buildPresetChips(
            langCode: _t2Lang,
            onSelectPreset: (p) => setState(() => _t2Controller.text = p),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _t2Controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Input Text to Speak',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _t2IsRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.volume_up_rounded),
                  label: Text(_t2IsRunning ? 'Synthesizing Audio...' : 'Synthesize & Speak'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF448AFF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _t2IsRunning ? null : _runT2Tts,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.stop, color: Colors.redAccent),
                tooltip: 'Stop Playback',
                onPressed: _stopTtsPlayback,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildOutputWindow(title: 'TTS SYNTHESIS STATUS', content: _t2Status),
          if (_t2LatencyMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('TTS Latency', '${_t2LatencyMs}ms'),
              MapEntry('Engine', _t2Engine),
              MapEntry('Voice', _t2Gender),
            ]),
          ],
        ],
      ),
    );
  }

  // 3. STT -> TTS Direct Voice Loop (No MT)
  Widget _buildCard3SttTts(ThemeData theme, bool isDark) {
    final isRecording = _activeRecordingTest == 3;

    return _buildTestCard(
      testId: 3,
      title: 'STT ➔ TTS (Direct Voice Loop)',
      subtitle: 'Voice loopback without translation • Default: Meta MMS en',
      accentColor: const Color(0xFFFF9100),
      isActive: _t3Active,
      onToggleActive: (enable) {
        setState(() => _t3Active = enable);
        if (enable) {
          _ensureSttLoaded();
          _ensureTtsLoaded(_t3Lang, _t3Engine);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('t3_$_t3Engine'),
                  initialValue: _t3Engine,
                  decoration: const InputDecoration(
                    labelText: 'Loopback TTS Engine',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'META_MMS', child: Text('Meta MMS VITS')),
                    DropdownMenuItem(value: 'AI4BHARAT_RASA', child: Text('AI4Bharat Rasa-13')),
                    DropdownMenuItem(value: 'OS_NATIVE', child: Text('OS Native (System)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _t3Engine = val);
                      context.read<SettingsController>().updateTtsEngineType(val);
                      _ensureTtsLoaded(_t3Lang, val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'FEMALE', label: Text('F', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'MALE', label: Text('M', style: TextStyle(fontSize: 11))),
                ],
                selected: {_t3Gender},
                onSelectionChanged: (set) => setState(() => _t3Gender = set.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Loopback Language (All 10 Languages):',
            selectedLang: _t3Lang,
            onSelected: (l) {
              setState(() {
                _t3Lang = l;
                _t3Controller.text = _presets[l] ?? _presets['en']!;
              });
              _ensureTtsLoaded(l, _t3Engine);
            },
          ),
          _buildRasaWarning(_t3Engine, _t3Lang),
          _buildPresetChips(
            langCode: _t3Lang,
            onSelectPreset: (p) => setState(() => _t3Controller.text = p),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _t3Controller,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Test Phrase / Speech Text (Type or Speak)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 10),
          _buildMicMeter(isRecording: isRecording),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _t3IsSynthesizing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Icon(isRecording ? Icons.stop : Icons.mic_rounded),
                  label: Text(_t3IsSynthesizing
                      ? 'Speaking Audio Loop...'
                      : (isRecording ? 'Stop & Speak Immediately' : 'Record Loop (Mic)')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording ? Colors.redAccent : const Color(0xFFFF9100),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _t3IsSynthesizing ? null : _toggleT3Recording,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Direct Voice Output'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _t3IsSynthesizing || isRecording
                      ? null
                      : () => _runT3DirectSynthesis(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                icon: const Icon(Icons.stop, color: Colors.redAccent),
                tooltip: 'Stop Playback',
                onPressed: _stopTtsPlayback,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: 'RECOGNIZED & SPOKEN TEXT',
            content: _t3RecognizedText.isNotEmpty ? _t3RecognizedText : _t3Controller.text,
          ),
          const SizedBox(height: 6),
          Text(_t3Status, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (_t3TotalMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('STT', '${_t3SttMs}ms'),
              MapEntry('TTS', '${_t3TtsMs}ms'),
              MapEntry('Total', '${_t3TotalMs}ms'),
            ]),
          ],
        ],
      ),
    );
  }

  // 4. STT -> MT -> TTS Full Voice Pipeline
  Widget _buildCard4SttMtTts(ThemeData theme, bool isDark) {
    final isRecording = _activeRecordingTest == 4;

    return _buildTestCard(
      testId: 4,
      title: 'STT ➔ MT ➔ TTS (Full Voice Pipeline)',
      subtitle: 'Complete voice-to-voice translation pipeline',
      accentColor: const Color(0xFF00E5FF),
      isActive: _t4Active,
      onToggleActive: (enable) {
        setState(() => _t4Active = enable);
        if (enable) {
          _ensureSttLoaded();
          _ensureMtLoaded();
          _ensureTtsLoaded(_t4TargetLang, _t4Engine);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('t4_$_t4Engine'),
                  initialValue: _t4Engine,
                  decoration: const InputDecoration(
                    labelText: 'Target TTS Engine',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'META_MMS', child: Text('Meta MMS VITS')),
                    DropdownMenuItem(value: 'AI4BHARAT_RASA', child: Text('AI4Bharat Rasa-13')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _t4Engine = val);
                      context.read<SettingsController>().updateTtsEngineType(val);
                      _ensureTtsLoaded(_t4TargetLang, val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'FEMALE', label: Text('F', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'MALE', label: Text('M', style: TextStyle(fontSize: 11))),
                ],
                selected: {_t4Gender},
                onSelectionChanged: (set) => setState(() => _t4Gender = set.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Source Voice Language (All 10):',
            selectedLang: _t4SourceLang,
            onSelected: (l) => setState(() => _t4SourceLang = l),
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Target Spoken Language (All 10, Default: EN):',
            selectedLang: _t4TargetLang,
            onSelected: (l) {
              setState(() => _t4TargetLang = l);
              _ensureTtsLoaded(l, _t4Engine);
            },
          ),
          const SizedBox(height: 10),
          _buildMicMeter(isRecording: isRecording),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: _t4IsSynthesizing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Icon(isRecording ? Icons.stop : Icons.record_voice_over_rounded),
            label: Text(_t4IsSynthesizing
                ? 'Synthesizing Pipeline Audio...'
                : (isRecording ? 'Stop & Translate + Speak' : 'Start Full Voice Pipeline Test')),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.redAccent : const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            onPressed: _t4IsSynthesizing ? null : _toggleT4Recording,
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: '1. SOURCE TRANSCRIPT [${_t4SourceLang.toUpperCase()}]',
            content: _t4SourceText,
          ),
          const SizedBox(height: 8),
          _buildOutputWindow(
            title: '2. TRANSLATED & SPOKEN [${_t4TargetLang.toUpperCase()}]',
            content: _t4TranslatedText,
          ),
          const SizedBox(height: 6),
          Text(_t4Status, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (_t4TotalMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('STT', '${_t4SttMs}ms'),
              MapEntry('MT', '${_t4MtMs}ms'),
              MapEntry('TTS', '${_t4TtsMs}ms'),
              MapEntry('Total', '${_t4TotalMs}ms'),
            ]),
          ],
        ],
      ),
    );
  }

  // 5. Text -> MT -> TTS (NEW)
  Widget _buildCard5TextMtTts(ThemeData theme, bool isDark) {
    return _buildTestCard(
      testId: 5,
      title: 'Text ➔ MT ➔ TTS (Text-to-Speech Translation)',
      subtitle: 'Type text in Source ➔ Neural Translate ➔ Speak in Target',
      accentColor: const Color(0xFFAB47BC),
      isActive: _t5Active,
      onToggleActive: (enable) {
        setState(() => _t5Active = enable);
        if (enable) {
          _ensureMtLoaded();
          _ensureTtsLoaded(_t5TargetLang, _t5Engine);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('t5_$_t5Engine'),
                  initialValue: _t5Engine,
                  decoration: const InputDecoration(
                    labelText: 'Target TTS Engine',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'META_MMS', child: Text('Meta MMS VITS')),
                    DropdownMenuItem(value: 'AI4BHARAT_RASA', child: Text('AI4Bharat Rasa-13')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _t5Engine = val);
                      context.read<SettingsController>().updateTtsEngineType(val);
                      _ensureTtsLoaded(_t5TargetLang, val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'FEMALE', label: Text('F', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'MALE', label: Text('M', style: TextStyle(fontSize: 11))),
                ],
                selected: {_t5Gender},
                onSelectionChanged: (set) => setState(() => _t5Gender = set.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Source Text Language (All 10):',
            selectedLang: _t5SourceLang,
            onSelected: (l) {
              setState(() {
                _t5SourceLang = l;
                _t5Controller.text = _presets[l] ?? _presets['en']!;
              });
            },
          ),
          _buildPresetChips(
            langCode: _t5SourceLang,
            onSelectPreset: (p) => setState(() => _t5Controller.text = p),
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Target Voice Language (All 10, Default: EN):',
            selectedLang: _t5TargetLang,
            onSelected: (l) {
              setState(() => _t5TargetLang = l);
              _ensureTtsLoaded(l, _t5Engine);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _t5Controller,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Input Source Text',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _t5IsRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.translate_rounded),
                  label: Text(_t5IsRunning ? 'Processing...' : 'Translate & Speak Audio'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAB47BC),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _t5IsRunning ? null : _runT5TextMtTts,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.stop, color: Colors.redAccent),
                tooltip: 'Stop Playback',
                onPressed: _stopTtsPlayback,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: 'TRANSLATED & SPOKEN TEXT [${_t5TargetLang.toUpperCase()}]',
            content: _t5TranslatedText,
          ),
          const SizedBox(height: 6),
          Text(_t5Status, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (_t5TotalMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('MT', '${_t5MtMs}ms'),
              MapEntry('TTS', '${_t5TtsMs}ms'),
              MapEntry('Total', '${_t5TotalMs}ms'),
            ]),
          ],
        ],
      ),
    );
  }

  // 6. STT -> MT -> Text (NEW)
  Widget _buildCard6SttMtText(ThemeData theme, bool isDark) {
    final isRecording = _activeRecordingTest == 6;

    return _buildTestCard(
      testId: 6,
      title: 'STT ➔ MT ➔ Text (Voice-to-Text Translation)',
      subtitle: 'Voice input transcribed & translated (No audio playback)',
      accentColor: const Color(0xFF26A69A),
      isActive: _t6Active,
      onToggleActive: (enable) {
        setState(() => _t6Active = enable);
        if (enable) {
          _ensureSttLoaded();
          _ensureMtLoaded();
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLanguageSelector(
            title: 'Source Voice Language (All 10):',
            selectedLang: _t6SourceLang,
            onSelected: (l) => setState(() => _t6SourceLang = l),
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Target Translated Language (All 10):',
            selectedLang: _t6TargetLang,
            onSelected: (l) => setState(() => _t6TargetLang = l),
          ),
          const SizedBox(height: 10),
          _buildMicMeter(isRecording: isRecording),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: _t6IsTranslating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Icon(isRecording ? Icons.stop : Icons.mic_external_on_rounded),
            label: Text(_t6IsTranslating
                ? 'Translating to Text...'
                : (isRecording ? 'Stop & Translate to Text' : 'Start Voice-to-Text Test')),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.redAccent : const Color(0xFF26A69A),
              foregroundColor: Colors.black,
            ),
            onPressed: _t6IsTranslating ? null : _toggleT6Recording,
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: '1. SOURCE SPEECH TRANSCRIPT [${_t6SourceLang.toUpperCase()}]',
            content: _t6SourceText,
          ),
          const SizedBox(height: 8),
          _buildOutputWindow(
            title: '2. TRANSLATED TARGET TEXT [${_t6TargetLang.toUpperCase()}]',
            content: _t6TranslatedText,
          ),
          const SizedBox(height: 6),
          Text(_t6Status, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (_t6TotalMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('STT', '${_t6SttMs}ms'),
              MapEntry('MT', '${_t6MtMs}ms'),
              MapEntry('Total', '${_t6TotalMs}ms'),
            ]),
          ],
        ],
      ),
    );
  }

  // 7. Text -> MT -> Text (NEW)
  Widget _buildCard7TextMtText(ThemeData theme, bool isDark) {
    return _buildTestCard(
      testId: 7,
      title: 'Text ➔ MT ➔ Text (Pure Neural Translation)',
      subtitle: 'Pure IndicTrans MT test without audio or microphone',
      accentColor: const Color(0xFFFF7043),
      isActive: _t7Active,
      onToggleActive: (enable) {
        setState(() => _t7Active = enable);
        if (enable) _ensureMtLoaded();
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLanguageSelector(
            title: 'Source Text Language (All 10):',
            selectedLang: _t7SourceLang,
            onSelected: (l) {
              setState(() {
                _t7SourceLang = l;
                _t7Controller.text = _presets[l] ?? _presets['en']!;
              });
            },
          ),
          _buildPresetChips(
            langCode: _t7SourceLang,
            onSelectPreset: (p) => setState(() => _t7Controller.text = p),
          ),
          const SizedBox(height: 10),
          _buildLanguageSelector(
            title: 'Target Translated Language (All 10):',
            selectedLang: _t7TargetLang,
            onSelected: (l) => setState(() => _t7TargetLang = l),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _t7Controller,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Input Text to Translate',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: _t7IsTranslating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.sync_alt_rounded),
            label: Text(_t7IsTranslating ? 'Translating...' : 'Translate Text (Pure MT)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7043),
              foregroundColor: Colors.black,
            ),
            onPressed: _t7IsTranslating ? null : _runT7TextMtText,
          ),
          const SizedBox(height: 10),
          _buildOutputWindow(
            title: 'TRANSLATED OUTPUT TEXT [${_t7TargetLang.toUpperCase()}]',
            content: _t7TranslatedText,
          ),
          const SizedBox(height: 6),
          Text(_t7Status, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (_t7MtMs > 0) ...[
            const SizedBox(height: 8),
            _buildMetricsBar([
              MapEntry('MT Duration', '${_t7MtMs}ms'),
              MapEntry('Direction', '${_t7SourceLang.toUpperCase()} ➔ ${_t7TargetLang.toUpperCase()}'),
            ]),
          ],
        ],
      ),
    );
  }

  // --- Bottom Consolidated Activity Log ---
  Widget _buildActivityLogSection(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withAlpha(40)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal_rounded, size: 16, color: AppTheme.accentCyan),
                  const SizedBox(width: 6),
                  Text(
                    'TEST RUN LOG (${_activityLogs.length} EVENTS)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppTheme.accentCyan,
                    ),
                  ),
                ],
              ),
              if (_activityLogs.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _activityLogs.clear()),
                  child: const Text('Clear', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_activityLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No events recorded yet. Run any test to view live execution logs.',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _activityLogs.length,
                itemBuilder: (context, idx) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      _activityLogs[idx],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
