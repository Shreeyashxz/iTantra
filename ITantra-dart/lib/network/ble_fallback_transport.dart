import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../proto/transceiver_packet.dart';

/// Represents a nearby iTantra node discovered via Bluetooth Low Energy advertisements.
class BleDiscoveredPeer {
  final String name;
  final String address;
  final int rssi;
  final DateTime lastSeen;

  BleDiscoveredPeer({
    required this.name,
    required this.address,
    required this.rssi,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -85) return 2;
    return 1;
  }

  @override
  String toString() => '$name ($address, ${rssi}dBm)';
}

/// Bluetooth Low Energy (BLE) GATT Fallback Transport
///
/// Designed as a secondary radio link for iTantra when Wi-Fi Direct or local
/// mesh networking is unavailable, obstructed, or out of range.
///
/// Features:
/// 1. Low-power (< 15mW) secondary physical layer.
/// 2. Automatic packet MTU fragmentation (180-byte chunks) & reassembly.
/// 3. Native Android GATT Server (Advertising/Peripheral) & GATT Client (Central) via Platform Channels.
/// 4. Graceful in-memory simulation & loopback fallback for unit tests and desktop execution.
/// 5. Automatic stale buffer garbage collection (10s expiry).
class BleFallbackTransport {
  static const String serviceUuid = '0000FE60-0000-1000-8000-00805F9B34FB';
  static const String charTxUuid = '0000FE61-0000-1000-8000-00805F9B34FB';
  static const String charRxUuid = '0000FE62-0000-1000-8000-00805F9B34FB';

  static const _methodChannel = MethodChannel('com.itantra/ble');
  static const _eventChannel = EventChannel('com.itantra/ble_events');

  /// Standard BLE ATT default payload size (23 - 3 byte header = 20 bytes safe payload)
  /// Negotiable up to 512 bytes on Android 8.0+
  static const int defaultChunkSize = 180;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  bool _isAdvertising = false;
  bool _isScanning = false;
  bool _isConnected = false;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;

  String? _connectedPeerName;
  String? get connectedPeerName => _connectedPeerName;

  String? _connectedPeerAddress;
  String? get connectedPeerAddress => _connectedPeerAddress;

  final List<BleDiscoveredPeer> _discoveredPeers = [];
  List<BleDiscoveredPeer> get discoveredPeers => List.unmodifiable(_discoveredPeers);

  final _incomingPacketsController = StreamController<TransceiverPacket>.broadcast();
  Stream<TransceiverPacket> get incomingPackets => _incomingPacketsController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _peersController = StreamController<List<BleDiscoveredPeer>>.broadcast();
  Stream<List<BleDiscoveredPeer>> get peersStream => _peersController.stream;

  String _status = 'Standby';
  String get status => _status;

  // In-flight reassembly buffer: packetId -> Map<fragmentIndex, bytes>
  final Map<int, Map<int, Uint8List>> _reassemblyBuffers = {};
  final Map<int, int> _expectedFragments = {};
  final Map<int, DateTime> _fragmentTimestamps = {};

  int _nextPacketId = 1;

  // Metrics
  int totalChunksSent = 0;
  int totalChunksReceived = 0;
  int totalPacketsSent = 0;
  int totalPacketsReassembled = 0;

  StreamSubscription? _eventSubscription;

  BleFallbackTransport() {
    if (isSupported) {
      _initPlatformEventListener();
    }
  }

