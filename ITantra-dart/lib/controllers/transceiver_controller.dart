import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../alerts/alert_broadcaster.dart';
import '../alerts/alert_receiver.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_direct_manager.dart';
import '../proto/transceiver_packet.dart';
import '../speech/comm_pipeline.dart';
import '../speech/sherpa_onnx_speech_engine.dart';

class TransceiverController extends ChangeNotifier {
  final CommPipeline commPipeline;
  final TransceiverManager transceiverManager;
  final WifiDirectManager wifiDirectManager;
  final AlertBroadcaster alertBroadcaster;
  final AlertReceiver alertReceiver;
  final SherpaOnnxSpeechEngine speechEngine;
  final AppDatabase database;

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

  StreamSubscription<TransceiverPacket>? _packetSubscription;
  StreamSubscription<AlertEvent?>? _alertSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<List<MessageEntity>>? _dbSubscription;

  TransceiverController({
    required this.commPipeline,
    required this.transceiverManager,
    required this.wifiDirectManager,
    required this.alertBroadcaster,
    required this.alertReceiver,
    required this.speechEngine,
    required this.database,
  }) {
    deviceId = 'DEV_${Random().nextInt(90000) + 10000}';
    _init();
  }

  Future<void> _init() async {
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
        await speechEngine.synthesizeSpeech(packet.transcript, packet.languageCode);
      }
    });

    // Listen for alerts
    _alertSubscription = alertReceiver.activeAlert.listen((alert) {
      _activeAlert = alert;
      notifyListeners();
    });

    // Listen for connection status changes
    _statusSubscription = wifiDirectManager.connectionStatus.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    // Listen for database updates
    _dbSubscription = database.messagesStream.listen((list) {
      _messages = list;
      notifyListeners();
    });
  }

  void onPttPressed() {
    if (!_isTransmitting) {
      _isTransmitting = true;
      notifyListeners();
      commPipeline.startTransmission(
        senderId: deviceId,
        languageCode: _selectedLanguage,
        onTranscript: (text) {
          // Live preview or partial transcripts
        },
      );
    }
  }

  void onPttReleased() {
    if (_isTransmitting) {
      _isTransmitting = false;
      notifyListeners();
      commPipeline.stopTransmission();
    }
  }

  /// Sends a simulated or manual voice utterance through the transceiver pipeline
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

  Future<void> sendEmergencyAlert(String alertText) async {
    await alertBroadcaster.broadcastAlert(
      senderId: deviceId,
      languageCode: _selectedLanguage,
      alertText: alertText,
    );

    final entity = MessageEntity(
      senderId: deviceId,
      text: alertText,
      languageCode: _selectedLanguage,
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
    wifiDirectManager.startDiscovery();
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    _alertSubscription?.cancel();
    _statusSubscription?.cancel();
    _dbSubscription?.cancel();
    super.dispose();
  }
}
