import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';
import '../speech/indic_trans_engine.dart';
import '../speech/script_normalization_engine.dart';
import '../speech/sherpa_onnx_speech_engine.dart';

class IncomingPacketHandler {
  final TransceiverManager transceiverManager;
  final AppDatabase database;
  final SherpaOnnxSpeechEngine speechEngine;
  final IndicTransEngine transEngine;

  StreamSubscription<TransceiverPacket>? _subscription;
  // Dedup across Wi-Fi + BLE dual delivery (packetId, fallback sender|time).
  final Set<String> _seenKeys = {};
  static const int _maxSeen = 500;
  // Serialize inbound TTS so bursts don't overlap/cut each other.
  Future<void> _chain = Future.value();

  IncomingPacketHandler({
    required this.transceiverManager,
    required this.database,
    required this.speechEngine,
    required this.transEngine,
  });

  void start(String Function() getSelectedLanguage, bool Function() getIsMtEnabled, String Function() getTtsEngineType) {
    _getSelectedLanguage = getSelectedLanguage;
    _getIsMtEnabled = getIsMtEnabled;
    _getTtsEngineType = getTtsEngineType;
    _subscription = transceiverManager.incomingPackets.listen((packet) {
      // Chain: one packet at a time, no interleave.
      final prev = _chain;
      _chain = prev.then((_) => _handle(packet)).catchError((e) {
        debugPrint('[IncomingPacketHandler] chained error: $e');
      });
    });
  }

  String Function()? _getSelectedLanguage;
  bool Function()? _getIsMtEnabled;
  String Function()? _getTtsEngineType;

  Future<void> _handle(TransceiverPacket packet) async {
      // Dedup first — before DB insert and TTS.
      final key = packet.dedupKey;
      if (_seenKeys.contains(key)) return;
      _seenKeys.add(key);
      if (_seenKeys.length > _maxSeen) {
        _seenKeys.remove(_seenKeys.first);
      }
      try {
        final entity = MessageEntity(
          senderId: packet.senderId,
          text: packet.transcript,
          languageCode: packet.languageCode,
          type: packet.type.name.toUpperCase(),
          timestamp: packet.timestampMs,
          isIncoming: true,
        );
        await database.insertMessage(entity);

        if (packet.type == PacketType.voice) {
          final settings = await database.getSettings();
          if (settings.autoPlayAudio) {
            String textToSpeak = packet.transcript;
            final selectedLanguage = _getSelectedLanguage?.call() ?? packet.languageCode;
            final isMtEnabled = _getIsMtEnabled?.call() ?? false;
            final ttsEngineType = _getTtsEngineType?.call() ?? 'META_MMS';

            final String speechLang = (isMtEnabled && packet.languageCode != selectedLanguage)
                ? selectedLanguage
                : packet.languageCode;

            final ttsWarmUp = speechEngine.initTts(speechLang, ttsEngineType);

            if (isMtEnabled && packet.languageCode != selectedLanguage) {
              try {
                final translationFuture = transEngine.translate(
                  text: packet.transcript,
                  sourceLang: packet.languageCode,
                  targetLang: selectedLanguage,
                );
                final results = await Future.wait([translationFuture, ttsWarmUp]);
                textToSpeak = results[0] as String;
              } catch (e) {
                debugPrint('[IncomingPacketHandler] MT translation error: $e');
                await ttsWarmUp;
              }
            } else {
              await ttsWarmUp;
            }

            textToSpeak = ScriptNormalizationEngine.prepareTextForTts(
              textToSpeak,
              speechLang,
              ttsEngineType,
            );

            await speechEngine.synthesizeSpeech(
              textToSpeak,
              speechLang,
              settings.ttsGender,
              ttsEngineType,
            );
          }
        }
      } catch (e) {
        debugPrint('[IncomingPacketHandler] Error handling incoming packet: $e');
      }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
