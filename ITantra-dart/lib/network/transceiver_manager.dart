import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../proto/transceiver_packet.dart';
import 'ble_fallback_transport.dart';

class PeerLinkStats {
  final String ipAddress;
  final int port;
  final DateTime connectedAt;
  DateTime lastActivity;
  int packetsSent;
  int packetsReceived;
  int bytesSent;
  int bytesReceived;
  int rttMs;

  PeerLinkStats({
    required this.ipAddress,
    required this.port,
    required this.connectedAt,
    DateTime? lastActivity,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.rttMs = 0,
  }) : lastActivity = lastActivity ?? DateTime.now();
}

class TransceiverManager {
  static const int port = 8888;
  static const List<int> fallbackPorts = [8888, 8887, 8886, 8890];

  int _activePort = port;
  int get activePort => _activePort;

  String? _lastError;
  String? get lastError => _lastError;

  ServerSocket? _serverSocket;
  final Map<String, Socket> _peerSockets = {};
  final Map<String, PeerLinkStats> _peerStats = {};

  final BleFallbackTransport bleTransport = BleFallbackTransport();
  StreamSubscription<TransceiverPacket>? _bleSubscription;

  final _incomingPacketsController =
      StreamController<TransceiverPacket>.broadcast();
  Stream<TransceiverPacket> get incomingPackets =>
      _incomingPacketsController.stream;

  final _connectionStateController = StreamController<String>.broadcast();
  Stream<String> get connectionState => _connectionStateController.stream;

  final _statsController = StreamController<List<PeerLinkStats>>.broadcast();
  Stream<List<PeerLinkStats>> get statsStream => _statsController.stream;

  String get activeTransportType {
    if (_peerSockets.isNotEmpty) return 'Wi-Fi Direct / Mesh';
    if (bleTransport.isConnected) return 'BLE Fallback (GATT)';
    return 'None';
  }

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int get connectedPeersCount => _peerSockets.length;
  List<String> get connectedPeerIps => _peerSockets.keys.toList();
  List<PeerLinkStats> get activePeerStats => _peerStats.values.toList();

  int? get averageRttMs {
    final active = _peerStats.values.where((s) => s.rttMs > 0);
    if (active.isEmpty) return null;
    return (active.map((s) => s.rttMs).reduce((a, b) => a + b) / active.length)
        .round();
  }

  int totalPacketsSent = 0;
  int totalPacketsReceived = 0;

  Timer? _heartbeatTimer;

  TransceiverManager() {
    _initBleListener();
  }

  void _initBleListener() {
    _bleSubscription?.cancel();
    _bleSubscription = bleTransport.incomingPackets.listen((packet) {
      totalPacketsReceived++;
      _incomingPacketsController.add(packet);
    });
    bleTransport.statusStream.listen((_) {
      _updateConnectionState();
    });
  }

  String get currentStatusString {
    final count = _peerSockets.length;
    if (count > 0) {
      final ips = _peerSockets.keys.join(', ');
      return 'Connected ($count peer${count > 1 ? "s" : ""}: $ips)';
    } else if (bleTransport.isConnected) {
      final name = bleTransport.connectedPeerName ?? bleTransport.connectedPeerAddress ?? 'BLE Peer';
      return 'Connected (BLE Fallback: $name)';
    } else if (_isRunning) {
      return 'Listening on port $_activePort (Ready to pair)';
    } else if (_lastError != null) {
      return _lastError!;
    } else {
      return 'Disconnected';
    }
  }

  void _updateConnectionState() {
    _connectionStateController.add(currentStatusString);
    _statsController.add(activePeerStats);
  }

