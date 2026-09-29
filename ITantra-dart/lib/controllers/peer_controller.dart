import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/ble_fallback_transport.dart';
import '../network/transceiver_manager.dart';
import '../network/wifi_direct_p2p_service.dart';
import '../network/wifi_mesh_manager.dart';
import '../proto/transceiver_packet.dart';

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

  // BLE Fallback Transport State
  BleFallbackTransport get bleTransport => transceiverManager.bleTransport;
  bool get isBleSupported => bleTransport.isSupported;
  bool get isBleAdvertising => bleTransport.isAdvertising;
  bool get isBleScanning => bleTransport.isScanning;
  bool get isBleConnected => bleTransport.isConnected;
  String? get bleConnectedPeerName => bleTransport.connectedPeerName;
  String? get bleConnectedPeerAddress => bleTransport.connectedPeerAddress;
  List<BleDiscoveredPeer> get bleDiscoveredPeers => bleTransport.discoveredPeers;
  String get bleStatus => bleTransport.status;
  int get bleChunksSent => bleTransport.totalChunksSent;
  int get bleChunksReceived => bleTransport.totalChunksReceived;
  int get blePacketsSent => bleTransport.totalPacketsSent;
  int get blePacketsReceived => bleTransport.totalPacketsReassembled;
  int get blePacketsReassembled => bleTransport.totalPacketsReassembled;

  String _connectionStatus = 'Disconnected';
  String get connectionStatus => _connectionStatus;

  int get activePort => transceiverManager.activePort;
  bool get isHotspotHost => meshManager.isHotspotHost;
  bool get isHotspotClient => meshManager.isHotspotClient;
  String? get hotspotHostIp => meshManager.hotspotHostIp;

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

  StreamSubscription<List<BleDiscoveredPeer>>? _blePeersSub;
  StreamSubscription<String>? _bleStatusSub;

  bool _disposed = false;
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  PeerController({
    required this.meshManager,
    required this.transceiverManager,
    required this.p2pService,
  }) {
    _peers = meshManager.currentPeers;
    _interfaces = meshManager.activeInterfaces;
    _p2pPeers = p2pService.currentPeers;
    _p2pConnection = p2pService.currentConnection;
    _connectionStatus = transceiverManager.currentStatusString;

    _peersSub = meshManager.peersStream.listen((list) {
      _peers = list;
      _safeNotify();
    });

    _interfacesSub = meshManager.interfacesStream.listen((list) {
      _interfaces = list;
      _safeNotify();
    });

    _statusSub = meshManager.statusStream.listen((status) {
      _connectionStatus = status;
      _safeNotify();
    });

    _transceiverStatusSub = transceiverManager.connectionState.listen((status) {
      _connectionStatus = status;
      _safeNotify();
    });

    _statsSub = transceiverManager.statsStream.listen((stats) {
      _linkStats = stats;
      _safeNotify();
    });

    // P2P Subscriptions
    _p2pPeersSub = p2pService.peersStream.listen((list) {
      _p2pPeers = list;
      _safeNotify();
    });

    _p2pConnSub = p2pService.connectionStream.listen((info) {
      _p2pConnection = info;
      _safeNotify();
    });

    _p2pStatusSub = p2pService.statusStream.listen((status) {
      _connectionStatus = status;
      _safeNotify();
    });

    _blePeersSub = bleTransport.peersStream.listen((_) {
      _safeNotify();
    });

    _bleStatusSub = bleTransport.statusStream.listen((_) {
      _safeNotify();
    });

    _init();
  }

  Future<void> _init() async {
    await meshManager.refreshInterfaces();
    await meshManager.startBeaconService(
      customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
    );
    _safeNotify();
  }

  // --- Wi-Fi Direct Native Methods ---
  Future<bool> startP2pDiscovery() async {
    final ok = await p2pService.startDiscovery();
    _safeNotify();
    return ok;
  }

  Future<bool> stopP2pDiscovery() async {
    final ok = await p2pService.stopDiscovery();
    _safeNotify();
    return ok;
  }

  Future<bool> connectP2p(String deviceAddress) async {
    final ok = await p2pService.connect(deviceAddress);
    _safeNotify();
    return ok;
  }

  Future<bool> disconnectP2p() async {
    final ok = await p2pService.disconnect();
    _safeNotify();
    return ok;
  }

  // --- Wi-Fi Mesh Methods ---
  void toggleAutoConnect(bool enable) {
    meshManager.autoConnect = enable;
    _safeNotify();
  }

  Future<void> toggleBeacon() async {
    if (meshManager.isBeaconing) {
      meshManager.stopBeaconService();
    } else {
      await meshManager.startBeaconService(
        customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
      );
    }
    _safeNotify();
  }

  Future<void> refreshNetwork() async {
    await meshManager.refreshInterfaces();
    _safeNotify();
  }

  Future<void> probeSubnet() async {
    await meshManager.probeSubnet();
    _safeNotify();
  }

  Future<Map<String, dynamic>> testRadioPort() async {
    final res = await transceiverManager.testLocalPortConnection();
    _safeNotify();
    return res;
  }

  Future<void> changePort(int newPort) async {
    await transceiverManager.rebindPort(newPort);
    await meshManager.startBeaconService(
      customNodeName: 'iTantra Node (${localIp ?? "Mesh"})',
    );
    _safeNotify();
  }

  Future<bool> quickConnectHotspotHost() async {
    final host = hotspotHostIp;
    if (host == null) return false;
    final ok = await connectToPeer(host, port: activePort);
    _safeNotify();
    return ok;
  }

  Future<bool> connectToPeer(String ipAddress, {int? port}) async {
    final destPort = port ?? activePort;
    final success = await meshManager.connectToPeerIp(ipAddress, port: destPort);
    _safeNotify();
    return success;
  }

  Future<bool> connectToGateway() async {
    final success = await meshManager.connectToGateway();
    _safeNotify();
    return success;
  }

  // --- BLE Fallback Methods ---
  Future<bool> startBleAdvertising([String? name]) async {
    final ok = await bleTransport.startAdvertising(name);
    _safeNotify();
    return ok;
  }

  Future<bool> stopBleAdvertising() async {
    final ok = await bleTransport.stopAdvertising();
    _safeNotify();
    return ok;
  }

  Future<bool> startBleScanning() async {
    final ok = await bleTransport.startScanning();
    _safeNotify();
    return ok;
  }

  Future<bool> stopBleScanning() async {
    final ok = await bleTransport.stopScanning();
    _safeNotify();
    return ok;
  }

  Future<bool> connectBlePeer(String address, [String? name]) async {
    final ok = await bleTransport.connectToPeer(address, name);
    _safeNotify();
    return ok;
  }

  Future<void> disconnectBle() async {
    await bleTransport.disconnect();
    _safeNotify();
  }

  void simulateBlePeer([String name = 'Simulated Field Radio', String? address]) {
    bleTransport.simulatePeerConnected(name, address);
    _safeNotify();
  }

  Future<Map<String, dynamic>> testBleLoopback([String testText = 'iTantra Emergency Beacon Loopback Payload']) async {
    final packet = TransceiverPacket(
      senderId: deviceId,
      transcript: testText,
      languageCode: 'hi',
      type: PacketType.voice,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    final res = await bleTransport.testLoopback(packet);
    _safeNotify();
    return res;
  }

  void disconnectPeer(String ipAddress) {
    transceiverManager.disconnectPeer(ipAddress);
    _safeNotify();
  }

  void disconnectAll() {
    transceiverManager.stop();
    p2pService.disconnect();
    disconnectBle();
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _peersSub?.cancel();
    _interfacesSub?.cancel();
    _statusSub?.cancel();
    _transceiverStatusSub?.cancel();
    _statsSub?.cancel();
    _p2pPeersSub?.cancel();
    _p2pConnSub?.cancel();
    _p2pStatusSub?.cancel();
    _blePeersSub?.cancel();
    _bleStatusSub?.cancel();
    super.dispose();
  }
}
