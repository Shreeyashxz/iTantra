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

  bool _disposed = false;

  PttManager({
    required this.commPipeline,
    required this.speechEngine,
    required this.database,
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void setSttInitializing(bool val) {
    _isSttInitializing = val;
    _safeNotify();
  }

  void clearPttError() {
    _pttError = null;
    _safeNotify();
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
        final ok = await speechEngine.initStt().timeout(
          const Duration(seconds: 20),
          onTimeout: () => false,
        );
        setSttInitializing(false);
        if (!ok) {
          _pttError = 'STT model not loaded. Download from Settings → Language Packs.';
          _safeNotify();
          return;
        }
      } catch (e) {
        setSttInitializing(false);
        _pttError = 'STT initialization error: $e';
        _safeNotify();
        return;
      }
    }

    debugPrint('[PTT] ▶ Recording started (lang=$selectedLanguage)');

    try {
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
          _safeNotify();
        },
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      _pttError = 'Could not start microphone: $e';
      _safeNotify();
      return;
    }

    // Only mark transmitting if pipeline actually started (mic permission etc.).
    if (!commPipeline.isTransmitting) {
      _pttError = 'Microphone unavailable — check permission.';
      _safeNotify();
      return;
    }
    _isTransmitting = true;
    _safeNotify();
  }

  Future<void> onPttReleased({
    required String deviceId,
    required String selectedLanguage,
  }) async {
    if (_isVadMode) return;
    if (!_isTransmitting) return;

    _isTransmitting = false;
    _isVoiceDetected = false;
    _safeNotify();
    debugPrint('[PTT] ■ Recording stopped — finalizing STT...');

    String transcript = '';
    try {
      transcript = await commPipeline.stopTransmissionAndGetTranscript().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[PTT] STT finalize timed out');
          return '';
        },
      );
    } catch (e) {
      debugPrint('[PTT] STT finalize error: $e');
    }

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

  Future<void> toggleVadMode({
    required String deviceId,
    required String selectedLanguage,
  }) async {
    _isVadMode = !_isVadMode;
    if (_isVadMode) {
      try {
        await commPipeline.startVadAutoMode(
          senderId: deviceId,
          languageCode: selectedLanguage,
          onTranscript: (text) {},
          onVoiceDetected: (isDetected) {
            _isVoiceDetected = isDetected;
            _isTransmitting = commPipeline.isTransmitting;
            _safeNotify();
          },
        );
      } catch (e) {
        _isVadMode = false;
        _pttError = 'Could not start hands-free mode: $e';
      }
    } else {
      try {
        await commPipeline.stopVadAutoMode();
      } catch (_) {}
      _isTransmitting = false;
      _isVoiceDetected = false;
    }
    _safeNotify();
  }
}
