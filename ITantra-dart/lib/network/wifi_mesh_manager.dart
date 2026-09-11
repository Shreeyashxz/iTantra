import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'transceiver_manager.dart';

class NetworkInterfaceInfo {
  final String name;
  final String ipAddress;
  final String subnetPrefix;
  final String broadcastAddress;
  final bool isHotspot;
  final bool isP2P;
  final bool isApipa;

  const NetworkInterfaceInfo({
    required this.name,
    required this.ipAddress,
    required this.subnetPrefix,
    required this.broadcastAddress,
    required this.isHotspot,
    required this.isP2P,
    this.isApipa = false,
  });

  String get typeLabel {
    if (isP2P) return 'Wi-Fi Direct P2P';
    if (isHotspot) return 'Mobile Hotspot';
    if (isApipa) return 'Link-Local (Unconfigured)';
    return 'Wi-Fi / LAN';
  }
}

class MeshPeer {
  final String id;
  final String name;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;
  final bool isHost;
  final String networkType;

  const MeshPeer({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.port = TransceiverManager.port,
    required this.lastSeen,
    this.isHost = false,
    this.networkType = 'Wi-Fi Mesh',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPeer && runtimeType == other.runtimeType && ipAddress == other.ipAddress;

  @override
  int get hashCode => ipAddress.hashCode;
}

class WifiMeshManager {
  static const int beaconPort = 8889;
  static final InternetAddress multicastAddress = InternetAddress('239.255.88.88');
  static const String beaconPrefix = 'ITANTRA_MESH:v2:';

  final TransceiverManager transceiverManager;

  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _multicastSocket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;

  final Map<String, MeshPeer> _discoveredPeers = {};
  final _peersController = StreamController<List<MeshPeer>>.broadcast();
  Stream<List<MeshPeer>> get peersStream => _peersController.stream;
  List<MeshPeer> get currentPeers => _discoveredPeers.values.toList();

  final _interfacesController = StreamController<List<NetworkInterfaceInfo>>.broadcast();
  Stream<List<NetworkInterfaceInfo>> get interfacesStream => _interfacesController.stream;
  List<NetworkInterfaceInfo> _activeInterfaces = [];
  List<NetworkInterfaceInfo> get activeInterfaces => _activeInterfaces;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  String _currentStatus = 'Standby';
  String get currentStatus => _currentStatus;

  bool _isBeaconing = false;
  bool get isBeaconing => _isBeaconing;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool autoConnect = true;

  String nodeId = 'NODE_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
  String nodeName = 'iTantra Device';

  bool _isDisposed = false;

  WifiMeshManager({required this.transceiverManager}) {
    // Automatically bind the local socket server
    transceiverManager.startServer();
    refreshInterfaces();
  }

  void _updateStatus(String status) {
    _currentStatus = status;
    if (!_isDisposed && !_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Checks if an IP address belongs to known mobile hotspot ranges
  static bool isHotspotSubnet(String ip) {
    return ip.startsWith('192.168.43.') || // Android default AP
        ip.startsWith('192.168.137.') || // Windows Mobile Hotspot
        ip.startsWith('172.20.10.') || // iOS Personal Hotspot
        ip.startsWith('192.168.225.') || // Jio / OEM Hotspot
        ip.startsWith('192.168.44.'); // Custom Android AP
  }

  /// Scans local network interfaces, computes subnets, and prioritizes active routable Wi-Fi
  Future<List<NetworkInterfaceInfo>> refreshInterfaces() async {
    final list = <NetworkInterfaceInfo>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            final lastDot = ip.lastIndexOf('.');
            if (lastDot != -1) {
              final prefix = ip.substring(0, lastDot);
              final isHotspot = isHotspotSubnet(ip);
              final isP2P = ip.startsWith('192.168.49.');
              final isApipa = ip.startsWith('169.254.');

              list.add(
                NetworkInterfaceInfo(
                  name: iface.name,
                  ipAddress: ip,
                  subnetPrefix: prefix,
                  broadcastAddress: '$prefix.255',
                  isHotspot: isHotspot,
                  isP2P: isP2P,
                  isApipa: isApipa,
                ),
              );
            }
          }
        }
      }

      // Rank interfaces: Hotspot > P2P > LAN/Wi-Fi > APIPA (Link-Local)
      list.sort((a, b) {
        int rank(NetworkInterfaceInfo info) {
          if (info.isApipa) return 4;
          if (info.isHotspot) return 0;
          if (info.isP2P) return 1;
          if (info.ipAddress.startsWith('192.168.') ||
              info.ipAddress.startsWith('10.') ||
              info.ipAddress.startsWith('172.')) {
            return 2;
          }
          return 3;
        }
        return rank(a).compareTo(rank(b));
      });
    } catch (e) {
      debugPrint('Error inspecting network interfaces: $e');
    }

    _activeInterfaces = list;
    if (!_isDisposed && !_interfacesController.isClosed) {
      _interfacesController.add(_activeInterfaces);
    }
    return list;
  }

