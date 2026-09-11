import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/network/transceiver_manager.dart';
import 'package:itantra_dart/network/wifi_mesh_manager.dart';

void main() {
  test('Transceiver and Wi-Fi Mesh Normalization Verification', () async {
    final tm = TransceiverManager();
    final ok = await tm.startServer();
    expect(ok, isTrue);
    expect(tm.activePort, equals(8888));
    expect(tm.currentStatusString, contains('Listening on port 8888'));

    final testRes = await tm.testLocalPortConnection();
    expect(testRes['success'], isTrue);
    expect(testRes['port'], equals(8888));

    final mm = WifiMeshManager(transceiverManager: tm);
    final ifaces = await mm.refreshInterfaces();
    expect(ifaces, isNotEmpty);

    // Verify APIPA filtering: primaryIp should never be an APIPA address if a routable IP is present
    final hasRoutable = ifaces.any((i) => !i.isApipa);
    if (hasRoutable) {
      expect(mm.primaryIp?.startsWith('169.254.'), isFalse);
    }

    // Verify Hotspot range detection
    expect(WifiMeshManager.isHotspotSubnet('192.168.43.1'), isTrue);
    expect(WifiMeshManager.isHotspotSubnet('192.168.137.1'), isTrue);
    expect(WifiMeshManager.isHotspotSubnet('172.20.10.1'), isTrue);
    expect(WifiMeshManager.isHotspotSubnet('192.168.225.1'), isTrue);
    expect(WifiMeshManager.isHotspotSubnet('192.168.1.10'), isFalse);

    mm.dispose();
    tm.dispose();
  });
}
