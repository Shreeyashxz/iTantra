import 'dart:async';
import 'transceiver_manager.dart';

class WifiP2pPeer {
  final String deviceAddress;
  final String deviceName;
  final int status; // 0: connected, 1: invited, 2: failed, 3: available, 4: unavailable
  final bool isGroupOwner;

  const WifiP2pPeer({
    required this.deviceAddress,
    required this.deviceName,
    this.status = 3,
    this.isGroupOwner = false,
  });

  String get statusDescription {
    switch (status) {
      case 0:
        return 'Connected';
      case 1:
        return 'Invited';
      case 2:
        return 'Failed';
      case 3:
        return 'Available';
      default:
        return 'Unavailable';
    }
  }
}

class WifiDirectManager {
  final TransceiverManager transceiverManager;

  final _peersController = StreamController<List<WifiP2pPeer>>.broadcast();
  Stream<List<WifiP2pPeer>> get peers => _peersController.stream;
  List<WifiP2pPeer> _currentPeers = [];
  List<WifiP2pPeer> get currentPeers => _currentPeers;

  final _connectionStatusController = StreamController<String>.broadcast();
  Stream<String> get connectionStatus => _connectionStatusController.stream;
  String _currentStatus = 'Disconnected';
  String get currentStatus => _currentStatus;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  WifiDirectManager({required this.transceiverManager}) {
    // Start local socket server automatically
    transceiverManager.startServer();
  }

  void _updateStatus(String status) {
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  Future<void> startDiscovery() async {
    _isDiscovering = true;
    _updateStatus('Discovering nearby peers...');

    // Simulate scanning discovery for nearby iTantra nodes on local Wi-Fi Direct mesh
    await Future.delayed(const Duration(milliseconds: 1200));

    _currentPeers = [
      const WifiP2pPeer(
        deviceAddress: '192.168.49.1',
        deviceName: 'iTantra-BaseNode-Alpha',
        status: 3,
        isGroupOwner: true,
      ),
      const WifiP2pPeer(
        deviceAddress: '192.168.49.42',
        deviceName: 'iTantra-Responder-Beta',
        status: 3,
        isGroupOwner: false,
      ),
    ];
    _peersController.add(_currentPeers);
    _updateStatus('Peers found (${_currentPeers.length})');
  }

  Future<bool> connectToPeer(WifiP2pPeer peer) async {
    _updateStatus('Connecting to ${peer.deviceName}...');
    final success = await transceiverManager.connectToPeer(peer.deviceAddress);
    if (success) {
      _updateStatus('Connected');
      _currentPeers = _currentPeers.map((p) {
        if (p.deviceAddress == peer.deviceAddress) {
          return WifiP2pPeer(
            deviceAddress: p.deviceAddress,
            deviceName: p.deviceName,
            status: 0,
            isGroupOwner: p.isGroupOwner,
          );
        }
        return p;
      }).toList();
      _peersController.add(_currentPeers);
    } else {
      _updateStatus('Connection failed');
    }
    return success;
  }

  void stopDiscovery() {
    _isDiscovering = false;
    _updateStatus('Discovery stopped');
  }

  void dispose() {
    stopDiscovery();
    _peersController.close();
    _connectionStatusController.close();
  }
}
