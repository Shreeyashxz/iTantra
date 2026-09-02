import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/wifi_direct_manager.dart';
import '../network/hotspot_network_manager.dart';

enum PeerNetworkMode {
  wifiDirect,
  wifiHotspot,
}

class PeerController extends ChangeNotifier {
  final WifiDirectManager wifiDirectManager;
  final HotspotNetworkManager hotspotNetworkManager;

  PeerNetworkMode _networkMode = PeerNetworkMode.wifiHotspot;
  PeerNetworkMode get networkMode => _networkMode;

  // Wi-Fi Direct state
  List<WifiP2pPeer> _peers = [];
  List<WifiP2pPeer> get peers => _peers;

  String _connectionStatus = 'Disconnected';
  String get connectionStatus => _connectionStatus;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  // Wi-Fi Hotspot state
  List<HotspotPeer> _hotspotPeers = [];
  List<HotspotPeer> get hotspotPeers => _hotspotPeers;

  String? _localIp;
  String? get localIp => _localIp;

  bool get isHotspotBroadcasting => hotspotNetworkManager.isBroadcasting;
  bool get isHotspotScanning => hotspotNetworkManager.isScanning;

  final String deviceId = 'ITANTRA_DART_NODE';

  StreamSubscription<List<WifiP2pPeer>>? _peersSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<List<HotspotPeer>>? _hotspotPeersSubscription;
  StreamSubscription<String>? _hotspotStatusSubscription;

  PeerController({
    required this.wifiDirectManager,
    required this.hotspotNetworkManager,
  }) {
    _peers = wifiDirectManager.currentPeers;
    _connectionStatus = wifiDirectManager.currentStatus;

    _peersSubscription = wifiDirectManager.peers.listen((peerList) {
      _peers = peerList;
      notifyListeners();
    });

    _statusSubscription = wifiDirectManager.connectionStatus.listen((status) {
      if (_networkMode == PeerNetworkMode.wifiDirect) {
        _connectionStatus = status;
        _isDiscovering = wifiDirectManager.isDiscovering;
        notifyListeners();
      }
    });

    _hotspotPeersSubscription = hotspotNetworkManager.discoveredPeers.listen((list) {
      _hotspotPeers = list;
      notifyListeners();
    });

    _hotspotStatusSubscription = hotspotNetworkManager.statusStream.listen((status) {
      if (_networkMode == PeerNetworkMode.wifiHotspot) {
        _connectionStatus = status;
        notifyListeners();
      }
    });

    _initHotspotState();
  }

  Future<void> _initHotspotState() async {
    _localIp = await hotspotNetworkManager.getPrimaryIpAddress();
    await hotspotNetworkManager.startBeaconReceiver();
    notifyListeners();
  }

  void setNetworkMode(PeerNetworkMode mode) {
    _networkMode = mode;
    if (mode == PeerNetworkMode.wifiHotspot) {
      refreshLocalIp();
    }
    notifyListeners();
  }

  Future<void> refreshLocalIp() async {
    _localIp = await hotspotNetworkManager.getPrimaryIpAddress();
    notifyListeners();
  }

  // Wi-Fi Direct actions
  Future<void> startDiscovery() async {
    _isDiscovering = true;
    notifyListeners();
    await wifiDirectManager.startDiscovery();
    _isDiscovering = false;
    notifyListeners();
  }

  Future<bool> connectToPeer(WifiP2pPeer peer) async {
    return await wifiDirectManager.connectToPeer(peer);
  }

  // Hotspot actions
  Future<void> toggleHotspotBeacon() async {
    if (hotspotNetworkManager.isBroadcasting) {
      hotspotNetworkManager.stopBeaconBroadcaster();
    } else {
      await hotspotNetworkManager.startBeaconBroadcaster(
        nodeId: deviceId,
        nodeName: 'iTantra Node (${_localIp ?? "Mesh"})',
      );
    }
    notifyListeners();
  }

  Future<void> scanHotspotSubnet() async {
    await hotspotNetworkManager.scanHotspotSubnet();
    notifyListeners();
  }

  Future<bool> connectToHotspotHost() async {
    final success = await hotspotNetworkManager.connectToHotspotHost();
    if (success) {
      _connectionStatus = 'Connected to Hotspot Host (Base Station)';
    }
    notifyListeners();
    return success;
  }

  Future<bool> connectToHotspotIp(String ip) async {
    final success = await hotspotNetworkManager.connectToHotspotPeer(ip);
    if (success) {
      _connectionStatus = 'Connected to $ip';
    }
    notifyListeners();
    return success;
  }

  @override
  void dispose() {
    _peersSubscription?.cancel();
    _statusSubscription?.cancel();
    _hotspotPeersSubscription?.cancel();
    _hotspotStatusSubscription?.cancel();
    super.dispose();
  }
}
