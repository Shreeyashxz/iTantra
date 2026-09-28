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

  IncomingPacketHandler({
    required this.transceiverManager,
    required this.database,
    required this.speechEngine,
    required this.transEngine,
  });

  void start(String Function() getSelectedLanguage, bool Function() getIsMtEnabled, String Function() getTtsEngineType) {
    _subscription = transceiverManager.incomingPackets.listen((packet) async {
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
            final selectedLanguage = getSelectedLanguage();
            final isMtEnabled = getIsMtEnabled();
            final ttsEngineType = getTtsEngineType();

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
    });
  }

  void dispose() {
    _subscription?.cancel();
  }
}
