import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_mesh_manager.dart';

class PeerController extends ChangeNotifier {
  final WifiMeshManager meshManager;
  final TransceiverManager transceiverManager;

  List<MeshPeer> _peers = [];
  List<MeshPeer> get peers => _peers;

  List<NetworkInterfaceInfo> _interfaces = [];
  List<NetworkInterfaceInfo> get interfaces => _interfaces;

  List<PeerLinkStats> _linkStats = [];
  List<PeerLinkStats> get linkStats => _linkStats;

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

  PeerController({
    required this.meshManager,
    required this.transceiverManager,
  }) {
    _peers = meshManager.currentPeers;
    _interfaces = meshManager.activeInterfaces;
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

    _init();
  }

  Future<void> _init() async {
    await meshManager.refreshInterfaces();
    // Auto-start presence beaconing so devices discover each other out of the box
    await meshManager.startBeaconService(
      customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
    );
    notifyListeners();
  }

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

  @override
  void dispose() {
    _peersSub?.cancel();
    _interfacesSub?.cancel();
    _statusSub?.cancel();
    _transceiverStatusSub?.cancel();
    _statsSub?.cancel();
    super.dispose();
  }
}
