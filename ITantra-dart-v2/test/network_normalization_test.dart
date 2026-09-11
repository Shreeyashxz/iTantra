import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/network/transceiver_manager.dart';
import 'package:itantra_dart/network/wifi_mesh_manager.dart';

void main() {
  test('Transceiver and Wi-Fi Mesh Normalization Verification', () async {
    final tm = TransceiverManager();
    final ok = await tm.startServer();
    expect(ok, isTrue);
    expect(tm.activePort, isIn(TransceiverManager.fallbackPorts));
    expect(tm.currentStatusString, contains('Listening on port ${tm.activePort}'));

    final testRes = await tm.testLocalPortConnection();
    expect(testRes['success'], isTrue);
    expect(testRes['port'], equals(tm.activePort));

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

    // Verify 32-bit numeric IP comparison (192.168.1.3 must be less than 192.168.1.10)
    final numIp3 = WifiMeshManager.ipToUint32('192.168.1.3');
    final numIp10 = WifiMeshManager.ipToUint32('192.168.1.10');
    expect(numIp3, isNonZero);
    expect(numIp10, isNonZero);
    expect(numIp3 < numIp10, isTrue);

    mm.dispose();
    tm.dispose();
  });
}
