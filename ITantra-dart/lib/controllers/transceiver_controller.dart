import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../alerts/alert_broadcaster.dart';
import '../alerts/alert_receiver.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_mesh_manager.dart';
import '../proto/transceiver_packet.dart';
import '../speech/comm_pipeline.dart';
import '../speech/indic_trans_engine.dart';
import '../speech/script_normalization_engine.dart';
import '../speech/sherpa_onnx_speech_engine.dart';

class TransceiverController extends ChangeNotifier {
  final CommPipeline commPipeline;
  final TransceiverManager transceiverManager;
  final WifiMeshManager meshManager;
  final AlertBroadcaster alertBroadcaster;
  final AlertReceiver alertReceiver;
  final SherpaOnnxSpeechEngine speechEngine;
  final AppDatabase database;
  final IndicTransEngine transEngine = IndicTransEngine();

  late final String deviceId;
  List<MessageEntity> _messages = [];
  List<MessageEntity> get messages => _messages;

  AlertEvent? _activeAlert;
  AlertEvent? get activeAlert => _activeAlert;

  String _connectionStatus = 'Disconnected';
  String get connectionStatus => _connectionStatus;

  bool _isTransmitting = false;
  bool get isTransmitting => _isTransmitting;

  String _selectedLanguage = 'hi';
  String get selectedLanguage => _selectedLanguage;

  bool _isMtEnabled = true;
  bool get isMtEnabled => _isMtEnabled;

  bool _isVadMode = false;
  bool get isVadMode => _isVadMode;

  bool _isVoiceDetected = false;
  bool get isVoiceDetected => _isVoiceDetected;

  int? get linkRttMs => transceiverManager.averageRttMs;

  /// Whether the STT engine is loaded and ready for PTT
  bool get isSttReady => speechEngine.isSttLoaded;

  /// Last PTT error message (null when no error)
  String? _pttError;
  String? get pttError => _pttError;

  /// Whether STT is currently being initialized
  bool _isSttInitializing = false;
  bool get isSttInitializing => _isSttInitializing;

  /// Active TTS engine type ('AI4BHARAT_RASA' or 'META_MMS')
  String _ttsEngineType = 'AI4BHARAT_RASA';
  String get ttsEngineType => _ttsEngineType;
  bool get isRasa => _ttsEngineType == 'AI4BHARAT_RASA';

  Future<void> toggleTtsEngine() async {
    _ttsEngineType = _ttsEngineType == 'AI4BHARAT_RASA' ? 'META_MMS' : 'AI4BHARAT_RASA';
    notifyListeners();
    try {
      final settings = await database.getSettings();
      await database.saveSettings(settings.copyWith(ttsEngineType: _ttsEngineType));
      unawaited(speechEngine.initTts(_selectedLanguage, _ttsEngineType));
      debugPrint('[TransceiverController] TTS Engine switched to: $_ttsEngineType');
    } catch (e) {
      debugPrint('[TransceiverController] Error saving TTS engine switch: $e');
    }
  }

  StreamSubscription<TransceiverPacket>? _packetSubscription;
  StreamSubscription<AlertEvent?>? _alertSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<List<MessageEntity>>? _dbSubscription;
  StreamSubscription<dynamic>? _statsSubscription;

  TransceiverController({
    required this.commPipeline,
    required this.transceiverManager,
    required this.meshManager,
    required this.alertBroadcaster,
    required this.alertReceiver,
    required this.speechEngine,
    required this.database,
  }) {
    deviceId = 'DEV_${Random().nextInt(90000) + 10000}';
    _connectionStatus = transceiverManager.currentStatusString;
    _init();
  }

