import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_direct_p2p_service.dart';
import '../network/wifi_mesh_manager.dart';

class PeerController extends ChangeNotifier {
  final WifiMeshManager meshManager;
  final TransceiverManager transceiverManager;
  final WifiDirectP2pService p2pService;

  // Wi-Fi Mesh State
  List<MeshPeer> _peers = [];
  List<MeshPeer> get peers => _peers;

  List<NetworkInterfaceInfo> _interfaces = [];
  List<NetworkInterfaceInfo> get interfaces => _interfaces;

  List<PeerLinkStats> _linkStats = [];
  List<PeerLinkStats> get linkStats => _linkStats;

  // Wi-Fi Direct (P2P Native) State
  List<WifiP2pPeer> _p2pPeers = [];
  List<WifiP2pPeer> get p2pPeers => _p2pPeers;

  WifiP2pConnectionInfo _p2pConnection = const WifiP2pConnectionInfo(
    groupFormed: false,
    isGroupOwner: false,
    groupOwnerAddress: '',
  );
  WifiP2pConnectionInfo get p2pConnection => _p2pConnection;

  bool get isP2pSupported => p2pService.isSupported;
  bool get isP2pDiscovering => p2pService.isDiscovering;

  String _connectionStatus = 'Disconnected';
  String get connectionStatus => _connectionStatus;

  String get deviceId => meshManager.nodeId;
  String? get localIp => meshManager.primaryIp;

  bool get isBeaconing => meshManager.isBeaconing;
  bool get isScanning => meshManager.isScanning;
  bool get autoConnect => meshManager.autoConnect;

  List<String> get connectedIps => transceiverManager.connectedPeerIps;
  int get connectedCount => transceiverManager.connectedPeersCount;

  StreamSubscription<List<MeshPeer>>? _peersSub;
  StreamSubscription<List<NetworkInterfaceInfo>>? _interfacesSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _transceiverStatusSub;
  StreamSubscription<List<PeerLinkStats>>? _statsSub;

  StreamSubscription<List<WifiP2pPeer>>? _p2pPeersSub;
  StreamSubscription<WifiP2pConnectionInfo>? _p2pConnSub;
  StreamSubscription<String>? _p2pStatusSub;

  PeerController({
    required this.meshManager,
    required this.transceiverManager,
    required this.p2pService,
  }) {
    _peers = meshManager.currentPeers;
    _interfaces = meshManager.activeInterfaces;
    _p2pPeers = p2pService.currentPeers;
    _p2pConnection = p2pService.currentConnection;
    _connectionStatus = transceiverManager.isRunning ? 'Listening on port 8888' : 'Standby';

    _peersSub = meshManager.peersStream.listen((list) {
      _peers = list;
      notifyListeners();
    });

    _interfacesSub = meshManager.interfacesStream.listen((list) {
      _interfaces = list;
      notifyListeners();
    });

    _statusSub = meshManager.statusStream.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    _transceiverStatusSub = transceiverManager.connectionState.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    _statsSub = transceiverManager.statsStream.listen((stats) {
      _linkStats = stats;
      notifyListeners();
    });

    // P2P Subscriptions
    _p2pPeersSub = p2pService.peersStream.listen((list) {
      _p2pPeers = list;
      notifyListeners();
    });

    _p2pConnSub = p2pService.connectionStream.listen((info) {
      _p2pConnection = info;
      notifyListeners();
    });

    _p2pStatusSub = p2pService.statusStream.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    _init();
  }

  Future<void> _init() async {
    await meshManager.refreshInterfaces();
    await meshManager.startBeaconService(
      customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
    );
    notifyListeners();
  }

  // --- Wi-Fi Direct Native Methods ---
  Future<bool> startP2pDiscovery() async {
    final ok = await p2pService.startDiscovery();
    notifyListeners();
    return ok;
  }

  Future<bool> stopP2pDiscovery() async {
    final ok = await p2pService.stopDiscovery();
    notifyListeners();
    return ok;
  }

  Future<bool> connectP2p(String deviceAddress) async {
    final ok = await p2pService.connect(deviceAddress);
    notifyListeners();
    return ok;
  }

  Future<bool> disconnectP2p() async {
    final ok = await p2pService.disconnect();
    notifyListeners();
    return ok;
  }

  // --- Wi-Fi Mesh Methods ---
  void toggleAutoConnect(bool enable) {
    meshManager.autoConnect = enable;
    notifyListeners();
  }

  Future<void> toggleBeacon() async {
    if (meshManager.isBeaconing) {
      meshManager.stopBeaconService();
    } else {
      await meshManager.startBeaconService(
        customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
      );
    }
    notifyListeners();
  }

  Future<void> refreshNetwork() async {
    await meshManager.refreshInterfaces();
    notifyListeners();
  }

  Future<void> probeSubnet() async {
    await meshManager.probeSubnet();
    notifyListeners();
  }

  Future<bool> connectToPeer(String ipAddress, {int port = TransceiverManager.port}) async {
    final success = await meshManager.connectToPeerIp(ipAddress, port: port);
    notifyListeners();
    return success;
  }

  Future<bool> connectToGateway() async {
    final success = await meshManager.connectToGateway();
    notifyListeners();
    return success;
  }

  void disconnectPeer(String ipAddress) {
    transceiverManager.disconnectPeer(ipAddress);
    notifyListeners();
  }

  void disconnectAll() {
    transceiverManager.stop();
    p2pService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _interfacesSub?.cancel();
    _statusSub?.cancel();
    _transceiverStatusSub?.cancel();
    _statsSub?.cancel();
    _p2pPeersSub?.cancel();
    _p2pConnSub?.cancel();
    _p2pStatusSub?.cancel();
    super.dispose();
  }
}
