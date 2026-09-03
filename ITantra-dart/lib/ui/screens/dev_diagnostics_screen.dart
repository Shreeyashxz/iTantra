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

  // --- TTS State ---
  String _selectedTtsLang = 'hi';
  final TextEditingController _ttsTextController = TextEditingController(
    text: 'नमस्ते, आई-तंत्र आपातकालीन न्यूरल ट्रांससीवर में आपका स्वागत है।',
  );
  bool _isSynthesizing = false;
  String _ttsStatusMessage = 'Idle (Ready to synthesize)';

  // --- STT -> MT -> TTS Pipeline State ---
  bool _isLoopRecording = false;
  bool _isLoopTranslating = false;
  bool _isLoopSynthesizing = false;
  String _loopStage = 'Idle (Ready to test STT -> MT -> TTS pipeline)';
  String _loopRecognizedText = '';
  String _loopTranslatedText = '';
  String _selectedLoopSourceLang = 'hi';
  String _selectedLoopTargetLang = 'en';

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
    _audioSub?.cancel();
    _vadSub?.cancel();
    _sttTextSub?.cancel();
    _recorder.dispose();
    _vad.release();
    _ttsTextController.dispose();
    super.dispose();
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

        // Calculate live RMS energy
        double sum = 0;
        for (int i = 0; i < chunk.length; i++) {
          final norm = chunk[i] / 32768.0;
          sum += norm * norm;
        }
        final rms = sqrt(sum / chunk.length);

        if (mounted) {
          setState(() {
            _currentAmplitude = (rms * 8.0).clamp(0.0, 1.0);
          });
        }
      });

      _vadSub?.cancel();
      _vadSub = _vad.startVad(stream).listen((isSpeech) {
        if (mounted) {
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
      final gender = context.read<SettingsController>().ttsGender;
      await speechEngine.synthesizeSpeech(text, _selectedTtsLang, gender);
      setState(() {
        _isSynthesizing = false;
        _ttsStatusMessage = 'Audio playing ($gender): "${text.length > 60 ? '${text.substring(0, 60)}...' : text}"';
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
      _isLoopSynthesizing = false;
      _ttsStatusMessage = 'Audio playback stopped';
      if (_isLoopRecording || _isLoopSynthesizing) {
        _loopStage = 'Loopback stopped.';
      }
    });
  }

  // --- STT -> MT -> TTS End-to-End Pipeline Methods ---
  Future<void> _startSttToMtToTtsLoopTest() async {
    final speechEngine = context.read<TransceiverController>().speechEngine;
    final settingsController = context.read<SettingsController>();

    setState(() {
      _isLoopRecording = true;
      _isLoopTranslating = false;
      _isLoopSynthesizing = false;
      _loopStage = 'Stage 1: 🎙️ Listening in [$_selectedLoopSourceLang]... Speak into microphone!';
      _loopRecognizedText = '';
      _loopTranslatedText = '';
      _totalSamplesCaptured = 0;
      _recordDurationSeconds = 0;
      _currentAmplitude = 0.0;
    });

    _vad.setSensitivity(settingsController.vadSensitivity);

    if (_sttInitialized) {
      final sttStream = speechEngine.startListening(_selectedLoopSourceLang);
      _sttTextSub?.cancel();
      _sttTextSub = sttStream.listen((text) {
        if (mounted && text.trim().isNotEmpty) {
          setState(() {
            _loopRecognizedText = text;
          });
        }
      });
    }

    try {
      final stream = await _recorder.startRecording();
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordDurationSeconds++);
        }
      });

      _audioSub?.cancel();
      _audioSub = stream.listen((chunk) {
        _totalSamplesCaptured += chunk.length;

        if (_sttInitialized) {
          speechEngine.feedAudioData(chunk);
        }

        // Calculate live RMS energy
        double sum = 0;
        for (int i = 0; i < chunk.length; i++) {
          final norm = chunk[i] / 32768.0;
          sum += norm * norm;
        }
        final rms = sqrt(sum / chunk.length);

        if (mounted) {
          setState(() {
            _currentAmplitude = (rms * 8.0).clamp(0.0, 1.0);
          });
        }
      });

      _vadSub?.cancel();
      _vadSub = _vad.startVad(stream).listen((isSpeech) {
        if (mounted) {
          setState(() {
            _isVoiceDetected = isSpeech;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isLoopRecording = false;
        _loopStage = 'Error starting audio recorder: $e';
      });
    }
  }

  Future<void> _stopSttToMtToTtsLoopAndSpeak() async {
    final transceiverCtrl = context.read<TransceiverController>();
    final speechEngine = transceiverCtrl.speechEngine;
    final settingsController = context.read<SettingsController>();

    _durationTimer?.cancel();
    await _audioSub?.cancel();
    _audioSub = null;
    await _vadSub?.cancel();
    _vadSub = null;
    await _recorder.stopRecording();
    _vad.stopVad();

    setState(() {
      _isLoopRecording = false;
      _currentAmplitude = 0.0;
      _isVoiceDetected = false;
      _loopStage = 'Stage 2: 🧠 Decoding STT speech with AI4Bharat IndicConformer...';
    });

    final transcript = await speechEngine.stopListeningAndTranscribe(_selectedLoopSourceLang);
    await _sttTextSub?.cancel();
    _sttTextSub = null;

    final sourceText = transcript.isNotEmpty
        ? transcript
        : (_loopRecognizedText.isNotEmpty ? _loopRecognizedText : '');

    if (sourceText.isEmpty) {
      setState(() {
        _loopStage = 'No speech recognized. Pipeline halted. Speak closer to microphone.';
      });
      _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->MT->TTS: No speech detected');
      return;
    }

    setState(() {
      _loopRecognizedText = sourceText;
      _isLoopTranslating = true;
      _loopStage = 'Stage 3: 🌐 Translating via AI4Bharat IndicTrans ($_selectedLoopSourceLang ➔ $_selectedLoopTargetLang)...';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT Recognized ($_selectedLoopSourceLang): "$sourceText"');

    String translated = sourceText;
    if (_selectedLoopSourceLang != _selectedLoopTargetLang) {
      try {
        translated = await transceiverCtrl.transEngine.translate(
          text: sourceText,
          sourceLang: _selectedLoopSourceLang,
          targetLang: _selectedLoopTargetLang,
        );
      } catch (e) {
        debugPrint('[DevDiagnostics] Translation error: $e');
        translated = sourceText;
      }
    }

    setState(() {
      _isLoopTranslating = false;
      _loopTranslatedText = translated;
      _isLoopSynthesizing = true;
      _loopStage = 'Stage 4: 🔊 Synthesizing & playing translated voice in $_selectedLoopTargetLang: "$translated"...';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] MT Translated ($_selectedLoopTargetLang): "$translated"');

    try {
      final gender = settingsController.ttsGender;
      await speechEngine.synthesizeSpeech(translated, _selectedLoopTargetLang, gender);
      if (mounted) {
        setState(() {
          _isLoopSynthesizing = false;
          _loopStage = 'Stage 5: ✅ Translation Loop Complete! Spoke in $_selectedLoopTargetLang ($gender).';
        });
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->MT->TTS Complete: Spoke in $_selectedLoopTargetLang ($gender)');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoopSynthesizing = false;
          _loopStage = 'TTS Error during translation playback: $e';
        });
        _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] STT->MT->TTS Playback Error: $e');
      }
    }
  }

  Future<void> _runMockSttMtTtsTest(String testText) async {
    final transceiverCtrl = context.read<TransceiverController>();
    final speechEngine = transceiverCtrl.speechEngine;
    final settingsController = context.read<SettingsController>();

    setState(() {
      _loopRecognizedText = testText;
      _isLoopTranslating = true;
      _loopStage = 'Simulated STT: "$testText" -> Translating ($_selectedLoopSourceLang ➔ $_selectedLoopTargetLang)...';
    });

    String translated = testText;
    if (_selectedLoopSourceLang != _selectedLoopTargetLang) {
      try {
        translated = await transceiverCtrl.transEngine.translate(
          text: testText,
          sourceLang: _selectedLoopSourceLang,
          targetLang: _selectedLoopTargetLang,
        );
      } catch (e) {
        translated = testText;
      }
    }

    setState(() {
      _isLoopTranslating = false;
      _loopTranslatedText = translated;
      _isLoopSynthesizing = true;
      _loopStage = 'Simulated MT: "$translated" -> Synthesizing TTS in $_selectedLoopTargetLang...';
    });
    _transcriptLog.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Mock STT->MT->TTS: "$testText" ➔ "$translated"');

    try {
      final gender = settingsController.ttsGender;
      await speechEngine.synthesizeSpeech(translated, _selectedLoopTargetLang, gender);
      if (mounted) {
        setState(() {
          _isLoopSynthesizing = false;
          _loopStage = '✅ Complete! Spoke "$translated" in $_selectedLoopTargetLang ($gender).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoopSynthesizing = false;
          _loopStage = 'Mock TTS Error: $e';
        });
      }
    }
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
                        Row(
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              color: _isRecording ? Colors.red : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '1. STT Diagnostic Test (Record & Text)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red.withAlpha(40)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isRecording ? Colors.red : theme.colorScheme.outline,
                            ),
                          ),
                          child: Text(
                            _isRecording ? 'LIVE RECORDING (${_recordDurationSeconds}s)' : 'STANDBY',
                            style: TextStyle(
                              color: _isRecording ? Colors.red : theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                        Row(
                          children: [
                            Icon(Icons.volume_up_rounded, color: theme.colorScheme.secondary),
                            const SizedBox(width: 8),
                            Text(
                              '2. TTS Diagnostic Test (Text-to-Audio)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _isSynthesizing ? Colors.green.withAlpha(40) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isSynthesizing ? Colors.green : theme.colorScheme.outline,
                            ),
                          ),
                          child: Text(
                            _isSynthesizing ? 'SYNTHESIZING' : 'READY',
                            style: TextStyle(
                              color: _isSynthesizing ? Colors.green : theme.colorScheme.outline,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                    const SizedBox(height: 14),

                    // Language & Gender Selectors
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
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
            // SECTION 3: STT -> MT -> TTS PIPELINE TEST CARD
            // ==========================================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _isLoopRecording || _isLoopTranslating || _isLoopSynthesizing
                      ? Colors.teal.shade700
                      : theme.colorScheme.outlineVariant,
                  width: _isLoopRecording || _isLoopTranslating || _isLoopSynthesizing ? 1.5 : 1.0,
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
                        Row(
                          children: [
                            Icon(
                              Icons.translate_rounded,
                              color: _isLoopRecording || _isLoopTranslating || _isLoopSynthesizing
                                  ? Colors.teal.shade700
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '3. STT ➔ MT ➔ TTS Pipeline Test',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _isLoopRecording
                                ? Colors.red.withAlpha(40)
                                : _isLoopTranslating
                                    ? Colors.blue.withAlpha(40)
                                    : _isLoopSynthesizing
                                        ? Colors.green.withAlpha(40)
                                        : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isLoopRecording
                                  ? Colors.red
                                  : _isLoopTranslating
                                      ? Colors.blue
                                      : _isLoopSynthesizing
                                          ? Colors.green
                                          : theme.colorScheme.outline,
                            ),
                          ),
                          child: Text(
                            _isLoopRecording
                                ? 'RECORDING SPEECH'
                                : _isLoopTranslating
                                    ? 'INDIC-TRANS MT'
                                    : _isLoopSynthesizing
                                        ? 'PLAYING TTS VOICE'
                                        : 'READY',
                            style: TextStyle(
                              color: _isLoopRecording
                                  ? Colors.red
                                  : _isLoopTranslating
                                      ? Colors.blue
                                      : _isLoopSynthesizing
                                          ? Colors.green
                                          : theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Complete translation transceiver pipeline: Voice ➔ IndicConformer STT ➔ AI4Bharat IndicTrans2 MT ➔ Neural TTS ➔ Translated Audio.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.memory_rounded, size: 13, color: Colors.teal),
                          const SizedBox(width: 6),
                          Text(
                            context.watch<TransceiverController>().transEngine.engineStatus,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Visual Pipeline Flow Diagram
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
                            isActive: _isLoopRecording,
                            isDone: !_isLoopRecording && _loopRecognizedText.isNotEmpty,
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.graphic_eq_rounded,
                            label: '2. Indic STT',
                            isActive: _loopStage.contains('Stage 2'),
                            isDone: _loopRecognizedText.isNotEmpty,
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.translate_rounded,
                            label: '3. IndicTrans MT',
                            isActive: _isLoopTranslating,
                            isDone: _loopTranslatedText.isNotEmpty,
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.volume_up_rounded,
                            label: '4. Neural TTS',
                            isActive: _isLoopSynthesizing,
                            isDone: _loopStage.contains('Stage 5'),
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                          _buildPipelineNode(
                            icon: Icons.hearing_rounded,
                            label: '5. Audio Out',
                            isActive: _isLoopSynthesizing,
                            isDone: _loopStage.contains('Complete'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Source, Target Language & Voice Selection Row
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedLoopSourceLang,
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
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedLoopSourceLang = val);
                              }
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.teal, size: 18),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedLoopTargetLang,
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
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedLoopTargetLang = val);
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
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'FEMALE', child: Text('👩 Female', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'MALE', child: Text('👨 Male', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                settingsController.updateTtsGender(val);
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Dual Text Box Display: Recognized Source & Translated Output
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isLoopRecording || _isLoopTranslating || _isLoopSynthesizing
                              ? Colors.teal.shade700
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Source recognized text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🎙️ Recognized Speech (${_selectedLoopSourceLang.toUpperCase()}):',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_isLoopRecording)
                                const Text(
                                  '● LISTENING',
                                  style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loopRecognizedText.isEmpty
                                ? 'Speak into microphone to recognize speech...'
                                : _loopRecognizedText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),

                          // Target translated text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🌐 IndicTrans Translated (${_selectedLoopTargetLang.toUpperCase()}):',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_isLoopTranslating)
                                const Text(
                                  '● TRANSLATING',
                                  style: TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loopTranslatedText.isEmpty
                                ? (_isLoopTranslating ? 'Translating text...' : 'Waiting for recognized speech...')
                                : _loopTranslatedText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Text(
                            _loopStage,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: _loopStage.startsWith('Error')
                                  ? Colors.red
                                  : _loopStage.contains('Complete')
                                      ? Colors.green
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Action Buttons for STT -> MT -> TTS
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoopTranslating || _isLoopSynthesizing
                                ? null
                                : _isLoopRecording
                                    ? _stopSttToMtToTtsLoopAndSpeak
                                    : _startSttToMtToTtsLoopTest,
                            icon: Icon(
                              _isLoopRecording
                                  ? Icons.stop_rounded
                                  : Icons.record_voice_over_rounded,
                            ),
                            label: Text(
                              _isLoopRecording
                                  ? 'STOP & TRANSLATE ECHO'
                                  : 'RECORD & TRANSLATE (STT➔MT➔TTS)',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isLoopRecording
                                  ? Colors.red
                                  : Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _isLoopRecording || _isLoopTranslating || _isLoopSynthesizing
                              ? null
                              : () {
                                  final sample = _selectedLoopSourceLang == 'hi'
                                      ? 'नमस्ते, आपातकालीन सहायता चाहिए।'
                                      : _selectedLoopSourceLang == 'en'
                                          ? 'Emergency assistance needed at base station.'
                                          : 'आणीबाणी मदत हवी आहे.';
                                  _runMockSttMtTtsTest(sample);
                                },
                          child: const Text('Simulate MT'),
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
