import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../proto/transceiver_packet.dart';

class TransceiverManager {
  static const int port = 8888;

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _activeSockets = [];

  final _incomingPacketsController = StreamController<TransceiverPacket>.broadcast();
  Stream<TransceiverPacket> get incomingPackets => _incomingPacketsController.stream;

  final _connectionStateController = StreamController<String>.broadcast();
  Stream<String> get connectionState => _connectionStateController.stream;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int get connectedPeersCount => _activeSockets.length;
  List<String> get connectedPeerIps =>
      _activeSockets.map((s) => s.remoteAddress.address).toSet().toList();

  void _updateConnectionState() {
    final count = _activeSockets.length;
    if (count > 0) {
      final ips = connectedPeerIps.join(', ');
      _connectionStateController.add('Connected ($count peer${count > 1 ? "s" : ""}: $ips)');
    } else if (_isRunning) {
      _connectionStateController.add('Listening on port $port');
    } else {
      _connectionStateController.add('Disconnected');
    }
  }

  Future<void> startServer() async {
    if (_serverSocket != null) return;
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _updateConnectionState();
      debugPrint('Transceiver server listening on port $port');

      _serverSocket!.listen(
        (socket) {
          debugPrint('Inbound peer connected from ${socket.remoteAddress.address}:${socket.remotePort}');
          _handleIncomingConnection(socket);
        },
        onError: (error) {
          debugPrint('Transceiver server error: $error');
          _connectionStateController.add('Server error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to start transceiver server: $e');
      _connectionStateController.add('Server error: $e');
    }
  }

  Future<bool> connectToPeer(String ipAddress) async {
    try {
      // Don't connect if already connected to this IP
      final alreadyConnected = _activeSockets.any((s) => s.remoteAddress.address == ipAddress);
      if (alreadyConnected) {
        _updateConnectionState();
        return true;
      }

      final socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 4));
      _clientSocket = socket;
      _handleIncomingConnection(socket);
      debugPrint('Connected outbound to peer at $ipAddress:$port');
      return true;
    } catch (e) {
      debugPrint('Failed to connect to peer $ipAddress: $e');
      _connectionStateController.add('Failed to connect to $ipAddress');
      return false;
    }
  }

  void _handleIncomingConnection(Socket socket) {
    _activeSockets.add(socket);
    _updateConnectionState();
    final buffer = BytesBuilder();

    socket.listen(
      (data) {
        buffer.add(data);
        var currentBytes = buffer.toBytes();

        while (true) {
          final res = TransceiverPacket.parseDelimited(currentBytes);
          if (res.packet != null) {
            _incomingPacketsController.add(res.packet!);
            currentBytes = currentBytes.sublist(res.bytesConsumed);
            buffer.clear();
            buffer.add(currentBytes);
          } else {
            break;
          }
        }
      },
      onError: (e) {
        debugPrint('Socket error from ${socket.remoteAddress.address}: $e');
        _activeSockets.remove(socket);
        _updateConnectionState();
      },
      onDone: () {
        debugPrint('Socket closed: ${socket.remoteAddress.address}');
        _activeSockets.remove(socket);
        _updateConnectionState();
      },
      cancelOnError: true,
    );
  }

  Future<void> sendPacket(TransceiverPacket packet) async {
    if (_activeSockets.isEmpty) {
      debugPrint('No active peer sockets to send packet.');
      return;
    }

    for (final socket in List<Socket>.from(_activeSockets)) {
      try {
        packet.writeDelimitedTo(socket);
        await socket.flush();
      } catch (e) {
        debugPrint('Error writing to socket ${socket.remoteAddress.address}: $e');
        _activeSockets.remove(socket);
        _updateConnectionState();
      }
    }
  }

  void stop() {
    _isRunning = false;
    _serverSocket?.close();
    _serverSocket = null;
    _clientSocket?.destroy();
    _clientSocket = null;
    for (final s in _activeSockets) {
      s.destroy();
    }
    _activeSockets.clear();
    _connectionStateController.add('Disconnected');
  }

  void dispose() {
    stop();
    _incomingPacketsController.close();
    _connectionStateController.close();
  }
}
