import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../utils/app_permissions.dart';

class AudioRecorderService {
  static final AudioRecorderService _instance = AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  AudioRecorder? _audioRecorder;
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();

  StreamSubscription<List<int>>? _recordSubscription;
  StreamController<Int16List> _pcmStreamController = StreamController<Int16List>.broadcast();

  Stream<Int16List> get pcmStream {
    if (_pcmStreamController.isClosed) {
      _pcmStreamController = StreamController<Int16List>.broadcast();
    }
    return _pcmStreamController.stream;
  }

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
    if (_pcmStreamController.isClosed) {
      _pcmStreamController = StreamController<Int16List>.broadcast();
    }

    try {
      if (_isRecording) {
        _activeClients++;
        return _pcmStreamController.stream;
      }

      // Android 13+: runtime mic grant required — request, don't just check.
      final granted = await AppPermissions.ensureMicrophone();
      if (!granted) {
        debugPrint('[AudioRecorder] Microphone permission denied — not starting');
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
        _activeClients++;
        _carryByte = null;
        await _recordSubscription?.cancel();
        _recordSubscription = stream.listen((byteChunk) {
          if (!_isRecording || _pcmStreamController.isClosed) return;
          final int16List = processPcmChunk(byteChunk);
          if (int16List != null && int16List.isNotEmpty) {
            if (!_pcmStreamController.isClosed) {
              _pcmStreamController.add(int16List);
            }
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
    if (!_isRecording && _recordSubscription == null) return;

    try {
      _isRecording = false;
      _carryByte = null;
      final sub = _recordSubscription;
      _recordSubscription = null;
      await sub?.cancel();
      await _audioRecorder?.stop();
    } catch (e) {
      debugPrint('Error stopping audio recorder: $e');
    }
  }

  Future<void> dispose() async {
    // Singleton teardown — reset refcount first so stop() actually stops.
    _activeClients = 0;
    _carryByte = null;
    _isRecording = false;
    await stopRecording();
    await _audioRecorder?.dispose();
    _audioRecorder = null;
    if (!_pcmStreamController.isClosed) {
      await _pcmStreamController.close();
    }
  }
}
