import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/audio_recorder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioRecorderService - processPcmChunk alignment and carry byte', () {
    late AudioRecorderService recorder;

    setUp(() {
      recorder = AudioRecorderService();
    });

    test('successfully processes unaligned chunks with offset 5 without throwing RangeError', () {
      // Simulate Flutter Platform Channel EventChannel buffer where offset is 5
      final rawBuffer = Uint8List(100);
      // Fill samples: sample 0 = 0x0102, sample 1 = 0x0304
      rawBuffer[5] = 0x02;
      rawBuffer[6] = 0x01;
      rawBuffer[7] = 0x04;
      rawBuffer[8] = 0x03;

      // Sublist view with offsetInBytes == 5
      final unalignedChunk = Uint8List.sublistView(rawBuffer, 5, 9);
      expect(unalignedChunk.offsetInBytes, equals(5));

      // In the old code, this directly threw:
      // RangeError: Offset (5) must be a multiple of BYTES_PER_ELEMENT (2)
      final pcm = recorder.processPcmChunk(unalignedChunk);
      expect(pcm, isNotNull);
      expect(pcm!.length, equals(2));
      expect(pcm[0], equals(0x0102));
      expect(pcm[1], equals(0x0304));
    });

    test('correctly preserves odd trailing byte across chunk boundaries', () {
      // Chunk 1 has 3 bytes (1 full 16-bit sample + 1 trailing odd byte)
      // Sample 0: [0x01, 0x00] -> 1
      // Trailing byte: 0x02
      final chunk1 = Uint8List.fromList([0x01, 0x00, 0x02]);
      final pcm1 = recorder.processPcmChunk(chunk1);
      expect(pcm1, isNotNull);
      expect(pcm1!.length, equals(1));
      expect(pcm1[0], equals(1));

      // Chunk 2 has 3 bytes:
      // High byte of sample 1: 0x00 -> combined with 0x02 gives [0x02, 0x00] -> 2
      // Sample 2: [0x03, 0x00] -> 3
      final chunk2 = Uint8List.fromList([0x00, 0x03, 0x00]);
      final pcm2 = recorder.processPcmChunk(chunk2);
      expect(pcm2, isNotNull);
      expect(pcm2!.length, equals(2));
      expect(pcm2[0], equals(2));
      expect(pcm2[1], equals(3));
    });

    test('handles single-byte chunk followed by another byte', () {
      final chunk1 = Uint8List.fromList([0xAA]);
      final pcm1 = recorder.processPcmChunk(chunk1);
      expect(pcm1, isNull);

      final chunk2 = Uint8List.fromList([0xBB]);
      final pcm2 = recorder.processPcmChunk(chunk2);
      expect(pcm2, isNotNull);
      expect(pcm2!.length, equals(1));
      // In little-endian: 0xAA (low byte) + 0xBB (high byte) = 0xBBAA (signed int16 = -17750)
      final expected = ByteData(2)..setUint8(0, 0xAA)..setUint8(1, 0xBB);
      expect(pcm2[0], equals(expected.getInt16(0, Endian.little)));
    });

    test('handles empty chunk gracefully', () {
      final pcm = recorder.processPcmChunk([]);
      expect(pcm, isNull);
    });
  });
}
