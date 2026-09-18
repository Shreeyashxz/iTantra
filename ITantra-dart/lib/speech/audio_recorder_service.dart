import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _recordSubscription;
  final _pcmStreamController = StreamController<Int16List>.broadcast();

  Stream<Int16List> get pcmStream => _pcmStreamController.stream;
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<Stream<Int16List>> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _isRecording = true;
        _recordSubscription?.cancel();
        _recordSubscription = stream.listen((byteChunk) {
          final alignedLength = byteChunk.length - (byteChunk.length % 2);
          if (alignedLength <= 0) return;
          final uint8List = byteChunk.length == alignedLength
              ? byteChunk
              : Uint8List.sublistView(byteChunk, 0, alignedLength);
          final int16List = Int16List.view(
            uint8List.buffer,
            uint8List.offsetInBytes,
            alignedLength ~/ 2,
          );
          _pcmStreamController.add(int16List);
        });
      }
    } catch (e) {
      debugPrint('Error starting audio recorder stream: $e');
    }
    return _pcmStreamController.stream;
  }

  Future<void> stopRecording() async {
    try {
      _isRecording = false;
      await _recordSubscription?.cancel();
      _recordSubscription = null;
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Error stopping audio recorder: $e');
    }
  }

  void dispose() {
    stopRecording();
    _audioRecorder.dispose();
    _pcmStreamController.close();
  }
}
