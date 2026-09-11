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
    // Load settings including MT preference
    final initialSettings = await database.getSettings();
    _isMtEnabled = initialSettings.isMtEnabled;

    // Load initial message history
    _messages = await database.getAllMessages();
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

          // B2: Overlapped MT Translation + TTS Pre-warming (only if MT enabled and languages differ)
          final ttsWarmUp = speechEngine.initTts(_selectedLanguage, settings.ttsEngineType);

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
            _selectedLanguage,
            settings.ttsEngineType,
          );

          await speechEngine.synthesizeSpeech(
            textToSpeak,
            _selectedLanguage,
            settings.ttsGender,
            settings.ttsEngineType,
          );
        }
      }
    });

    // B1: Warm-up active language TTS engine in background after initialization
    unawaited(
      database.getSettings().then((settings) {
        speechEngine.initTts(_selectedLanguage, settings.ttsEngineType);
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

  void onPttPressed() {
    if (_isVadMode) return; // In VAD auto-mode, PTT is automatic
    if (!_isTransmitting) {
      _isTransmitting = true;
      notifyListeners();
      commPipeline.startTransmission(
        senderId: deviceId,
        languageCode: _selectedLanguage,
        onTranscript: (text) {
          // Live preview or partial transcripts
        },
        onVoiceDetected: (isDetected) {
          _isVoiceDetected = isDetected;
          notifyListeners();
        },
      );
    }
  }

  void onPttReleased() {
    if (_isVadMode) return;
    if (_isTransmitting) {
      _isTransmitting = false;
      _isVoiceDetected = false;
      notifyListeners();
      commPipeline.stopTransmission();
    }
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
