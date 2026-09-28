import 'package:flutter/foundation.dart';
import '../speech/comm_pipeline.dart';
import '../speech/sherpa_onnx_speech_engine.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';

class PttManager extends ChangeNotifier {
  final CommPipeline commPipeline;
  final SherpaOnnxSpeechEngine speechEngine;
  final AppDatabase database;

  bool _isTransmitting = false;
  bool get isTransmitting => _isTransmitting;

  bool _isVadMode = false;
  bool get isVadMode => _isVadMode;

  bool _isVoiceDetected = false;
  bool get isVoiceDetected => _isVoiceDetected;

  String? _pttError;
  String? get pttError => _pttError;

  bool _isSttInitializing = false;
  bool get isSttInitializing => _isSttInitializing;

  PttManager({
    required this.commPipeline,
    required this.speechEngine,
    required this.database,
  });

  void setSttInitializing(bool val) {
    _isSttInitializing = val;
    notifyListeners();
  }

  void clearPttError() {
    _pttError = null;
    notifyListeners();
  }

  Future<void> onPttPressed({
    required String deviceId,
    required String selectedLanguage,
  }) async {
    if (_isVadMode) return;
    if (_isTransmitting) return;

    _pttError = null;

    if (!speechEngine.isSttLoaded) {
      debugPrint('[PTT] STT not loaded — attempting on-the-fly init...');
      setSttInitializing(true);
      try {
        final ok = await speechEngine.initStt();
        setSttInitializing(false);
        if (!ok) {
          _pttError = 'STT model not loaded. Download from Settings → Language Packs.';
          notifyListeners();
          return;
        }
      } catch (e) {
        setSttInitializing(false);
        _pttError = 'STT initialization error: $e';
        notifyListeners();
        return;
      }
    }

    _isTransmitting = true;
    notifyListeners();
    debugPrint('[PTT] ▶ Recording started (lang=$selectedLanguage)');

    await commPipeline.startTransmission(
      senderId: deviceId,
      languageCode: selectedLanguage,
      onTranscript: (text) async {
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

  Future<void> onPttReleased({
    required String deviceId,
    required String selectedLanguage,
  }) async {
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
        languageCode: selectedLanguage,
        type: 'VOICE',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isIncoming: false,
      );
      await database.insertMessage(entity);
    } else {
      debugPrint('[PTT] No speech detected — nothing sent');
    }
  }

  void toggleVadMode({
    required String deviceId,
    required String selectedLanguage,
  }) {
    _isVadMode = !_isVadMode;
    if (_isVadMode) {
      commPipeline.startVadAutoMode(
        senderId: deviceId,
        languageCode: selectedLanguage,
        onTranscript: (text) {},
        onVoiceDetected: (isDetected) {
          _isVoiceDetected = isDetected;
          _isTransmitting = commPipeline.isTransmitting;
          notifyListeners();
        },
      );
    } else {
      commPipeline.stopVadAutoMode();
      _isTransmitting = false;
      _isVoiceDetected = false;
    }
    notifyListeners();
  }
}