  Future<void> _init() async {
    // Load settings including MT preference and TTS engine type
    final initialSettings = await database.getSettings();
    _isMtEnabled = initialSettings.isMtEnabled;
    _ttsEngineType = initialSettings.ttsEngineType;

    // Load initial message history
    _messages = await database.getAllMessages();
    notifyListeners();

    // ── Start Wi-Fi Mesh presence beaconing automatically on startup ──
    try {
      debugPrint('[TransceiverController] Auto-starting mesh beacon service on startup...');
      unawaited(meshManager.startBeaconService(
        customNodeName: 'iTantra Node ($deviceId)',
      ));
    } catch (e) {
      debugPrint('[TransceiverController] Beacon service start notice: $e');
    }

    // ── Auto-initialize STT engine so PTT works immediately ──
    _isSttInitializing = true;
    notifyListeners();
    try {
      final sttOk = await speechEngine.initStt();
      debugPrint('[TransceiverController] STT auto-init: ${sttOk ? "SUCCESS" : "FAILED (models not downloaded?)"}');
    } catch (e) {
      debugPrint('[TransceiverController] STT auto-init error: $e');
    }
    _isSttInitializing = false;
    notifyListeners();

    // Listen for incoming packets
    _packetSubscription = transceiverManager.incomingPackets.listen((packet) async {
      final entity = MessageEntity(
        senderId: packet.senderId,
        text: packet.transcript,
        languageCode: packet.languageCode,
        type: packet.type.name.toUpperCase(),
        timestamp: packet.timestampMs,
        isIncoming: true,
      );
      await database.insertMessage(entity);
      _messages = await database.getAllMessages();
      notifyListeners();

      if (packet.type == PacketType.voice) {
        final settings = await database.getSettings();
        if (settings.autoPlayAudio) {
          String textToSpeak = packet.transcript;

          // Determine playback language:
          // If MT is enabled and languages differ -> translate to receiver's selected language
          // If MT is disabled -> output voice in the sender's original language (packet.languageCode)
          final String speechLang = (_isMtEnabled && packet.languageCode != _selectedLanguage)
              ? _selectedLanguage
              : packet.languageCode;

          final effectiveEngine = _ttsEngineType;
          final ttsWarmUp = speechEngine.initTts(speechLang, effectiveEngine);

          if (_isMtEnabled && packet.languageCode != _selectedLanguage) {
            try {
              final translationFuture = transEngine.translate(
                text: packet.transcript,
                sourceLang: packet.languageCode,
                targetLang: _selectedLanguage,
              );
              // Wait for MT translation and TTS engine warm-up concurrently
              final results = await Future.wait([translationFuture, ttsWarmUp]);
              textToSpeak = results[0] as String;
            } catch (e) {
              debugPrint('[TransceiverController] MT translation error: $e');
              await ttsWarmUp;
            }
          } else {
            // MT is bypassed or languages match — zero translation overhead!
            await ttsWarmUp;
          }

          textToSpeak = ScriptNormalizationEngine.prepareTextForTts(
            textToSpeak,
            speechLang,
            effectiveEngine,
          );

          await speechEngine.synthesizeSpeech(
            textToSpeak,
            speechLang,
            settings.ttsGender,
            effectiveEngine,
          );
        }
      }
    });

    // B1: Warm-up active language TTS engine in background after initialization
    unawaited(
      database.getSettings().then((settings) {
        speechEngine.initTts(_selectedLanguage, _ttsEngineType);
      }).catchError((e) {
        debugPrint('[TransceiverController] Startup warm-up ignored: $e');
      }),
    );

    // Listen for alerts
    _alertSubscription = alertReceiver.activeAlert.listen((alert) {
      _activeAlert = alert;
      notifyListeners();
    });

    // Listen for real connection status changes from TransceiverManager
    _statusSubscription = transceiverManager.connectionState.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    // Listen for database updates
    _dbSubscription = database.messagesStream.listen((list) {
      _messages = list;
      notifyListeners();
    });

    // Listen for network stats updates (RTT / Latency)
    _statsSubscription = transceiverManager.statsStream.listen((_) {
      notifyListeners();
    });
  }

  /// Handles PTT button press — ensures STT is loaded before starting mic+pipeline
  Future<void> onPttPressed() async {
    if (_isVadMode) return; // In VAD auto-mode, PTT is automatic
    if (_isTransmitting) return;

    // Clear any previous error
    _pttError = null;

    // Guard: ensure STT model is loaded
    if (!speechEngine.isSttLoaded) {
      debugPrint('[PTT] STT not loaded — attempting on-the-fly init...');
      _isSttInitializing = true;
      notifyListeners();
      try {
        final ok = await speechEngine.initStt();
        _isSttInitializing = false;
        if (!ok) {
          _pttError = 'STT model not loaded. Download from Settings → Language Packs.';
          notifyListeners();
          debugPrint('[PTT] BLOCKED: STT init failed — models not downloaded');
          return;
        }
      } catch (e) {
        _isSttInitializing = false;
        _pttError = 'STT initialization error: $e';
        notifyListeners();
        return;
      }
    }

    _isTransmitting = true;
    notifyListeners();
    debugPrint('[PTT] ▶ Recording started (lang=$_selectedLanguage, stt=${speechEngine.loadedSttVariant})');

    await commPipeline.startTransmission(
      senderId: deviceId,
      languageCode: _selectedLanguage,
      onTranscript: (text) async {
        // Save live/partial transcripts to message history
        if (text.trim().isNotEmpty) {
          debugPrint('[PTT] Live transcript: "$text"');
        }
      },
      onVoiceDetected: (isDetected) {
        _isVoiceDetected = isDetected;
        notifyListeners();
      },
    );
  }

