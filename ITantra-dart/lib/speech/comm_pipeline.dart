import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';
import 'audio_recorder_service.dart';
import 'script_normalization_engine.dart';
import 'sherpa_onnx_speech_engine.dart';
import 'vad_engine.dart';

class CommPipeline {
  final AudioRecorderService audioRecorder;
  final VadEngine vadEngine;
  final SherpaOnnxSpeechEngine speechEngine;
  final TransceiverManager transceiverManager;

  StreamSubscription<Int16List>? _audioSubscription;
  StreamSubscription<String>? _sttSubscription;
  StreamSubscription<bool>? _vadSubscription;
  bool _isTransmitting = false;
  bool get isTransmitting => _isTransmitting;

  String? _currentSenderId;
  String? _currentLanguageCode;
  void Function(String)? _onTranscriptCallback;
  void Function(bool isVoiceDetected)? _onVoiceDetectedCallback;

  bool _isVoiceDetected = false;
  bool get isVoiceDetected => _isVoiceDetected;

  bool _isVadAutoMode = false;
  bool get isVadAutoMode => _isVadAutoMode;
  Timer? _vadSilenceTimer;
  int _vadGeneration = 0;
  bool _hasActiveUtterance = false;

  CommPipeline({
    required this.audioRecorder,
    required this.vadEngine,
    required this.speechEngine,
    required this.transceiverManager,
  });

  Future<void> startTransmission({
    required String senderId,
    required String languageCode,
    void Function(String partialText)? onTranscript,
    void Function(bool isVoiceDetected)? onVoiceDetected,
  }) async {
    if (_isTransmitting) return; // guard double-start (PTT bounce)
    if (_isVadAutoMode) {
      debugPrint('[CommPipeline] Refusing PTT while VAD auto-mode active');
      return;
    }
    // Guard: ensure STT model is initialized before starting mic
    if (!speechEngine.isSttLoaded) {
      debugPrint('[CommPipeline] STT not loaded — attempting auto-init before transmission...');
      final ok = await speechEngine.initStt();
      if (!ok) {
        debugPrint('[CommPipeline] ABORT: Cannot start transmission without STT model');
        return;
      }
    }

    _isTransmitting = true;
    _currentSenderId = senderId;
    _currentLanguageCode = languageCode;
    _onTranscriptCallback = onTranscript;
    _onVoiceDetectedCallback = onVoiceDetected;

    final audioStream = await audioRecorder.startRecording();
    // If mic permission denied, recorder returns a dead stream — abort cleanly.
    if (!audioRecorder.isRecording) {
      debugPrint('[CommPipeline] ABORT: microphone not recording (permission?)');
      _isTransmitting = false;
      return;
    }
    final vadStream = vadEngine.startVad(audioStream);
    final textStream = speechEngine.startListening(languageCode);

    bool isSpeechActive = false;

    await _vadSubscription?.cancel();
    _vadSubscription = vadStream.listen((isSpeech) {
      _isVoiceDetected = isSpeech;
      _onVoiceDetectedCallback?.call(isSpeech);

      if (isSpeech && !isSpeechActive) {
        // C3: Speech onset — flush pre-speech lookback buffer to avoid clipping first syllable
        for (final frame in vadEngine.lookbackBuffer) {
          speechEngine.feedAudioData(frame);
        }
      }
      isSpeechActive = isSpeech;
    });

    await _audioSubscription?.cancel();
    _audioSubscription = audioStream.listen((chunk) {
      // C1: Only feed audio to STT when speech is active (or initial onset buffer)
      if (isSpeechActive) {
        speechEngine.feedAudioData(chunk);
      }
    });

    await _sttSubscription?.cancel();
    _sttSubscription = textStream.listen((text) {
      if (text.trim().isNotEmpty) {
        final normalizedText = ScriptNormalizationEngine.normalizeFromStt(text, languageCode);
        _onTranscriptCallback?.call(normalizedText);
      }
    });
  }


