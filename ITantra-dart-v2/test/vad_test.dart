import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/silero_vad_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SileroVadEngine Verification Tests', () {
    test('Detects speech vs silence and maintains lookback buffer', () async {
      final vad = SileroVadEngine(
        sensitivity: 0.7,
        minSilenceDuration: 0.3,
        minSpeechDuration: 0.1,
      );

      // Generate 16kHz audio: 30ms = 480 samples
      const chunkSize = 480;

      // 1. Generate silence chunks (RMS near 0)
      final silenceChunk = Int16List(chunkSize);
      for (int i = 0; i < chunkSize; i++) {
        silenceChunk[i] = (Random().nextDouble() * 40 - 20).toInt(); // Low noise floor
      }

      // 2. Generate loud voiced speech chunk (16-bit sine wave representing voice)
      final speechChunk = Int16List(chunkSize);
      for (int i = 0; i < chunkSize; i++) {
        speechChunk[i] = (sin(2 * pi * 250 * i / 16000) * 12000).toInt(); // 250Hz voice pitch
      }

      final detectedStates = <bool>[];
      final stream = vad.startVad(Stream.fromIterable([
        // 5 frames of silence (~150ms)
        silenceChunk, silenceChunk, silenceChunk, silenceChunk, silenceChunk,
        // 8 frames of speech (~240ms)
        speechChunk, speechChunk, speechChunk, speechChunk,
        speechChunk, speechChunk, speechChunk, speechChunk,
        // 12 frames of silence (~360ms)
        silenceChunk, silenceChunk, silenceChunk, silenceChunk,
        silenceChunk, silenceChunk, silenceChunk, silenceChunk,
        silenceChunk, silenceChunk, silenceChunk, silenceChunk,
      ]));

      final sub = stream.listen((isSpeech) {
        detectedStates.add(isSpeech);
      });

      await Future.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      // Verify VAD transitioned: silence -> speech detected (true) -> silence stoppage detected (false)
      expect(detectedStates.contains(true), isTrue, reason: 'VAD must detect voice onset');
      expect(detectedStates.last, isFalse, reason: 'VAD must detect speech stoppage / pause');
      expect(vad.lookbackBuffer.isNotEmpty, isTrue, reason: 'Lookback buffer must preserve onset frames');

      vad.release();
    });
  });
}
