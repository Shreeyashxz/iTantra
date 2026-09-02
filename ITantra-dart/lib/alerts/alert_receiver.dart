import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';
import '../speech/sherpa_onnx_speech_engine.dart';

class AlertEvent {
  final String senderId;
  final String text;
  final String languageCode;
  final int timestampMs;

  const AlertEvent({
    required this.senderId,
    required this.text,
    required this.languageCode,
    required this.timestampMs,
  });
}

class AlertReceiver {
  final TransceiverManager transceiverManager;
  final SherpaOnnxSpeechEngine speechEngine;

  final _activeAlertController = StreamController<AlertEvent?>.broadcast();
  Stream<AlertEvent?> get activeAlert => _activeAlertController.stream;
  AlertEvent? _currentAlert;
  AlertEvent? get currentAlert => _currentAlert;

  StreamSubscription<TransceiverPacket>? _packetSubscription;

  AlertReceiver({
    required this.transceiverManager,
    required this.speechEngine,
  }) {
    _startListening();
  }

  void _startListening() {
    _packetSubscription?.cancel();
    _packetSubscription = transceiverManager.incomingPackets.listen((packet) {
      if (packet.type == PacketType.alert) {
        _handleIncomingAlert(packet);
      }
    });
  }

  Future<void> _handleIncomingAlert(TransceiverPacket packet) async {
    final event = AlertEvent(
      senderId: packet.senderId,
      text: packet.transcript,
      languageCode: packet.languageCode,
      timestampMs: packet.timestampMs,
    );
    _currentAlert = event;
    _activeAlertController.add(event);

    // 1. High-intensity tactile / vibration alert
    try {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.vibrate();
    } catch (_) {}

    // 2. Synthesize distress text at maximum volume
    try {
      await speechEngine.synthesizeSpeech(packet.transcript, packet.languageCode);
    } catch (e) {
      debugPrint('Error synthesizing alert speech: $e');
    }
  }

  void dismissAlert() {
    _currentAlert = null;
    _activeAlertController.add(null);
    speechEngine.stopSpeech();
  }

  void dispose() {
    _packetSubscription?.cancel();
    _activeAlertController.close();
  }
}