  Future<void> sendUtterance({
    required String senderId,
    required String languageCode,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    final normalizedText = ScriptNormalizationEngine.normalizeFromStt(text, languageCode);
    final packet = TransceiverPacket(
      senderId: senderId,
      languageCode: languageCode,
      transcript: normalizedText,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: PacketType.voice,
    );
    await transceiverManager.sendPacket(packet);
  }

  /// Stops transmission and returns the final transcript (for the controller to save to DB).
  Future<String> stopTransmissionAndGetTranscript() async {
    if (!_isTransmitting && _audioSubscription == null && _vadSubscription == null) {
      return '';
    }
    _isTransmitting = false;
    _isVoiceDetected = false;
    _onVoiceDetectedCallback?.call(false);

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    await audioRecorder.stopRecording();
    vadEngine.stopVad();

    // Transcribe final buffer using IndicConformer
    final transcript = await speechEngine.stopListeningAndTranscribe(_currentLanguageCode);
    String normalizedTranscript = '';
    if (transcript.isNotEmpty && _currentSenderId != null && _currentLanguageCode != null) {
      normalizedTranscript = ScriptNormalizationEngine.normalizeFromStt(transcript, _currentLanguageCode!);
      _onTranscriptCallback?.call(normalizedTranscript);
      final packet = TransceiverPacket(
        senderId: _currentSenderId!,
        languageCode: _currentLanguageCode!,
        transcript: normalizedTranscript,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        type: PacketType.voice,
      );
      await transceiverManager.sendPacket(packet);
    }

    await _sttSubscription?.cancel();
    _sttSubscription = null;
    _currentSenderId = null;
    _currentLanguageCode = null;
    _onTranscriptCallback = null;

    return normalizedTranscript;
  }



  /// Starts Hands-Free VAD Auto-Mode:
  /// Continuously monitors microphone with Silero VAD; automatically records upon speech
  /// detection and finalizes/transmits upon 1.2s silence without requiring PTT button presses.
  Future<void> startVadAutoMode({
    required String senderId,
    required String languageCode,
    void Function(String partialText)? onTranscript,
    void Function(bool isVoiceDetected)? onVoiceDetected,
  }) async {
    if (_isVadAutoMode) return;
    if (_isTransmitting) {
      debugPrint('[CommPipeline] Refusing VAD auto-mode while PTT active');
      return;
    }
    _isVadAutoMode = true;
    _currentSenderId = senderId;
    _currentLanguageCode = languageCode;
    _onTranscriptCallback = onTranscript;
    _onVoiceDetectedCallback = onVoiceDetected;

    final audioStream = await audioRecorder.startRecording();
    if (!audioRecorder.isRecording) {
      debugPrint('[CommPipeline] VAD auto-mode ABORT: mic not recording');
      _isVadAutoMode = false;
      return;
    }
    final vadStream = vadEngine.startVad(audioStream);

    await _vadSubscription?.cancel();
    _vadSubscription = vadStream.listen((isSpeech) async {
      _isVoiceDetected = isSpeech;
      _onVoiceDetectedCallback?.call(isSpeech);

      if (isSpeech) {
        _vadSilenceTimer?.cancel();
        _vadSilenceTimer = null;

        if (!_hasActiveUtterance) {
          _hasActiveUtterance = true;
          _isTransmitting = true;
          speechEngine.startListening(languageCode);
          for (final frame in vadEngine.lookbackBuffer) {
            speechEngine.feedAudioData(frame);
          }
        }
      } else {
        if (_hasActiveUtterance && _vadSilenceTimer == null) {
          final gen = _vadGeneration;
          _vadSilenceTimer = Timer(const Duration(milliseconds: 1200), () async {
            // Stale timer (stopVadAutoMode bumped generation) — ignore.
            if (gen != _vadGeneration || !_hasActiveUtterance) return;
            _hasActiveUtterance = false;
            _isTransmitting = false;

            final transcript = await speechEngine.stopListeningAndTranscribe(_currentLanguageCode);
            // Double-check generation after async gap — stop may have raced us.
            if (gen != _vadGeneration) return;
            if (transcript.trim().isNotEmpty && _currentSenderId != null && _currentLanguageCode != null) {
              final normalized = ScriptNormalizationEngine.normalizeFromStt(transcript, _currentLanguageCode!);
              _onTranscriptCallback?.call(normalized);
              final packet = TransceiverPacket(
                senderId: _currentSenderId!,
                languageCode: _currentLanguageCode!,
                transcript: normalized,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
                type: PacketType.voice,
              );
              await transceiverManager.sendPacket(packet);
            }
          });
        }
      }
    });

    await _audioSubscription?.cancel();
    _audioSubscription = audioStream.listen((chunk) {
      if (_hasActiveUtterance) {
        speechEngine.feedAudioData(chunk);
      }
    });
  }

  Future<void> stopVadAutoMode() async {
    _vadGeneration++; // invalidates any queued silence timer
    _isVadAutoMode = false;
    _hasActiveUtterance = false;
    _isTransmitting = false;
    _isVoiceDetected = false;
    _vadSilenceTimer?.cancel();
    _vadSilenceTimer = null;
    _onVoiceDetectedCallback?.call(false);

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    await audioRecorder.stopRecording();
    vadEngine.stopVad();
    speechEngine.stopListening();
  }

  Future<void> dispose() async {
    await stopTransmissionAndGetTranscript();
    await stopVadAutoMode();
    await _sttSubscription?.cancel();
    _sttSubscription = null;
    _onTranscriptCallback = null;
    _onVoiceDetectedCallback = null;
  }
}
