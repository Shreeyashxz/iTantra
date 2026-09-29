import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../alerts/alert_broadcaster.dart';
import '../alerts/alert_receiver.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';
import '../data/entities/user_settings_entity.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_mesh_manager.dart';

import '../speech/comm_pipeline.dart';
import '../speech/indic_trans_engine.dart';
import '../speech/indic_xlit_engine.dart';
import '../speech/neural_xlit_engine.dart';
import '../speech/script_normalization_engine.dart';
import '../speech/sherpa_onnx_speech_engine.dart';
import 'ptt_manager.dart';
import 'incoming_packet_handler.dart';

class TransceiverController extends ChangeNotifier {
  final CommPipeline commPipeline;
  final TransceiverManager transceiverManager;
  final WifiMeshManager meshManager;
  final AlertBroadcaster alertBroadcaster;
  final AlertReceiver alertReceiver;
  final SherpaOnnxSpeechEngine speechEngine;
  final AppDatabase database;
  final IndicTransEngine transEngine = IndicTransEngine();

  late final PttManager _pttManager;
  late final IncomingPacketHandler _incomingPacketHandler;

  late String deviceId;
  List<MessageEntity> _messages = [];
  List<MessageEntity> get messages => _messages;

  AlertEvent? _activeAlert;
  AlertEvent? get activeAlert => _activeAlert;

  String _connectionStatus = 'Disconnected';
  String get connectionStatus => _connectionStatus;

  String _selectedLanguage = 'hi';
  String get selectedLanguage => _selectedLanguage;

  bool _isMtEnabled = true;
  bool get isMtEnabled => _isMtEnabled;

  int? get linkRttMs => transceiverManager.averageRttMs;

  bool get isSttReady => speechEngine.isSttLoaded;

  // --- Delegated PTT properties ---
  bool get isTransmitting => _pttManager.isTransmitting;
  bool get isVadMode => _pttManager.isVadMode;
  bool get isVoiceDetected => _pttManager.isVoiceDetected;
  String? get pttError => _pttManager.pttError;
  bool get isSttInitializing => _pttManager.isSttInitializing;

  String _ttsEngineType = 'AI4BHARAT_RASA';
  String get ttsEngineType => _ttsEngineType;
  bool get isRasa => _ttsEngineType == 'AI4BHARAT_RASA';
  bool get isOsNative => _ttsEngineType == 'OS_NATIVE';
  bool get isRasaUnsupportedForSelectedLang =>
      const {'gu', 'or', 'en'}.contains(_selectedLanguage.toLowerCase());

