import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  static final AudioRecorderService _instance = AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  AudioRecorder? _audioRecorder;
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();

  StreamSubscription<List<int>>? _recordSubscription;
  final _pcmStreamController = StreamController<Int16List>.broadcast();

  Stream<Int16List> get pcmStream => _pcmStreamController.stream;
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  
  int _activeClients = 0;
  int? _carryByte;

  @visibleForTesting
  Int16List? processPcmChunk(List<int> byteChunk) {
    if (byteChunk.isEmpty) return null;

    final Uint8List bytes;
    if (_carryByte != null) {
      bytes = Uint8List(byteChunk.length + 1);
      bytes[0] = _carryByte!;
      bytes.setRange(1, bytes.length, byteChunk);
      _carryByte = null;
    } else {
      // Uint8List.fromList creates a fresh Uint8List whose buffer is guaranteed
      // to start at byte offset 0. This prevents `RangeError: Offset (5) must be a multiple of BYTES_PER_ELEMENT (2)`
      // caused by Flutter platform channels providing sublist views into message buffers with odd offsets.
      bytes = Uint8List.fromList(byteChunk);
    }

    final sampleCount = bytes.length ~/ 2;
    if (sampleCount <= 0) {
      if (bytes.length == 1) {
        _carryByte = bytes[0];
      }
      return null;
    }

    if (bytes.length % 2 != 0) {
      _carryByte = bytes[bytes.length - 1];
    }

    return Int16List.view(
      bytes.buffer,
      0,
      sampleCount,
    );
  }

  Future<Stream<Int16List>> startRecording() async {
    _activeClients++;
    try {
      if (_isRecording) {
        return _pcmStreamController.stream;
      }

      final recorder = _recorder;
      if (await recorder.hasPermission()) {
        final stream = await recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _isRecording = true;
        _carryByte = null;
        _recordSubscription?.cancel();
        _recordSubscription = stream.listen((byteChunk) {
          final int16List = processPcmChunk(byteChunk);
          if (int16List != null && int16List.isNotEmpty) {
            _pcmStreamController.add(int16List);
          }
        });
      }
    } catch (e) {
      debugPrint('Error starting audio recorder stream: $e');
    }
    return _pcmStreamController.stream;
  }

  Future<void> stopRecording() async {
    if (_activeClients > 0) _activeClients--;
    if (_activeClients > 0) return; // Keep recording for other active clients

    try {
      _isRecording = false;
      _carryByte = null;
      await _recordSubscription?.cancel();
      _recordSubscription = null;
      await _audioRecorder?.stop();
    } catch (e) {
      debugPrint('Error stopping audio recorder: $e');
    }
  }

  void dispose() {
    // Singleton, so we only clean up if explicitly commanded by app teardown
    _activeClients = 0;
    _carryByte = null;
    stopRecording();
    _audioRecorder?.dispose();
    _audioRecorder = null;
    _pcmStreamController.close();
  }
}
