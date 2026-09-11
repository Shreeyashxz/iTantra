import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/app_database.dart';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';
import '../speech/script_normalization_engine.dart';
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
  static const _hardwareAlertChannel = MethodChannel('com.itantra/hardware_alert');

  final TransceiverManager transceiverManager;
  final SherpaOnnxSpeechEngine speechEngine;
  final AppDatabase? database;

  final _activeAlertController = StreamController<AlertEvent?>.broadcast();
  Stream<AlertEvent?> get activeAlert => _activeAlertController.stream;
  AlertEvent? _currentAlert;
  AlertEvent? get currentAlert => _currentAlert;

  StreamSubscription<TransceiverPacket>? _packetSubscription;

  AlertReceiver({
    required this.transceiverManager,
    required this.speechEngine,
    this.database,
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

    // 1. Android Native Hardware Alarm: Force STREAM_ALARM to max volume + tactile waveform
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _hardwareAlertChannel.invokeMethod('triggerHardwareAlert');
      } catch (e) {
        debugPrint('[AlertReceiver] Hardware alert channel error: $e');
      }
    } else {
      try {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.vibrate();
      } catch (_) {}
    }

    // 2. Configure audio player context for Alarm / Sonification audio stream
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.duckOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AlertReceiver] Error setting alarm audio context: $e');
    }

    // 3. Synthesize distress text at maximum alarm stream volume
    try {
      final settings = await database?.getSettings();
      final engineType = settings?.ttsEngineType ?? 'AI4BHARAT_RASA';
      final gender = settings?.ttsGender ?? 'FEMALE';
      final normalizedText = ScriptNormalizationEngine.prepareTextForTts(
        packet.transcript,
        packet.languageCode,
        engineType,
      );
      await speechEngine.synthesizeSpeech(
        normalizedText,
        packet.languageCode,
        gender,
        engineType,
      );
    } catch (e) {
      debugPrint('[AlertReceiver] Error synthesizing alert speech: $e');
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
