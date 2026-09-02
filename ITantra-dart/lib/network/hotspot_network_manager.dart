import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'transceiver_manager.dart';

class HotspotPeer {
  final String id;
  final String name;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;
  final bool isHost;

  HotspotPeer({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.port = TransceiverManager.port,
    required this.lastSeen,
    this.isHost = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotspotPeer &&
          runtimeType == other.runtimeType &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => ipAddress.hashCode;
}

/// Manages Wi-Fi Hotspot network connections, subnet discovery,
/// and zero-configuration UDP beacons across portable APs and offline routers.
class HotspotNetworkManager {
  static const int beaconPort = 8889;
  static const String beaconPrefix = 'ITANTRA_BEACON:v1:';

  final TransceiverManager transceiverManager;

  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _receiverSocket;
  Timer? _beaconTimer;

  final Map<String, HotspotPeer> _discoveredPeers = {};
  final _peersController = StreamController<List<HotspotPeer>>.broadcast();
  Stream<List<HotspotPeer>> get discoveredPeers => _peersController.stream;
  List<HotspotPeer> get currentPeers => _discoveredPeers.values.toList();

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  String _currentStatus = 'Idle';
  String get currentStatus => _currentStatus;

  bool _isBroadcasting = false;
  bool get isBroadcasting => _isBroadcasting;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  HotspotNetworkManager({required this.transceiverManager});

  /// Lists all active non-loopback IPv4 network addresses on this device.
  Future<List<String>> getLocalIpAddresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IPs: $e');
    }
    return ips;
  }

  /// Returns the most likely Hotspot / Wi-Fi IPv4 address.
  /// Prioritizes standard hotspot AP subnets: 192.168.43.x (Android Hotspot),
  /// 192.168.49.x (Wi-Fi Direct), or standard 192.168.x.x / 10.x.x.x.
  Future<String?> getPrimaryIpAddress() async {
    final ips = await getLocalIpAddresses();
    if (ips.isEmpty) return null;

    // Android hotspot host or client
    final hotspotIp = ips.where((ip) => ip.startsWith('192.168.43.')).firstOrNull;
    if (hotspotIp != null) return hotspotIp;

    // Standard private LAN IPs
    final lanIp = ips.where((ip) => ip.startsWith('192.168.') || ip.startsWith('10.')).firstOrNull;
    if (lanIp != null) return lanIp;

    return ips.first;
  }

  /// Suggests the Hotspot Host IP (default Android AP gateway is 192.168.43.1).
  String getSuggestedHotspotHostIp(String? currentIp) {
    if (currentIp != null && currentIp.startsWith('192.168.43.')) {
      return '192.168.43.1';
    }
    if (currentIp != null && currentIp.contains('.')) {
      final parts = currentIp.split('.');
      if (parts.length == 4) {
        return '${parts[0]}.${parts[1]}.${parts[2]}.1';
      }
    }
    return '192.168.43.1';
  }