  Future<bool> startServer({int? preferredPort}) async {
    if (_serverSocket != null && _isRunning) {
      if (preferredPort == null || preferredPort == _activePort) {
        return true;
      }
      stop();
    }

    final portsToTry = preferredPort != null
        ? [preferredPort, ...fallbackPorts.where((p) => p != preferredPort)]
        : fallbackPorts;

    for (final tryPort in portsToTry) {
      try {
        _serverSocket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          tryPort,
          shared: true,
        );
        _activePort = tryPort;
        _isRunning = true;
        _lastError = null;
        _updateConnectionState();
        debugPrint('Transceiver server active on 0.0.0.0:$_activePort');

        _serverSocket!.listen(
          (socket) {
            final remoteIp = socket.remoteAddress.address;
            debugPrint(
              'Inbound connection received from $remoteIp:${socket.remotePort}',
            );
            _attachSocket(socket, remoteIp);
          },
          onError: (error) {
            debugPrint('Transceiver server error: $error');
            _lastError = 'Server error: $error';
            _connectionStateController.add('Server error: $error');
          },
        );

        // Listen for BLE fallback packets if received
        _bleSubscription?.cancel();
        _bleSubscription = bleTransport.incomingPackets.listen((packet) {
          totalPacketsReceived++;
          _incomingPacketsController.add(packet);
        });

        _startHeartbeat();
        return true;
      } catch (e) {
        debugPrint('Port $tryPort busy or unavailable: $e');
        _lastError = 'Port $tryPort busy';
      }
    }