  /// Handles PTT button release — stops recording, transcribes, sends packet, saves to DB
  Future<void> onPttReleased() async {
    if (_isVadMode) return;
    if (!_isTransmitting) return;

    _isTransmitting = false;
    _isVoiceDetected = false;
    notifyListeners();
    debugPrint('[PTT] ■ Recording stopped — finalizing STT...');

    final transcript = await commPipeline.stopTransmissionAndGetTranscript();

    if (transcript.isNotEmpty) {
      debugPrint('[PTT] Final transcript: "$transcript" — saving to DB');
      final entity = MessageEntity(
        senderId: deviceId,
        text: transcript,
        languageCode: _selectedLanguage,
        type: 'VOICE',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isIncoming: false,
      );
      await database.insertMessage(entity);
      _messages = await database.getAllMessages();
      notifyListeners();
    } else {
      debugPrint('[PTT] No speech detected — nothing sent');
    }
  }

  /// Clears the PTT error state (called by UI after displaying)
  void clearPttError() {
    _pttError = null;
    notifyListeners();
  }

  /// Toggles between PTT (Push-To-Talk) and VAD (Hands-Free Voice Activity Detection) mode
  void toggleVadMode() {
    _isVadMode = !_isVadMode;
    if (_isVadMode) {
      // Start continuous VAD auto-detection
      commPipeline.startVadAutoMode(
        senderId: deviceId,
        languageCode: _selectedLanguage,
        onTranscript: (text) {
          // Live preview or partial transcripts
        },
        onVoiceDetected: (isDetected) {
          _isVoiceDetected = isDetected;
          _isTransmitting = commPipeline.isTransmitting;
          notifyListeners();
        },
      );
    } else {
      // Stop continuous VAD and return to manual PTT
      commPipeline.stopVadAutoMode();
      _isTransmitting = false;
      _isVoiceDetected = false;
    }
    notifyListeners();
  }


  /// Broadcasts a voice or quiet-mode utterance through the mesh transceiver pipeline
  Future<void> sendUtterance(String text) async {
    if (text.trim().isEmpty) return;

    final entity = MessageEntity(
      senderId: deviceId,
      text: text,
      languageCode: _selectedLanguage,
      type: 'VOICE',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isIncoming: false,
    );
    await database.insertMessage(entity);

    await commPipeline.sendUtterance(
      senderId: deviceId,
      languageCode: _selectedLanguage,
      text: text,
    );
    _messages = await database.getAllMessages();
    notifyListeners();
  }

  void setLanguage(String code) {
    _selectedLanguage = code;
    notifyListeners();
  }

  Future<void> setMtEnabled(bool enabled) async {
    if (_isMtEnabled != enabled) {
      _isMtEnabled = enabled;
      notifyListeners();
      try {
        final currentSettings = await database.getSettings();
        await database.saveSettings(currentSettings.copyWith(isMtEnabled: enabled));
      } catch (e) {
        debugPrint('[TransceiverController] Error saving MT setting: $e');
      }
    }
  }

  void toggleMt() {
    setMtEnabled(!_isMtEnabled);
  }

  /// Triggers a live Just-In-Time (JIT) end-to-end pipeline run:
  /// Text -> Machine Translation -> Mesh Transmission -> Neural TTS Synthesis
  Future<void> triggerJitPipeline([String? customText]) async {
    final text = customText ?? (selectedLanguage == 'hi' ? 'आपातकालीन सहायता की आवश्यकता है' : 'Emergency assistance required immediately');
    debugPrint('[JIT Pipeline] Executing Just-In-Time pipeline for: "$text"');
    await sendUtterance(text);
  }

  Future<void> sendEmergencyAlert(String alertText, {String? languageCode}) async {
    final lang = languageCode ?? _selectedLanguage;
    await alertBroadcaster.broadcastAlert(
      senderId: deviceId,
      languageCode: lang,
      alertText: alertText,
    );

    final entity = MessageEntity(
      senderId: deviceId,
      text: alertText,
      languageCode: lang,
      type: 'ALERT',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isIncoming: false,
    );
    await database.insertMessage(entity);
    _messages = await database.getAllMessages();
    notifyListeners();
  }

  void dismissAlert() {
    _activeAlert = null;
    alertReceiver.dismissAlert();
    notifyListeners();
  }

  void startPeerDiscovery() {
    meshManager.probeSubnet();
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    _alertSubscription?.cancel();
    _statusSubscription?.cancel();
    _dbSubscription?.cancel();
    _statsSubscription?.cancel();
    super.dispose();
  }
}
