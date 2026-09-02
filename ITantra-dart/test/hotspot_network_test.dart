import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/network/hotspot_network_manager.dart';
import 'package:itantra_dart/network/transceiver_manager.dart';

void main() {
  group('HotspotNetworkManager Tests', () {
    late TransceiverManager transceiverManager;
    late HotspotNetworkManager hotspotManager;

    setUp(() {
      transceiverManager = TransceiverManager();
      hotspotManager = HotspotNetworkManager(transceiverManager: transceiverManager);
    });

    tearDown(() {
      hotspotManager.dispose();
    });

    test('getSuggestedHotspotHostIp identifies Android hotspot host gateway', () {
      expect(
        hotspotManager.getSuggestedHotspotHostIp('192.168.43.14'),
        equals('192.168.43.1'),
      );
      expect(
        hotspotManager.getSuggestedHotspotHostIp('192.168.1.105'),
        equals('192.168.1.1'),
      );
      expect(
        hotspotManager.getSuggestedHotspotHostIp(null),
        equals('192.168.43.1'),
      );
    });

    test('HotspotPeer equality and host identification operates properly', () {
      final now = DateTime.now();
      final peer1 = HotspotPeer(
        id: 'NODE_01',
        name: 'Alpha Node',
        ipAddress: '192.168.43.1',
        lastSeen: now,
        isHost: true,
      );

      final peer2 = HotspotPeer(
        id: 'NODE_02',
        name: 'Alpha Node Updated',
        ipAddress: '192.168.43.1',
        lastSeen: now,
        isHost: true,
      );

      expect(peer1, equals(peer2));
      expect(peer1.isHost, isTrue);
    });
  });
}