  /// Starts listening for UDP beacons from other iTantra devices on the hotspot network.
  Future<void> startBeaconReceiver() async {
    if (_receiverSocket != null) return;

    try {
      _receiverSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
        reusePort: true,
      );
      _receiverSocket!.broadcastEnabled = true;

      _receiverSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _receiverSocket?.receive();
          if (datagram != null) {
            _handleIncomingBeacon(datagram);
          }
        }
      });

      _updateStatus('Listening for hotspot beacons on port $beaconPort');
      debugPrint('Hotspot UDP Beacon receiver active on port $beaconPort');
    } catch (e) {
      debugPrint('Error starting hotspot beacon receiver: $e');
      _updateStatus('Beacon receiver error: $e');
    }
  }

  /// Broadcasts presence beacons every 2.5 seconds to 255.255.255.255:8889.
  Future<void> startBeaconBroadcaster({
    required String nodeId,
    required String nodeName,
  }) async {
    await startBeaconReceiver();

    _isBroadcasting = true;
    _updateStatus('Broadcasting hotspot beacon as $nodeName');

    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      final myIp = await getPrimaryIpAddress() ?? '0.0.0.0';
      final isHost = myIp.endsWith('.1');
      final payload = '$beaconPrefix$nodeId:$nodeName:$myIp:${TransceiverManager.port}:$isHost';
      final bytes = utf8.encode(payload);

      try {
        _broadcastSocket ??= await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        _broadcastSocket!.broadcastEnabled = true;

        // Broadcast to general subnet
        _broadcastSocket!.send(
          bytes,
          InternetAddress('255.255.255.255'),
          beaconPort,
        );

        // Also broadcast directly to standard Android hotspot subnet broadcast if applicable
        if (myIp.startsWith('192.168.43.')) {
          _broadcastSocket!.send(
            bytes,
            InternetAddress('192.168.43.255'),
            beaconPort,
          );
        }
      } catch (e) {
        debugPrint('Beacon broadcast error: $e');
      }
    });
  }

  /// Stops broadcasting beacons.
  void stopBeaconBroadcaster() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    _isBroadcasting = false;
    _updateStatus('Hotspot beacon broadcast stopped');
  }

  void _handleIncomingBeacon(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      if (!message.startsWith(beaconPrefix)) return;

      final content = message.substring(beaconPrefix.length);
      final parts = content.split(':');
      if (parts.length >= 4) {
        final nodeId = parts[0];
        final nodeName = parts[1];
        final senderIp = parts[2].isNotEmpty && parts[2] != '0.0.0.0'
            ? parts[2]
            : datagram.address.address;
        final port = int.tryParse(parts[3]) ?? TransceiverManager.port;
        final isHost = parts.length >= 5 ? parts[4] == 'true' : senderIp.endsWith('.1');

        final peer = HotspotPeer(
          id: nodeId,
          name: nodeName,
          ipAddress: senderIp,
          port: port,
          lastSeen: DateTime.now(),
          isHost: isHost,
        );

        _discoveredPeers[senderIp] = peer;
        _peersController.add(currentPeers);
      }
    } catch (e) {
      debugPrint('Error parsing incoming beacon: $e');
    }
  }

  /// Scans the local hotspot subnet (e.g. 192.168.43.1 - 192.168.43.254)
  /// by testing port 8888 connectivity for immediate zero-config pairing.
  Future<List<HotspotPeer>> scanHotspotSubnet() async {
    if (_isScanning) return currentPeers;
    _isScanning = true;
    _updateStatus('Scanning hotspot subnet for iTantra transceivers...');

    final localIp = await getPrimaryIpAddress();
    final baseSubnet = localIp != null && localIp.contains('.')
        ? localIp.substring(0, localIp.lastIndexOf('.'))
        : '192.168.43';

    final foundPeers = <HotspotPeer>[];
    final probeTasks = <Future<void>>[];

    // Probe 1 through 254 in parallel batches of 25
    for (var i = 1; i <= 254; i++) {
      final targetIp = '$baseSubnet.$i';
      if (targetIp == localIp) continue; // skip self

      probeTasks.add(() async {
        try {
          final socket = await Socket.connect(
            targetIp,
            TransceiverManager.port,
            timeout: const Duration(milliseconds: 350),
          );
          socket.destroy();

          final peer = HotspotPeer(
            id: 'NODE_$i',
            name: i == 1 ? 'Hotspot Base Station ($targetIp)' : 'iTantra Peer ($targetIp)',
            ipAddress: targetIp,
            port: TransceiverManager.port,
            lastSeen: DateTime.now(),
            isHost: i == 1,
          );
          _discoveredPeers[targetIp] = peer;
          foundPeers.add(peer);
        } catch (_) {
          // host not responding on 8888, ignore
        }
      }());

      if (probeTasks.length >= 25) {
        await Future.wait(probeTasks);
        probeTasks.clear();
      }
    }

    if (probeTasks.isNotEmpty) {
      await Future.wait(probeTasks);
    }

    _isScanning = false;
    _peersController.add(currentPeers);
    _updateStatus('Scan complete: ${foundPeers.length} active node(s) found');
    return currentPeers;
  }

  /// Connects directly to a peer or hotspot host by IP.
  Future<bool> connectToHotspotPeer(String ipAddress) async {
    _updateStatus('Connecting to $ipAddress...');
    final success = await transceiverManager.connectToPeer(ipAddress);
    if (success) {
      _updateStatus('Connected to $ipAddress');
    } else {
      _updateStatus('Failed to connect to $ipAddress');
    }
    return success;
  }

  /// One-tap connection to Hotspot Host (Base Station).
  Future<bool> connectToHotspotHost() async {
    final localIp = await getPrimaryIpAddress();
    final hostIp = getSuggestedHotspotHostIp(localIp);
    return await connectToHotspotPeer(hostIp);
  }

  void _updateStatus(String status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    stopBeaconBroadcaster();
    _receiverSocket?.close();
    _receiverSocket = null;
    _peersController.close();
    _statusController.close();
  }
}