    _isRunning = false;
    _connectionStateController.add('All ports (${portsToTry.join(", ")}) busy');
    return false;
  }

  Future<void> rebindPort(int newPort) async {
    await startServer(preferredPort: newPort);
  }

  /// Verifies whether the local TCP transceiver server is responsive on loopback
  Future<Map<String, dynamic>> testLocalPortConnection({int? testPort}) async {
    final target = testPort ?? _activePort;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        target,
        timeout: const Duration(milliseconds: 1500),
      );
      sw.stop();
      socket.destroy();
      return {
        'success': true,
        'port': target,
        'latencyMs': sw.elapsedMilliseconds,
        'message':
            'Port $target is OPEN and ready for transceiver traffic (~${sw.elapsedMilliseconds} ms)',
      };
    } catch (e) {
      sw.stop();
      return {
        'success': false,
        'port': target,
        'latencyMs': sw.elapsedMilliseconds,
        'message': 'Could not connect to local port $target: $e',
      };
    }
  }

  final Set<String> _connectingPeers = {};

  Future<bool> connectToPeer(String ipAddress, {int? targetPort}) async {
    final destPort = targetPort ?? _activePort;

    // Avoid self-connection in production mesh, but handle gracefully
    if (ipAddress == '127.0.0.1' || ipAddress == '0.0.0.0') {
      final testRes = await testLocalPortConnection(testPort: destPort);
      return testRes['success'] as bool;
    }

    // Check if already connected or connection already in progress
    if (_peerSockets.containsKey(ipAddress) || _connectingPeers.contains(ipAddress)) {
      _updateConnectionState();
      return true;
    }

    _connectingPeers.add(ipAddress);
    try {
      final socket = await Socket.connect(
        ipAddress,
        destPort,
        timeout: const Duration(seconds: 3),
      );
      _attachSocket(socket, ipAddress);
      debugPrint('Outbound connection established to $ipAddress:$destPort');
      return true;
    } catch (e) {
      debugPrint('Failed connecting to peer at $ipAddress:$destPort: $e');
      return false;
    } finally {
      _connectingPeers.remove(ipAddress);
    }
  }

  void _attachSocket(Socket socket, String ipAddress) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    // Close any previous socket for this IP
    final existing = _peerSockets[ipAddress];
    if (existing != null && existing != socket) {
      debugPrint(
        '[Transceiver] Replacing existing socket for $ipAddress with new link',
      );
      _peerSockets.remove(ipAddress);
      try {
        existing.destroy();
      } catch (_) {}
    }

    _peerSockets[ipAddress] = socket;
    _peerStats[ipAddress] = PeerLinkStats(
      ipAddress: ipAddress,
      port: socket.remotePort,
      connectedAt: DateTime.now(),
    );
    _updateConnectionState();

    final buffer = BytesBuilder();

    socket.listen(
      (data) {
        final stats = _peerStats[ipAddress];
        if (stats != null) {
          stats.bytesReceived += data.length;
          stats.lastActivity = DateTime.now();
        }

        buffer.add(data);
        var currentBytes = buffer.toBytes();

        while (true) {
          final res = TransceiverPacket.parseDelimited(currentBytes);
          if (res.packet != null) {
            final packet = res.packet!;
            totalPacketsReceived++;
            if (stats != null) {
              stats.packetsReceived++;
            }

            // Handle ping packet for RTT measurement
            if (packet.transcript == '__ITANTRA_PING__') {
              _sendAck(socket, packet.timestampMs);
            } else if (packet.type == PacketType.ack &&
                packet.transcript.startsWith('PONG:')) {
              final sentTime =
                  int.tryParse(packet.transcript.substring(5)) ?? 0;
              if (sentTime > 0 && stats != null) {
                stats.rttMs = DateTime.now().millisecondsSinceEpoch - sentTime;
                _statsController.add(activePeerStats);
              }
            } else {
              if (packet.type == PacketType.voice) {
                _sendAck(socket, packet.timestampMs);
              }
              _incomingPacketsController.add(packet);
            }

            currentBytes = currentBytes.sublist(res.bytesConsumed);
            buffer.clear();
            buffer.add(currentBytes);
          } else {
            break;
          }
        }
      },
      onError: (e) {
        debugPrint('Socket error on $ipAddress: $e');
        _detachSocket(ipAddress, socket);
      },
      onDone: () {
        debugPrint('Socket disconnected from $ipAddress');
        _detachSocket(ipAddress, socket);
      },
      cancelOnError: true,
    );
  }

  void _detachSocket(String ipAddress, [Socket? closedSocket]) {
    final current = _peerSockets[ipAddress];
    if (closedSocket != null && current != null && current != closedSocket) {
      debugPrint(
        '[Transceiver] Ignoring detachment for superseded socket on $ipAddress',
      );
      return;
    }
    final socket = _peerSockets.remove(ipAddress);
    _peerStats.remove(ipAddress);
    try {
      socket?.destroy();
    } catch (_) {}
    _updateConnectionState();
  }

  void disconnectPeer(String ipAddress) {
    _detachSocket(ipAddress);
  }

  void _sendAck(Socket socket, int pingTimestamp) {
    try {
      final ackPacket = TransceiverPacket(
        senderId: 'SYSTEM',
        transcript: 'PONG:$pingTimestamp',
        type: PacketType.ack,
      );
      ackPacket.writeDelimitedTo(socket);
      socket.flush();
    } catch (_) {}
  }

  Future<void> sendPacket(TransceiverPacket packet) async {
    if (_peerSockets.isEmpty) {
      if (bleTransport.isConnected) {
        debugPrint(
          '[Transceiver] Wi-Fi peers unavailable. Routing via BLE fallback transport...',
        );
        totalPacketsSent++;
        await bleTransport.sendPacket(packet);
        return;
      }
      debugPrint('No connected Wi-Fi or BLE peers to deliver packet.');
      return;
    }

    final payload = packet.toProtoBytes();
    totalPacketsSent++;

    for (final entry in Map<String, Socket>.from(_peerSockets).entries) {
      final ip = entry.key;
      final socket = entry.value;
      try {
        packet.writeDelimitedTo(socket);
        await socket.flush();

        final stats = _peerStats[ip];
        if (stats != null) {
          stats.packetsSent++;
          stats.bytesSent += payload.length;
          stats.lastActivity = DateTime.now();
        }
      } catch (e) {
        debugPrint('Error writing to socket $ip: $e');
        _detachSocket(ip);
      }
    }
    _statsController.add(activePeerStats);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_peerSockets.isEmpty) return;
      final pingPacket = TransceiverPacket(
        senderId: 'SYSTEM',
        transcript: '__ITANTRA_PING__',
        type: PacketType.ack,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      for (final socket in _peerSockets.values) {
        try {
          pingPacket.writeDelimitedTo(socket);
          socket.flush();
        } catch (_) {}
      }
    });
  }

  void stop() {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _serverSocket?.close();
    _serverSocket = null;
    for (final s in _peerSockets.values) {
      s.destroy();
    }
    _peerSockets.clear();
    _peerStats.clear();
    _updateConnectionState();
  }

  void dispose() {
    stop();
    _bleSubscription?.cancel();
    bleTransport.dispose();
    _incomingPacketsController.close();
    _connectionStateController.close();
    _statsController.close();
  }
}
