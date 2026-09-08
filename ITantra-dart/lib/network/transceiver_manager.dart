import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../proto/transceiver_packet.dart';

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

  ServerSocket? _serverSocket;
  final Map<String, Socket> _peerSockets = {};
  final Map<String, PeerLinkStats> _peerStats = {};

  final _incomingPacketsController = StreamController<TransceiverPacket>.broadcast();
  Stream<TransceiverPacket> get incomingPackets => _incomingPacketsController.stream;

  final _connectionStateController = StreamController<String>.broadcast();
  Stream<String> get connectionState => _connectionStateController.stream;

  final _statsController = StreamController<List<PeerLinkStats>>.broadcast();
  Stream<List<PeerLinkStats>> get statsStream => _statsController.stream;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int get connectedPeersCount => _peerSockets.length;
  List<String> get connectedPeerIps => _peerSockets.keys.toList();
  List<PeerLinkStats> get activePeerStats => _peerStats.values.toList();

  int? get averageRttMs {
    final active = _peerStats.values.where((s) => s.rttMs > 0);
    if (active.isEmpty) return null;
    return (active.map((s) => s.rttMs).reduce((a, b) => a + b) / active.length).round();
  }

  int totalPacketsSent = 0;
  int totalPacketsReceived = 0;

  Timer? _heartbeatTimer;

  void _updateConnectionState() {
    final count = _peerSockets.length;
    if (count > 0) {
      final ips = _peerSockets.keys.join(', ');
      _connectionStateController.add('Connected ($count peer${count > 1 ? "s" : ""}: $ips)');
    } else if (_isRunning) {
      _connectionStateController.add('Listening on port $port (Ready to pair)');
    } else {
      _connectionStateController.add('Disconnected');
    }
    _statsController.add(activePeerStats);
  }

  Future<void> startServer() async {
    if (_serverSocket != null) return;
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
      _isRunning = true;
      _updateConnectionState();
      debugPrint('Transceiver server active on 0.0.0.0:$port');

      _serverSocket!.listen(
        (socket) {
          final remoteIp = socket.remoteAddress.address;
          debugPrint('Inbound connection received from $remoteIp:${socket.remotePort}');
          _attachSocket(socket, remoteIp);
        },
        onError: (error) {
          debugPrint('Transceiver server error: $error');
          _connectionStateController.add('Server error: $error');
        },
      );

      _startHeartbeat();
    } catch (e) {
      debugPrint('Failed to start transceiver server on port $port: $e');
      _connectionStateController.add('Port $port busy: $e');
    }
  }

  Future<bool> connectToPeer(String ipAddress, {int targetPort = port}) async {
    // Avoid self-connection
    if (ipAddress == '127.0.0.1' || ipAddress == '0.0.0.0') return false;

    // Check if already connected
    if (_peerSockets.containsKey(ipAddress)) {
      _updateConnectionState();
      return true;
    }

    try {
      final socket = await Socket.connect(
        ipAddress,
        targetPort,
        timeout: const Duration(seconds: 3),
      );
      _attachSocket(socket, ipAddress);
      debugPrint('Outbound connection established to $ipAddress:$targetPort');
      return true;
    } catch (e) {
      debugPrint('Failed connecting to peer at $ipAddress:$targetPort: $e');
      return false;
    }
  }

  void _attachSocket(Socket socket, String ipAddress) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    // Close any previous socket for this IP
    final existing = _peerSockets[ipAddress];
    if (existing != null && existing != socket) {
      existing.destroy();
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
            } else if (packet.type == PacketType.ack && packet.transcript.startsWith('PONG:')) {
              final sentTime = int.tryParse(packet.transcript.substring(5)) ?? 0;
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
        _detachSocket(ipAddress);
      },
      onDone: () {
        debugPrint('Socket disconnected from $ipAddress');
        _detachSocket(ipAddress);
      },
      cancelOnError: true,
    );
  }

  void _detachSocket(String ipAddress) {
    final socket = _peerSockets.remove(ipAddress);
    _peerStats.remove(ipAddress);
    socket?.destroy();
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
      debugPrint('No connected peers to deliver packet.');
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
    _incomingPacketsController.close();
    _connectionStateController.close();
    _statsController.close();
  }
}
