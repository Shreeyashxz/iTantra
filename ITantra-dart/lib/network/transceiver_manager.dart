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

  Future<void> startServer() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _connectionStateController.add('Server listening on port $port');
      debugPrint('Transceiver server listening on port $port');

      _serverSocket!.listen(
        (socket) {
          _handleIncomingConnection(socket);
        },
        onError: (error) {
          debugPrint('Transceiver server error: $error');
          _connectionStateController.add('Server error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to start transceiver server: $e');
      _connectionStateController.add('Failed to start server: $e');
    }
  }

  Future<bool> connectToPeer(String ipAddress) async {
    try {
      _clientSocket?.destroy();
      _clientSocket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5));
      _handleIncomingConnection(_clientSocket!);
      _connectionStateController.add('Connected to peer at $ipAddress');
      debugPrint('Connected to peer at $ipAddress:$port');
      return true;
    } catch (e) {
      debugPrint('Failed to connect to peer $ipAddress: $e');
      _connectionStateController.add('Connection failed: $e');
      return false;
    }
  }

  void _handleIncomingConnection(Socket socket) {
    _activeSockets.add(socket);
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
      },
      onDone: () {
        debugPrint('Socket closed: ${socket.remoteAddress.address}');
        _activeSockets.remove(socket);
      },
      cancelOnError: true,
    );
  }

  Future<void> sendPacket(TransceiverPacket packet) async {
    try {
      // Send to connected peer client socket if active
      if (_clientSocket != null) {
        packet.writeDelimitedTo(_clientSocket!);
        await _clientSocket!.flush();
      }

      // Also broadcast to any incoming sockets connected to our server
      for (final socket in List<Socket>.from(_activeSockets)) {
        if (socket != _clientSocket) {
          try {
            packet.writeDelimitedTo(socket);
            await socket.flush();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error sending packet: $e');
    }
  }

  /// Direct injection for testing or mock loops
  void emitSimulatedPacket(TransceiverPacket packet) {
    _incomingPacketsController.add(packet);
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