  /// Returns primary active IP, strictly prioritizing real routable Wi-Fi over APIPA (169.254.*)
  String? get primaryIp {
    final routable = _activeInterfaces.where((i) => !i.isApipa);
    if (routable.isNotEmpty) return routable.first.ipAddress;
    return _activeInterfaces.isNotEmpty ? _activeInterfaces.first.ipAddress : null;
  }

  /// Returns true if this device is hosting a mobile hotspot AP (.1)
  bool get isHotspotHost =>
      _activeInterfaces.any((i) => i.isHotspot && i.ipAddress.endsWith('.1'));

  /// Returns true if this device is connected to a mobile hotspot as a client
  bool get isHotspotClient =>
      _activeInterfaces.any((i) => i.isHotspot && !i.ipAddress.endsWith('.1'));

  /// Returns the Hotspot Gateway Host IP (.1) if connected to a hotspot
  String? get hotspotHostIp {
    for (final iface in _activeInterfaces) {
      if (iface.isHotspot && !iface.ipAddress.endsWith('.1')) {
        return '${iface.subnetPrefix}.1';
      }
    }
    return null;
  }

  /// Starts the multi-interface UDP broadcast & Multicast presence beacon
  Future<void> startBeaconService({String? customNodeName}) async {
    if (customNodeName != null) nodeName = customNodeName;
    await refreshInterfaces();
    await _startReceivers();

    _isBeaconing = true;
    _updateStatus('Mesh Beaconing Active (Port $beaconPort)');

    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _sendPresenceBeacon());

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pruneStalePeers());

    // Send initial beacon immediately
    _sendPresenceBeacon();

    // Hybrid Auto-Connect: if we are a Hotspot client, proactively link to the AP host (.1)
    if (autoConnect && isHotspotClient && hotspotHostIp != null) {
      final hostIp = hotspotHostIp!;
      debugPrint('[Hybrid Discovery] Detected Hotspot Host at $hostIp. Auto-linking...');
      transceiverManager.connectToPeer(hostIp);
    }
  }

  Future<void> _startReceivers() async {
    // 1. Unicast/Broadcast Receiver Socket
    if (_broadcastSocket == null) {
      try {
        _broadcastSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          beaconPort,
          reuseAddress: true,
          reusePort: !Platform.isWindows,
        );
        _broadcastSocket!.broadcastEnabled = true;

        _broadcastSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _broadcastSocket?.receive();
            if (dg != null) _processBeaconDatagram(dg);
          }
        });
      } catch (e) {
        debugPrint('Error binding broadcast receiver: $e');
      }
    }

    // 2. Multicast Group Receiver (bypasses router broadcast blocks)
    if (_multicastSocket == null) {
      try {
        _multicastSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          beaconPort,
          reuseAddress: true,
        );
        _multicastSocket!.broadcastEnabled = true;
        try {
          _multicastSocket!.joinMulticast(multicastAddress);
        } catch (_) {}

        _multicastSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _multicastSocket?.receive();
            if (dg != null) _processBeaconDatagram(dg);
          }
        });
      } catch (e) {
        debugPrint('Multicast bind warning (non-fatal): $e');
      }
    }
  }

  Future<void> _sendPresenceBeacon() async {
    if (!_isBeaconing) return;
    final myIp = primaryIp ?? '0.0.0.0';
    final payload = '$beaconPrefix$nodeId:$nodeName:$myIp:${transceiverManager.activePort}';
    final bytes = utf8.encode(payload);

    try {
      if (_broadcastSocket == null) {
        _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
        _broadcastSocket!.broadcastEnabled = true;
      }

      // 1. Universal broadcast
      try {
        _broadcastSocket?.send(bytes, InternetAddress('255.255.255.255'), beaconPort);
      } catch (e) {
        // Universal 255.255.255.255 can throw OS error 1231 on Windows if route table is missing a gateway
      }

      // 2. Multicast group
      try {
        _broadcastSocket?.send(bytes, multicastAddress, beaconPort);
      } catch (_) {}

      // 3. Directed subnet broadcasts for each active non-APIPA interface
      for (final iface in _activeInterfaces.where((i) => !i.isApipa)) {
        try {
          _broadcastSocket?.send(bytes, InternetAddress(iface.broadcastAddress), beaconPort);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Beacon transmit error: $e');
      try {
        _broadcastSocket?.close();
      } catch (_) {}
      _broadcastSocket = null;
    }
  }

  void _processBeaconDatagram(Datagram dg) {
    try {
      final msg = utf8.decode(dg.data);
      if (!msg.startsWith(beaconPrefix)) return;

      final body = msg.substring(beaconPrefix.length);
      final parts = body.split(':');
      if (parts.length >= 4) {
        final peerId = parts[0];
        final peerName = parts[1];
        final announcedIp = parts[2];
        final port = int.tryParse(parts[3]) ?? transceiverManager.activePort;

        // Resolve real IP: if announced IP is missing, loopback, APIPA, or off-subnet, use the datagram link address
        String peerIp = dg.address.address;
        if (announcedIp.isNotEmpty &&
            announcedIp != '0.0.0.0' &&
            announcedIp != '127.0.0.1' &&
            !announcedIp.startsWith('169.254.')) {
          final matchesSubnet = _activeInterfaces.any(
            (iface) => !iface.isApipa && announcedIp.startsWith('${iface.subnetPrefix}.'),
          );
          if (matchesSubnet) {
            peerIp = announcedIp;
          }
        }

        // Ignore our own broadcast
        if (peerId == nodeId) return;
        final myIps = _activeInterfaces.map((i) => i.ipAddress).toSet();
        if (myIps.contains(peerIp)) return;

        final isHost = peerIp.endsWith('.1');
        String netType = 'Wi-Fi Peer';
        if (peerIp.startsWith('192.168.49.')) {
          netType = 'Wi-Fi Direct P2P';
        } else if (isHotspotSubnet(peerIp)) {
          netType = 'Mobile Hotspot';
        }

        final peer = MeshPeer(
          id: peerId,
          name: peerName,
          ipAddress: peerIp,
          port: port,
          lastSeen: DateTime.now(),
          isHost: isHost,
          networkType: netType,
        );

        final isNew = !_discoveredPeers.containsKey(peerIp);
        _discoveredPeers[peerIp] = peer;
        if (!_isDisposed && !_peersController.isClosed) {
          _peersController.add(currentPeers);
        }

        if (isNew) {
          _updateStatus('Discovered node $peerName ($peerIp)');
          debugPrint('Discovered new peer node: $peerName at $peerIp:$port');
        }

        // Auto-connect to newly discovered peer if enabled and not yet connected
        if (autoConnect && !transceiverManager.connectedPeerIps.contains(peerIp)) {
          _autoConnectToPeer(peerIp, port);
        }
      }
    } catch (e) {
      debugPrint('Error processing beacon: $e');
    }
  }

  /// Converts an IPv4 dotted string into a 32-bit unsigned integer for deterministic comparison
  static int ipToUint32(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length == 4) {
        return ((int.parse(parts[0]) & 0xFF) << 24) |
            ((int.parse(parts[1]) & 0xFF) << 16) |
            ((int.parse(parts[2]) & 0xFF) << 8) |
            (int.parse(parts[3]) & 0xFF);
      }
    } catch (_) {}
    return 0;
  }

  void _autoConnectToPeer(String peerIp, int port) {
    // 1. Hotspot AP Host Rule: If this device is hosting the AP (.1), let the Hotspot Client initiate
    if (isHotspotHost) {
      debugPrint('[Hybrid Discovery] Hotspot Host standing by for client link from $peerIp:$port');
      return;
    }

    // 2. Hotspot Client Rule: Proactively link to the Hotspot Host (.1)
    if (isHotspotClient && (peerIp == hotspotHostIp || peerIp.endsWith('.1'))) {
      debugPrint('[Hybrid Discovery] Auto-linking client to Hotspot Host at $peerIp:$port...');
      transceiverManager.connectToPeer(peerIp, targetPort: port);
      return;
    }

    // 3. Symmetrical 32-bit numeric IP tie-breaker for general peer mesh:
    // Device with smaller numeric IP initiates outbound TCP link
    final myIp = primaryIp ?? '';
    final myNumeric = ipToUint32(myIp);
    final peerNumeric = ipToUint32(peerIp);

    if (myNumeric != 0 && peerNumeric != 0) {
      if (myNumeric < peerNumeric) {
        debugPrint('Auto-linking mesh to $peerIp:$port (tie-breaker: initiator $myNumeric < $peerNumeric)...');
        transceiverManager.connectToPeer(peerIp, targetPort: port);
      } else {
        debugPrint('Mesh peer discovered: $peerIp:$port (tie-breaker: awaiting inbound connection)');
      }
    } else {
      transceiverManager.connectToPeer(peerIp, targetPort: port);
    }
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    final expiredIps = <String>[];
    for (final entry in _discoveredPeers.entries) {
      // If not seen in 15 seconds, remove
      if (now.difference(entry.value.lastSeen).inSeconds > 15) {
        expiredIps.add(entry.key);
      }
    }
    if (expiredIps.isNotEmpty) {
      for (final ip in expiredIps) {
        _discoveredPeers.remove(ip);
      }
      if (!_isDisposed && !_peersController.isClosed) {
        _peersController.add(currentPeers);
      }
    }
  }

  /// High-speed parallel subnet prober across all active network interfaces (skips APIPA)
  Future<List<MeshPeer>> probeSubnet() async {
    if (_isScanning) return currentPeers;
    _isScanning = true;
    _updateStatus('Probing active local subnets for iTantra transceivers...');

    await refreshInterfaces();
    final myIps = _activeInterfaces.map((i) => i.ipAddress).toSet();
    final prefixes = _activeInterfaces
        .where((i) => !i.isApipa && !i.ipAddress.startsWith('127.'))
        .map((i) => i.subnetPrefix)
        .toSet();

    if (prefixes.isEmpty) {
      prefixes.add('192.168.1');
      prefixes.add('192.168.43');
    }

    final found = <MeshPeer>[];
    final activePort = transceiverManager.activePort;

    for (final prefix in prefixes) {
      final batchTasks = <Future<void>>[];

      for (var i = 1; i <= 254; i++) {
        final targetIp = '$prefix.$i';
        if (myIps.contains(targetIp)) continue;

        batchTasks.add(() async {
          try {
            final socket = await Socket.connect(
              targetIp,
              activePort,
              timeout: const Duration(milliseconds: 220),
            );
            socket.destroy();

            final isHost = i == 1;
            final isHotspot = isHotspotSubnet(targetIp);
            final peer = MeshPeer(
              id: 'PROBE_NODE_$i',
              name: (isHost && isHotspot)
                  ? 'Hotspot Host ($targetIp)'
                  : (isHost ? 'Router/Host ($targetIp)' : 'iTantra Node ($targetIp)'),
              ipAddress: targetIp,
              port: activePort,
              lastSeen: DateTime.now(),
              isHost: isHost,
              networkType: targetIp.startsWith('192.168.49')
                  ? 'Wi-Fi Direct'
                  : (isHotspot ? 'Mobile Hotspot' : 'Wi-Fi Subnet'),
            );

            _discoveredPeers[targetIp] = peer;
            found.add(peer);

            // Immediately auto-connect
            if (autoConnect) {
              transceiverManager.connectToPeer(targetIp, targetPort: activePort);
            }
          } catch (_) {}
        }());

        if (batchTasks.length >= 35) {
          await Future.wait(batchTasks);
          batchTasks.clear();
        }
      }

      if (batchTasks.isNotEmpty) {
        await Future.wait(batchTasks);
      }
    }

    _isScanning = false;
    if (!_isDisposed && !_peersController.isClosed) {
      _peersController.add(currentPeers);
    }
    _updateStatus('Subnet probe complete: found ${found.length} node(s)');
    return currentPeers;
  }

  /// Connects to a peer explicitly by IP address
  Future<bool> connectToPeerIp(String ipAddress, {int? port}) async {
    final targetPort = port ?? transceiverManager.activePort;
    _updateStatus('Connecting to $ipAddress:$targetPort...');
    final success = await transceiverManager.connectToPeer(ipAddress, targetPort: targetPort);
    if (success) {
      _updateStatus('Connected to $ipAddress:$targetPort');
    } else {
      _updateStatus('Could not reach $ipAddress:$targetPort');
    }
    return success;
  }

  /// Quick link to Gateway / AP host (.1)
  Future<bool> connectToGateway() async {
    await refreshInterfaces();
    final targetPort = transceiverManager.activePort;
    for (final iface in _activeInterfaces.where((i) => !i.isApipa)) {
      final gatewayIp = '${iface.subnetPrefix}.1';
      if (gatewayIp != iface.ipAddress) {
        final ok = await connectToPeerIp(gatewayIp, port: targetPort);
        if (ok) return true;
      }
    }
    return false;
  }

  void stopBeaconService() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    _multicastSocket?.close();
    _multicastSocket = null;
    _isBeaconing = false;
    _updateStatus('Mesh Beacon Service Stopped');
  }

  void dispose() {
    _isDisposed = true;
    stopBeaconService();
    _peersController.close();
    _interfacesController.close();
    _statusController.close();
  }
}