  void _initPlatformEventListener() {
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final type = event['eventType'] as String?;
            switch (type) {
              case 'PEER_DISCOVERED':
                final name = event['name'] as String? ?? 'Nearby iTantra Node';
                final address = event['address'] as String? ?? '';
                final rssi = event['rssi'] as int? ?? -70;
                _handleDiscoveredPeer(name, address, rssi);
                break;

              case 'CONNECTION_STATE':
                final connected = event['connected'] as bool? ?? false;
                _isConnected = connected;
                if (connected) {
                  _connectedPeerAddress = event['address'] as String?;
                  _connectedPeerName = event['name'] as String? ?? 'iTantra Remote Peer';
                  _updateStatus('Connected to ${_connectedPeerName ?? _connectedPeerAddress}');
                } else {
                  _connectedPeerAddress = null;
                  _connectedPeerName = null;
                  _updateStatus('Disconnected');
                }
                break;

              case 'ADVERTISING_STATE':
                final adv = event['advertising'] as bool? ?? false;
                _isAdvertising = adv;
                _updateStatus(adv ? 'Advertising as iTantra Node' : 'Advertising Stopped');
                break;

              case 'SCAN_STATE':
                final scan = event['scanning'] as bool? ?? false;
                _isScanning = scan;
                _updateStatus(scan ? 'Scanning for nearby BLE peers...' : 'Scan Idle');
                break;

              case 'GATT_CHUNK_RECEIVED':
                final chunk = event['chunk'];
                if (chunk is Uint8List) {
                  receiveGattChunk(chunk);
                } else if (chunk is List) {
                  receiveGattChunk(Uint8List.fromList(chunk.cast<int>()));
                }
                break;
            }
          }
        },
        onError: (e) {
          debugPrint('[BLE Fallback] EventChannel error: $e');
        },
      );
    } catch (e) {
      debugPrint('[BLE Fallback] Failed to register EventChannel: $e');
    }
  }

  void _handleDiscoveredPeer(String name, String address, int rssi) {
    final idx = _discoveredPeers.indexWhere((p) => p.address == address);
    final peer = BleDiscoveredPeer(
      name: name,
      address: address,
      rssi: rssi,
      lastSeen: DateTime.now(),
    );

    if (idx >= 0) {
      _discoveredPeers[idx] = peer;
    } else {
      _discoveredPeers.add(peer);
    }
    _peersController.add(List.unmodifiable(_discoveredPeers));
  }

  void _updateStatus(String newStatus) {
    _status = newStatus;
    _statusController.add(_status);
    debugPrint('[BLE Fallback] $newStatus');
  }

  /// Starts advertising this device as a BLE Peripheral (GATT Server).
  Future<bool> startAdvertising([String? name]) async {
    _isAdvertising = true;
    _updateStatus('Advertising as ${name ?? "iTantra-Node"}');

    if (isSupported) {
      try {
        final ok = await _methodChannel.invokeMethod<bool>('startAdvertising', {
          'name': name ?? 'iTantra-Node',
        });
        return ok ?? true;
      } catch (e) {
        debugPrint('[BLE Fallback] Native startAdvertising error: $e');
      }
    }
    return true;
  }

  /// Stops BLE Peripheral advertising.
  Future<bool> stopAdvertising() async {
    _isAdvertising = false;
    _updateStatus('Advertising stopped');

    if (isSupported) {
      try {
        await _methodChannel.invokeMethod('stopAdvertising');
      } catch (e) {
        debugPrint('[BLE Fallback] Native stopAdvertising error: $e');
      }
    }
    return true;
  }

  /// Starts scanning for nearby iTantra BLE peers (GATT Client mode).
  Future<bool> startScanning() async {
    _isScanning = true;
    _updateStatus('Scanning for nearby iTantra peers...');

    if (isSupported) {
      try {
        final ok = await _methodChannel.invokeMethod<bool>('startScanning');
        return ok ?? true;
      } catch (e) {
        debugPrint('[BLE Fallback] Native startScanning error: $e');
      }
    }
    return true;
  }

  /// Stops BLE scanning.
  Future<bool> stopScanning() async {
    _isScanning = false;
    _updateStatus('Scanning stopped');

    if (isSupported) {
      try {
        await _methodChannel.invokeMethod('stopScanning');
      } catch (e) {
        debugPrint('[BLE Fallback] Native stopScanning error: $e');
      }
    }
    return true;
  }

  /// Connects to a remote peer via BLE GATT.
  Future<bool> connectToPeer(String address, [String? name]) async {
    _updateStatus('Connecting to ${name ?? address}...');

    if (isSupported) {
      try {
        final ok = await _methodChannel.invokeMethod<bool>('connect', {
          'address': address,
        });
        if (ok == true) {
          _isConnected = true;
          _connectedPeerAddress = address;
          _connectedPeerName = name ?? address;
          _updateStatus('Connected to ${_connectedPeerName!}');
          return true;
        }
      } catch (e) {
        debugPrint('[BLE Fallback] Native connect error: $e');
      }
    }

    // Fallback simulation mode
    if (kDebugMode) {
      simulatePeerConnected(name ?? 'Simulated Node', address);
      return true;
    }
    return false;
  }

  /// Disconnects the active BLE GATT link.
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPeerName = null;
    _connectedPeerAddress = null;
    _updateStatus('Disconnected');

    if (isSupported) {
      try {
        await _methodChannel.invokeMethod('disconnect');
      } catch (e) {
        debugPrint('[BLE Fallback] Native disconnect error: $e');
      }
    }
  }

  /// Simulates a successful connection to a remote BLE peer (useful for desktop and tests).
  void simulatePeerConnected([String deviceName = 'Simulated Field Node', String? address]) {
    _isConnected = true;
    _connectedPeerName = deviceName;
    _connectedPeerAddress = address ?? 'AA:BB:CC:DD:EE:FF';
    _updateStatus('Connected to $deviceName');
    debugPrint('[BLE Fallback] Paired with peer device: $deviceName ($address)');
  }

  /// Fragments a TransceiverPacket into a list of chunks <= [mtu] bytes.
  List<Uint8List> chunkPacket(TransceiverPacket packet, {int mtu = defaultChunkSize, int? packetId}) {
    final rawBytes = packet.toProtoBytes();
    final totalBytes = rawBytes.length;
    final pId = (packetId ?? _nextPacketId++) & 0xFFFF;
    const headerSize = 4;
    final payloadCapacity = mtu - headerSize;
    final totalFragments = (totalBytes / payloadCapacity).ceil();

    final chunks = <Uint8List>[];
    for (int i = 0; i < totalFragments; i++) {
      final start = i * payloadCapacity;
      final end = (start + payloadCapacity > totalBytes) ? totalBytes : start + payloadCapacity;
      final slice = rawBytes.sublist(start, end);

      final fragment = Uint8List(headerSize + slice.length);
      final byteData = ByteData.sublistView(fragment);

      byteData.setUint16(0, pId, Endian.big);
      fragment[2] = i;
      fragment[3] = totalFragments;
      fragment.setRange(4, 4 + slice.length, slice);
      chunks.add(fragment);
    }
    return chunks;
  }

  /// Fragments and transmits a TransceiverPacket over BLE GATT.
  Future<bool> sendPacket(TransceiverPacket packet, {int mtu = defaultChunkSize}) async {
    final chunks = chunkPacket(packet, mtu: mtu);
    final totalFragments = chunks.length;

    debugPrint('[BLE Fallback] Sending packet across $totalFragments BLE fragments');

    for (final fragment in chunks) {
      await _transmitGattChunk(fragment);
      totalChunksSent++;

      if (totalFragments > 1) {
        await Future.delayed(const Duration(milliseconds: 15));
      }
    }
    totalPacketsSent++;

    return true;
  }

  Future<void> _transmitGattChunk(Uint8List chunk) async {
    if (isSupported) {
      try {
        await _methodChannel.invokeMethod('sendChunk', {'chunk': chunk});
      } catch (e) {
        debugPrint('[BLE Fallback] Native sendChunk error: $e');
      }
    }
    debugPrint('[BLE Fallback] Transmitted chunk: ${chunk.length} bytes');
  }

  /// Ingests an incoming BLE GATT chunk and reassembles fragmented packets.
  void receiveGattChunk(Uint8List chunk) {
    if (chunk.length < 4) return;
    totalChunksReceived++;

    final byteData = ByteData.sublistView(chunk);
    final packetId = byteData.getUint16(0, Endian.big);
    final fragmentIndex = chunk[2];
    final totalFragments = chunk[3];
    final payload = chunk.sublist(4);

    _cleanupStaleBuffers();

    _reassemblyBuffers.putIfAbsent(packetId, () => {});
    _reassemblyBuffers[packetId]![fragmentIndex] = payload;
    _expectedFragments[packetId] = totalFragments;
    _fragmentTimestamps[packetId] = DateTime.now();

    // Check if all fragments have arrived
    final fragments = _reassemblyBuffers[packetId]!;
    if (fragments.length == totalFragments) {
      // Reassemble complete packet
      final completeBytesBuilder = BytesBuilder(copy: false);
      for (int i = 0; i < totalFragments; i++) {
        final part = fragments[i];
        if (part != null) {
          completeBytesBuilder.add(part);
        }
      }

      final completeBytes = completeBytesBuilder.toBytes();
      _reassemblyBuffers.remove(packetId);
      _expectedFragments.remove(packetId);
      _fragmentTimestamps.remove(packetId);

      try {
        final packet = TransceiverPacket.fromProtoBytes(completeBytes);
        totalPacketsReassembled++;
        debugPrint('[BLE Fallback] Packet #$packetId successfully reassembled (${completeBytes.length} bytes)');
        _incomingPacketsController.add(packet);
      } catch (e) {
        debugPrint('[BLE Fallback] Deserialization error on packet #$packetId: $e');
      }
    }
  }

  /// Number of pending fragmented packet reassembly buffers.
  int get activePendingBuffersCount => _reassemblyBuffers.length;

  /// Diagnostic loopback test: fragments a test packet, routes chunks directly through
  /// `receiveGattChunk()`, and checks whether the packet round-trips losslessly.
  Future<Map<String, dynamic>> testLoopback([TransceiverPacket? testPacket]) async {
    final packet = testPacket ?? TransceiverPacket(
      senderId: 'LOOPBACK_NODE',
      languageCode: 'hi',
      transcript: 'परीक्षण संदेश: 180B MTU विखंडन और पुनर्संयोजन सत्यापन। Emergency Radio Test.',
      type: PacketType.voice,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final completer = Completer<bool>();
    StreamSubscription? sub;

    sub = incomingPackets.listen((p) {
      if (p.transcript == packet.transcript &&
          p.senderId == packet.senderId) {
        if (!completer.isCompleted) completer.complete(true);
      }
    });

    final chunks = chunkPacket(packet, packetId: 9999);
    for (final chunk in chunks) {
      receiveGattChunk(chunk);
    }

    final success = await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );

    await sub.cancel();
    return {
      'success': success,
      'chunks': chunks.length,
      'bytes': packet.toProtoBytes().length,
      'message': success ? 'Integrity verified: all fragments reassembled losslessly.' : 'Loopback test timed out.',
    };
  }

  /// Cleans up stale reassembly buffers older than 10 seconds (or all if [forceAll] is true).
  void cleanStaleBuffers({bool forceAll = false}) {
    if (forceAll) {
      _reassemblyBuffers.clear();
      _expectedFragments.clear();
      _fragmentTimestamps.clear();
      return;
    }
    final now = DateTime.now();
    final expired = <int>[];
    _fragmentTimestamps.forEach((id, time) {
      if (now.difference(time).inSeconds > 10) {
        expired.add(id);
      }
    });
    for (final id in expired) {
      _reassemblyBuffers.remove(id);
      _expectedFragments.remove(id);
      _fragmentTimestamps.remove(id);
    }
  }

  void _cleanupStaleBuffers() {
    cleanStaleBuffers(forceAll: false);
  }

  void dispose() {
    _eventSubscription?.cancel();
    _incomingPacketsController.close();
    _statusController.close();
    _peersController.close();
    _reassemblyBuffers.clear();
    _expectedFragments.clear();
    _fragmentTimestamps.clear();
  }
}
