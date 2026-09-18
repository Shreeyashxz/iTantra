import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/network/ble_fallback_transport.dart';
import 'package:itantra_dart/proto/transceiver_packet.dart';

void main() {
  group('BleFallbackTransport Protocol & Chunking Tests', () {
    late BleFallbackTransport transport;

    setUp(() {
      transport = BleFallbackTransport();
    });

    tearDown(() {
      transport.dispose();
    });

    test('BleDiscoveredPeer RSSI to Signal Bars mapping', () {
      final peerStrong = BleDiscoveredPeer(name: 'Node-1', address: 'AA:BB:CC:DD:EE:01', rssi: -50);
      expect(peerStrong.signalBars, equals(4));

      final peerGood = BleDiscoveredPeer(name: 'Node-2', address: 'AA:BB:CC:DD:EE:02', rssi: -65);
      expect(peerGood.signalBars, equals(3));

      final peerFair = BleDiscoveredPeer(name: 'Node-3', address: 'AA:BB:CC:DD:EE:03', rssi: -80);
      expect(peerFair.signalBars, equals(2));

      final peerWeak = BleDiscoveredPeer(name: 'Node-4', address: 'AA:BB:CC:DD:EE:04', rssi: -90);
      expect(peerWeak.signalBars, equals(1));
    });

    test('Single chunk packet (< 176 bytes) produces 1 chunk <= 180 bytes', () {
      final packet = TransceiverPacket(
        senderId: 'ALPHA',
        languageCode: 'hi',
        transcript: 'नमस्ते',
        type: PacketType.voice,
      );

      final chunks = transport.chunkPacket(packet);
      expect(chunks.length, equals(1));
      expect(chunks.first.length, lessThanOrEqualTo(180));

      // Header inspection
      final header = chunks.first;
      expect(header.length, greaterThanOrEqualTo(4));
      // Byte 2: fragment index = 0
      expect(header[2], equals(0));
      // Byte 3: total fragments = 1
      expect(header[3], equals(1));
    });

    test('Multi-chunk packet (> 176 bytes payload) slices cleanly into <= 180 byte chunks', () {
      // Create a large packet with a ~600-byte transcript
      final longTranscript = 'Emergency distress beacon! Location: Sector 4. ' * 12;
      final packet = TransceiverPacket(
        senderId: 'BRAVO_BASE',
        languageCode: 'en',
        transcript: longTranscript,
        type: PacketType.alert,
      );

      final chunks = transport.chunkPacket(packet);
      expect(chunks.length, greaterThan(1));

      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        expect(chunk.length, lessThanOrEqualTo(180));
        // Fragment index
        expect(chunk[2], equals(i));
        // Total fragments
        expect(chunk[3], equals(chunks.length));
      }
    });

    test('Reassembly engine reconstructs in-order chunks with 100% integrity', () async {
      final original = TransceiverPacket(
        senderId: 'STATION_DELTA',
        languageCode: 'mr',
        transcript: 'सकाळचे सत्र सुरू झाले आहे. सर्व पथके सज्ज राहा. ' * 10,
        type: PacketType.alert,
      );

      final chunks = transport.chunkPacket(original);
      expect(chunks.length, greaterThan(1));

      TransceiverPacket? reassembled;
      final sub = transport.incomingPackets.listen((pkt) {
        reassembled = pkt;
      });

      for (final chunk in chunks) {
        transport.receiveGattChunk(chunk);
      }

      await pumpEventQueue();
      await sub.cancel();

      expect(reassembled, isNotNull);
      expect(reassembled!.senderId, equals(original.senderId));
      expect(reassembled!.languageCode, equals(original.languageCode));
      expect(reassembled!.transcript, equals(original.transcript));
      expect(reassembled!.type, equals(original.type));
    });

    test('Reassembly engine handles out-of-order chunks correctly', () async {
      final original = TransceiverPacket(
        senderId: 'OUT_OF_ORDER_TEST',
        languageCode: 'ta',
        transcript: 'மீட்புப் பணி நடைபெற்று வருகிறது. அவசர உதவி தேவைப்படுகிறது. ' * 15,
        type: PacketType.voice,
      );

      final chunks = transport.chunkPacket(original);
      expect(chunks.length, greaterThanOrEqualTo(3));

      TransceiverPacket? reassembled;
      final sub = transport.incomingPackets.listen((pkt) {
        reassembled = pkt;
      });

      // Deliver in reversed order: last chunk first, then second-to-last, etc.
      for (final chunk in chunks.reversed) {
        transport.receiveGattChunk(chunk);
      }

      await pumpEventQueue();
      await sub.cancel();

      expect(reassembled, isNotNull);
      expect(reassembled!.senderId, equals(original.senderId));
      expect(reassembled!.transcript, equals(original.transcript));
      expect(reassembled!.type, equals(original.type));
    });

    test('Stale fragment buffers are pruned by garbage collector', () {
      final packet = TransceiverPacket(
        senderId: 'STALE_TEST',
        languageCode: 'en',
        transcript: 'Short ' * 60,
      );

      final chunks = transport.chunkPacket(packet);
      expect(chunks.length, greaterThan(1));

      // Feed only the first chunk (incomplete packet)
      transport.receiveGattChunk(chunks.first);
      expect(transport.activePendingBuffersCount, equals(1));

      // Force GC cleanup
      transport.cleanStaleBuffers(forceAll: true);
      expect(transport.activePendingBuffersCount, equals(0));
    });

    test('Built-in loopback test executes and verifies pipeline integrity', () async {
      final result = await transport.testLoopback();
      expect(result['success'], isTrue);
      expect(result['chunks'], greaterThan(0));
      expect(result['bytes'], greaterThan(0));
      expect(result['message'], contains('Integrity verified'));
    });

    test('Simulation mode connects simulated peer and emits status', () async {
      expect(transport.isConnected, isFalse);

      String? lastStatus;
      final sub = transport.statusStream.listen((status) {
        lastStatus = status;
      });

      transport.simulatePeerConnected(
        'Simulated-Rescue-Alpha',
        'SIM:00:11:22:33:44',
      );

      await pumpEventQueue();

      expect(transport.isConnected, isTrue);
      expect(transport.connectedPeerName, equals('Simulated-Rescue-Alpha'));
      expect(transport.connectedPeerAddress, equals('SIM:00:11:22:33:44'));
      expect(transport.status, contains('Connected to Simulated-Rescue-Alpha'));
      expect(lastStatus, contains('Connected to Simulated-Rescue-Alpha'));

      transport.disconnect();
      await pumpEventQueue();

      expect(transport.isConnected, isFalse);
      expect(transport.connectedPeerName, isNull);
      expect(transport.status, equals('Disconnected'));

      await sub.cancel();
    });
  });
}
