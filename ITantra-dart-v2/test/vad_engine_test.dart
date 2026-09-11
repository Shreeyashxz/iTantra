import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/silero_vad_engine.dart';

void main() {
  group('SileroVadEngine Optimization Tests', () {
    late SileroVadEngine vadEngine;

    setUp(() {
      vadEngine = SileroVadEngine(sensitivity: 0.6, sampleRate: 16000);
    });

    tearDown(() {
      vadEngine.release();
    });

    test('Initializes with lookback buffer empty and sensitivity calibrated', () {
      expect(vadEngine.lookbackBuffer, isEmpty);
      expect(vadEngine.sensitivity, 0.6);
      vadEngine.setSensitivity(0.9);
      expect(vadEngine.sensitivity, 0.9);
    });

    test('C3: Lookback ring buffer accumulates recent audio frames without exceeding max', () async {
      final silenceStream = Stream<Int16List>.fromIterable([
        Int16List.fromList(List.filled(320, 10)),
        Int16List.fromList(List.filled(320, 15)),
        Int16List.fromList(List.filled(320, 20)),
        Int16List.fromList(List.filled(320, 25)),
        Int16List.fromList(List.filled(320, 30)),
        Int16List.fromList(List.filled(320, 35)),
        Int16List.fromList(List.filled(320, 40)),
      ]);

      final speechStates = <bool>[];
      final subscription = vadEngine.startVad(silenceStream).listen((isSpeech) {
        speechStates.add(isSpeech);
      });

      // Wait for stream to process
      await Future.delayed(const Duration(milliseconds: 60));
      await subscription.cancel();

      // Lookback buffer should not exceed 5 frames
      expect(vadEngine.lookbackBuffer.length, lessThanOrEqualTo(5));
      expect(vadEngine.lookbackBuffer.isNotEmpty, isTrue);
    });

    test('C2: High energy audio transitions to speech state', () async {
      // Simulate speech frames with high amplitude sinusoidal wave
      final speechFrames = List.generate(10, (_) {
        return Int16List.fromList(List.generate(320, (i) => (i % 2 == 0 ? 12000 : -12000)));
      });

      final audioStream = Stream<Int16List>.fromIterable(speechFrames);
      final results = <bool>[];

      final sub = vadEngine.startVad(audioStream).listen((isSpeech) {
        results.add(isSpeech);
      });

      await Future.delayed(const Duration(milliseconds: 60));
      await sub.cancel();

      // At least one speech onset event should have triggered
      expect(results.contains(true), isTrue);
    });
  });
}