  Future<void> toggleTtsEngine() async {
    if (_ttsEngineType == 'AI4BHARAT_RASA') {
      _ttsEngineType = 'META_MMS';
    } else if (_ttsEngineType == 'META_MMS') {
      _ttsEngineType = 'OS_NATIVE';
    } else {
      _ttsEngineType = 'AI4BHARAT_RASA';
    }
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

  String _normalizerMode = 'ADVANCED';
  String get normalizerMode => _normalizerMode;
  bool get isAdvancedNormalizer => _normalizerMode == 'ADVANCED';
  bool get isLegacyNormalizer => _normalizerMode == 'LEGACY_RULE_BASED';
  bool get isNeuralIndicXlit => _normalizerMode == 'NEURAL_INDIC_XLIT';
  String get xlitStatusLabel => IndicXlitEngine.instance.statusLabel;
  bool get isXlitNeural => IndicXlitEngine.instance.isNeuralActive;

  /// Direct set (used by pipeline diagram force switches).
  Future<void> setNormalizerMode(String mode) async {
    final leavingNeural = _normalizerMode == 'NEURAL_INDIC_XLIT' && mode != 'NEURAL_INDIC_XLIT';
    _normalizerMode = mode;
    ScriptNormalizationEngine.setModeFromString(_normalizerMode);
    if (mode == 'NEURAL_INDIC_XLIT') {
      final neural = await IndicXlitEngine.instance.ensureReady();
      debugPrint('[TransceiverController] Xlit ready (neural=$neural): ${IndicXlitEngine.instance.statusLabel}');
    } else if (leavingNeural) {
      // Second ORT session is ~120MB — never hold it while another mode is active.
      await NeuralXlitEngine.instance.unload();
    }
    notifyListeners();
    try {
      final settings = await database.getSettings();
      await database.saveSettings(settings.copyWith(normalizerMode: _normalizerMode));
    } catch (e) {
      debugPrint('[TransceiverController] Error saving normalizer mode: $e');
    }
  }

  Future<void> toggleNormalizerMode() async {
    String next;
    if (isAdvancedNormalizer) {
      next = 'LEGACY_RULE_BASED';
    } else if (isLegacyNormalizer) {
      next = 'NEURAL_INDIC_XLIT';
    } else {
      next = 'ADVANCED';
    }
    _normalizerMode = next;
    ScriptNormalizationEngine.setModeFromString(_normalizerMode);
    // Toggle-on: initialize Xlit so it works immediately (neural if bundle
    // present, otherwise offline rule-based fallback — no download required).
    if (next == 'NEURAL_INDIC_XLIT') {
      final neural = await IndicXlitEngine.instance.ensureReady();
      debugPrint('[TransceiverController] Xlit ready (neural=$neural): ${IndicXlitEngine.instance.statusLabel}');
    }
    notifyListeners();
    try {
      final settings = await database.getSettings();
      await database.saveSettings(settings.copyWith(normalizerMode: _normalizerMode));
      debugPrint('[TransceiverController] Normalizer Mode switched to: $_normalizerMode');
    } catch (e) {
      debugPrint('[TransceiverController] Error saving normalizer mode switch: $e');
    }
  }

  StreamSubscription<AlertEvent?>? _alertSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<List<MessageEntity>>? _dbSubscription;
  StreamSubscription<dynamic>? _statsSubscription;
  StreamSubscription<UserSettingsEntity>? _settingsSubscription;

  TransceiverController({
    required this.commPipeline,
    required this.transceiverManager,
    required this.meshManager,
    required this.alertBroadcaster,
    required this.alertReceiver,
    required this.speechEngine,
    required this.database,
  }) {
    deviceId = 'DEV_${const Uuid().v4().substring(0, 8).toUpperCase()}'; // Fallback until async init completes
    _connectionStatus = transceiverManager.currentStatusString;
    _pttManager = PttManager(commPipeline: commPipeline, speechEngine: speechEngine, database: database);
    _pttManager.addListener(_onPttChanged);
    _incomingPacketHandler = IncomingPacketHandler(transceiverManager: transceiverManager, database: database, speechEngine: speechEngine, transEngine: transEngine);
    _init();
  }

  void _onPttChanged() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  Future<void> _init() async {
    // Load settings including MT preference and TTS engine type
    final initialSettings = await database.getSettings();
    if (initialSettings.deviceId.isEmpty) {
      deviceId = 'DEV_${const Uuid().v4().substring(0, 8).toUpperCase()}';
      await database.saveSettings(initialSettings.copyWith(deviceId: deviceId));
    } else {
      deviceId = initialSettings.deviceId;
    }
    
    _selectedLanguage = initialSettings.preferredLanguage;
    _isMtEnabled = initialSettings.isMtEnabled;
    _ttsEngineType = initialSettings.ttsEngineType;
    _normalizerMode = initialSettings.normalizerMode;
    ScriptNormalizationEngine.setModeFromString(_normalizerMode);
    if (_normalizerMode == 'NEURAL_INDIC_XLIT') {
      // Persisted toggle (restart): Xlit must work without re-toggling.
      IndicXlitEngine.instance.ensureReady();
    }

    _messages = await database.getAllMessages();
    notifyListeners();

    _settingsSubscription = database.settingsStream.listen((settings) {
      bool changed = false;
      if (_selectedLanguage != settings.preferredLanguage) {
        _selectedLanguage = settings.preferredLanguage;
        changed = true;
      }
      if (_isMtEnabled != settings.isMtEnabled) {
        _isMtEnabled = settings.isMtEnabled;
        changed = true;
      }
      if (_ttsEngineType != settings.ttsEngineType) {
        _ttsEngineType = settings.ttsEngineType;
        changed = true;
      }
      if (_normalizerMode != settings.normalizerMode) {
        _normalizerMode = settings.normalizerMode;
        ScriptNormalizationEngine.setModeFromString(_normalizerMode);
        if (_normalizerMode == 'NEURAL_INDIC_XLIT') {
          IndicXlitEngine.instance.ensureReady();
        }
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    }, onError: (e) {
      debugPrint('[TransceiverController] Error in settingsStream: $e');
    });

    try {
      debugPrint('[TransceiverController] Auto-starting mesh beacon service on startup...');
      unawaited(meshManager.startBeaconService(
        customNodeName: 'iTantra Node ($deviceId)',
      ));
    } catch (e) {
      debugPrint('[TransceiverController] Beacon service start notice: $e');
    }

    _pttManager.setSttInitializing(true);
    try {
      final sttOk = await speechEngine.initStt();
      debugPrint('[TransceiverController] STT auto-init: ${sttOk ? "SUCCESS" : "FAILED (models not downloaded?)"}');
    } catch (e) {
      debugPrint('[TransceiverController] STT auto-init error: $e');
    }
    _pttManager.setSttInitializing(false);

    // Start incoming packet processor
    _incomingPacketHandler.start(() => _selectedLanguage, () => _isMtEnabled, () => _ttsEngineType);

    unawaited(
      database.getSettings().then((settings) {
        speechEngine.initTts(_selectedLanguage, _ttsEngineType);
      }).catchError((e) {
        debugPrint('[TransceiverController] Startup warm-up ignored: $e');
      }),
    );

    _alertSubscription = alertReceiver.activeAlert.listen((alert) {
      _activeAlert = alert;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TransceiverController] Error in activeAlert stream: $e');
    });

    _statusSubscription = transceiverManager.connectionState.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TransceiverController] Error in connectionState stream: $e');
    });

    _dbSubscription = database.messagesStream.listen((list) {
      _messages = list;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TransceiverController] Error in messagesStream: $e');
    });

    _statsSubscription = transceiverManager.statsStream.listen((_) {
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TransceiverController] Error in statsStream: $e');
    });
  }

  // --- Delegated PTT Actions ---
  Future<void> onPttPressed() => _pttManager.onPttPressed(deviceId: deviceId, selectedLanguage: _selectedLanguage);
  Future<void> onPttReleased() => _pttManager.onPttReleased(deviceId: deviceId, selectedLanguage: _selectedLanguage);
  void clearPttError() => _pttManager.clearPttError();
  void toggleVadMode() {
    // Fire-and-forget is intentional for UI tap; errors surface via pttError.
    _pttManager.toggleVadMode(deviceId: deviceId, selectedLanguage: _selectedLanguage);
  }

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
  }

  Future<void> setLanguage(String code) async {
    if (_selectedLanguage != code) {
      _selectedLanguage = code;
      notifyListeners();
      try {
        final s = await database.getSettings();
        await database.saveSettings(s.copyWith(preferredLanguage: code));
      } catch (e) {
        debugPrint('[TransceiverController] Error saving language setting: $e');
      }
    }
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
  }

  void dismissAlert() {
    _activeAlert = null;
    alertReceiver.dismissAlert();
    if (!_disposed) notifyListeners();
  }

  void startPeerDiscovery() {
    meshManager.probeSubnet();
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _pttManager.removeListener(_onPttChanged);
    } catch (_) {}
    try {
      _pttManager.removeListener(notifyListeners);
    } catch (_) {}
    try {
      _incomingPacketHandler.dispose();
    } catch (_) {}
    try {
      _pttManager.dispose();
    } catch (_) {}
    _alertSubscription?.cancel();
    _statusSubscription?.cancel();
    _dbSubscription?.cancel();
    _statsSubscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }
}
