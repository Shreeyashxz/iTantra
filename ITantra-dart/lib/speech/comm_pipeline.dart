import 'dart:async';
import 'dart:typed_data';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';
import 'audio_recorder_service.dart';
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
  }) async {
    _isTransmitting = true;
    _currentSenderId = senderId;
    _currentLanguageCode = languageCode;
    _onTranscriptCallback = onTranscript;

    final audioStream = await audioRecorder.startRecording();
    final vadStream = vadEngine.startVad(audioStream);
    final textStream = speechEngine.startListening();

    bool isSpeechActive = false;

    _vadSubscription?.cancel();
    _vadSubscription = vadStream.listen((isSpeech) {
      if (isSpeech && !isSpeechActive) {
        // C3: Speech onset — flush pre-speech lookback buffer to avoid clipping first syllable
        for (final frame in vadEngine.lookbackBuffer) {
          speechEngine.feedAudioData(frame);
        }
      }
      isSpeechActive = isSpeech;
    });

    _audioSubscription?.cancel();
    _audioSubscription = audioStream.listen((chunk) {
      // C1: Only feed audio to STT when speech is active (or initial onset buffer)
      if (isSpeechActive) {
        speechEngine.feedAudioData(chunk);
      }
    });

    _sttSubscription?.cancel();
    _sttSubscription = textStream.listen((text) async {
      if (text.trim().isNotEmpty) {
        _onTranscriptCallback?.call(text);
        final packet = TransceiverPacket(
          senderId: senderId,
          languageCode: languageCode,
          transcript: text,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          type: PacketType.voice,
        );
        await transceiverManager.sendPacket(packet);
      }
    });
  }

  Future<void> sendUtterance({
    required String senderId,
    required String languageCode,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    final packet = TransceiverPacket(
      senderId: senderId,
      languageCode: languageCode,
      transcript: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: PacketType.voice,
    );
    await transceiverManager.sendPacket(packet);
  }

  Future<void> stopTransmission() async {
    _isTransmitting = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    await audioRecorder.stopRecording();
    vadEngine.stopVad();

    // Transcribe final buffer using IndicConformer
    final transcript = await speechEngine.stopListeningAndTranscribe();
    if (transcript.isNotEmpty && _currentSenderId != null && _currentLanguageCode != null) {
      _onTranscriptCallback?.call(transcript);
      final packet = TransceiverPacket(
        senderId: _currentSenderId!,
        languageCode: _currentLanguageCode!,
        transcript: transcript,
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
  }

  void dispose() {
    stopTransmission();
  }
}
