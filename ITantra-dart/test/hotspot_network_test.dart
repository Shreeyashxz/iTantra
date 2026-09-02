import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/network/wifi_mesh_manager.dart';
import 'package:itantra_dart/network/transceiver_manager.dart';

void main() {
  group('WifiMeshManager Tests', () {
    late TransceiverManager transceiverManager;
    late WifiMeshManager meshManager;

    setUp(() {
      transceiverManager = TransceiverManager();
      meshManager = WifiMeshManager(transceiverManager: transceiverManager);
    });

    tearDown(() {
      meshManager.dispose();
      transceiverManager.dispose();
    });

    test('MeshPeer equality and host identification operates properly', () {
      final now = DateTime.now();
      final peer1 = MeshPeer(
        id: 'NODE_01',
        name: 'Alpha Node',
        ipAddress: '192.168.43.1',
        lastSeen: now,
        isHost: true,
      );

      final peer2 = MeshPeer(
        id: 'NODE_02',
        name: 'Alpha Node Updated',
        ipAddress: '192.168.43.1',
        lastSeen: now,
        isHost: true,
      );

      expect(peer1, equals(peer2));
      expect(peer1.isHost, isTrue);
    });

    test('NetworkInterfaceInfo identifies hotspot and p2p subnets', () {
      const hotspotIface = NetworkInterfaceInfo(
        name: 'wlan0',
        ipAddress: '192.168.43.15',
        subnetPrefix: '192.168.43',
        broadcastAddress: '192.168.43.255',
        isHotspot: true,
        isP2P: false,
      );
      expect(hotspotIface.typeLabel, equals('Mobile Hotspot'));

      const p2pIface = NetworkInterfaceInfo(
        name: 'p2p-wlan0-0',
        ipAddress: '192.168.49.2',
        subnetPrefix: '192.168.49',
        broadcastAddress: '192.168.49.255',
        isHotspot: false,
        isP2P: true,
      );
      expect(p2pIface.typeLabel, equals('Wi-Fi Direct P2P'));
    });
  });
}
