import 'dart:async';
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

  StreamSubscription<String>? _sttSubscription;
  StreamSubscription<bool>? _vadSubscription;
  bool _isTransmitting = false;
  bool get isTransmitting => _isTransmitting;

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
    final audioStream = await audioRecorder.startRecording();
    final vadStream = vadEngine.startVad(audioStream);
    final textStream = speechEngine.startListening();

    _vadSubscription?.cancel();
    _vadSubscription = vadStream.listen((isSpeech) {
      // Gate or log voice activity
    });

    _sttSubscription?.cancel();
    _sttSubscription = textStream.listen((text) async {
      if (text.trim().isNotEmpty) {
        onTranscript?.call(text);
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
    await _sttSubscription?.cancel();
    _sttSubscription = null;
    await _vadSubscription?.cancel();
    _vadSubscription = null;
    await audioRecorder.stopRecording();
    vadEngine.stopVad();
    speechEngine.stopListening();
  }

  void dispose() {
    stopTransmission();
  }
}
