import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'transceiver_manager.dart';

class WifiP2pPeer {
  final String deviceName;
  final String deviceAddress;
  final String primaryDeviceType;
  final int status; // 0 = Connected, 1 = Invited, 2 = Failed, 3 = Available, 4 = Unavailable
  final bool isGroupOwner;

  const WifiP2pPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.primaryDeviceType,
    required this.status,
    required this.isGroupOwner,
  });

  String get statusLabel {
    switch (status) {
      case 0:
        return 'Connected';
      case 1:
        return 'Invited';
      case 2:
        return 'Failed';
      case 3:
        return 'Available';
      case 4:
        return 'Unavailable';
      default:
        return 'Unknown';
    }
  }

  factory WifiP2pPeer.fromMap(Map<dynamic, dynamic> map) {
    return WifiP2pPeer(
      deviceName: map['deviceName'] as String? ?? 'Nearby Device',
      deviceAddress: map['deviceAddress'] as String? ?? '',
      primaryDeviceType: map['primaryDeviceType'] as String? ?? '',
      status: map['status'] as int? ?? 3,
      isGroupOwner: map['isGroupOwner'] as bool? ?? false,
    );
  }
}

class WifiP2pConnectionInfo {
  final bool groupFormed;
  final bool isGroupOwner;
  final String groupOwnerAddress;

  const WifiP2pConnectionInfo({
    required this.groupFormed,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });

  factory WifiP2pConnectionInfo.fromMap(Map<dynamic, dynamic> map) {
    return WifiP2pConnectionInfo(
      groupFormed: map['groupFormed'] as bool? ?? false,
      isGroupOwner: map['isGroupOwner'] as bool? ?? false,
      groupOwnerAddress: map['groupOwnerAddress'] as String? ?? '',
    );
  }
}

class WifiDirectP2pService {
  static const _methodChannel = MethodChannel('com.itantra/wifi_direct');
  static const _eventChannel = EventChannel('com.itantra/wifi_direct_events');

  final TransceiverManager transceiverManager;

  final _peersController = StreamController<List<WifiP2pPeer>>.broadcast();
  Stream<List<WifiP2pPeer>> get peersStream => _peersController.stream;
  List<WifiP2pPeer> _currentPeers = [];
  List<WifiP2pPeer> get currentPeers => _currentPeers;

  final _connectionController = StreamController<WifiP2pConnectionInfo>.broadcast();
  Stream<WifiP2pConnectionInfo> get connectionStream => _connectionController.stream;
  WifiP2pConnectionInfo _currentConnection = const WifiP2pConnectionInfo(
    groupFormed: false,
    isGroupOwner: false,
    groupOwnerAddress: '',
  );
  WifiP2pConnectionInfo get currentConnection => _currentConnection;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  String _status = 'Standby';
  String get status => _status;

  StreamSubscription? _eventSub;
  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  WifiDirectP2pService({required this.transceiverManager}) {
    if (isSupported) {
      _initEventListener();
    }
  }

  void _initEventListener() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final type = event['eventType'] as String?;
          switch (type) {
            case 'STATE_CHANGED':
              final enabled = event['enabled'] as bool? ?? false;
              _updateStatus(enabled ? 'Wi-Fi Direct Active' : 'Wi-Fi Direct Disabled');
              break;

            case 'PEERS_CHANGED':
              final rawPeers = event['peers'] as List? ?? [];
              _currentPeers = rawPeers
                  .map((p) => WifiP2pPeer.fromMap(p as Map<dynamic, dynamic>))
                  .toList();
              _peersController.add(_currentPeers);
              break;

            case 'CONNECTION_CHANGED':
              _currentConnection = WifiP2pConnectionInfo.fromMap(event);
              _connectionController.add(_currentConnection);
              _handleGroupConnection(_currentConnection);
              break;

            case 'THIS_DEVICE_CHANGED':
              final name = event['deviceName'] as String? ?? '';
              debugPrint('[Wi-Fi Direct] This device name: $name');
              break;
          }
        }
      },
      onError: (err) {
        debugPrint('[Wi-Fi Direct] Event channel error: $err');
      },
    );
  }

  void _updateStatus(String newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  Future<void> _handleGroupConnection(WifiP2pConnectionInfo info) async {
    if (info.groupFormed) {
      if (info.isGroupOwner) {
        _updateStatus('P2P Group Formed (Group Owner / Host)');
        await transceiverManager.startServer();
      } else {
        _updateStatus('P2P Group Formed (Client -> ${info.groupOwnerAddress})');
        if (info.groupOwnerAddress.isNotEmpty) {
          await transceiverManager.connectToPeer(info.groupOwnerAddress);
        }
      }
    } else {
      _updateStatus('P2P Disconnected');
    }
  }

  Future<bool> startDiscovery() async {
    if (!isSupported) return false;
    try {
      _updateStatus('Scanning for Wi-Fi Direct devices...');
      _isDiscovering = true;
      final res = await _methodChannel.invokeMethod<bool>('startDiscovery') ?? false;
      return res;
    } catch (e) {
      _updateStatus('P2P Discovery failed: $e');
      _isDiscovering = false;
      return false;
    }
  }

  Future<bool> stopDiscovery() async {
    if (!isSupported) return false;
    try {
      _isDiscovering = false;
      final res = await _methodChannel.invokeMethod<bool>('stopDiscovery') ?? false;
      return res;
    } catch (e) {
      return false;
    }
  }

  Future<bool> connect(String deviceAddress) async {
    if (!isSupported) return false;
    try {
      _updateStatus('Connecting to $deviceAddress via P2P...');
      final res = await _methodChannel.invokeMethod<bool>('connect', {
        'deviceAddress': deviceAddress,
      }) ?? false;
      return res;
    } catch (e) {
      _updateStatus('Connect failed: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    if (!isSupported) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('disconnect') ?? false;
      _currentConnection = const WifiP2pConnectionInfo(
        groupFormed: false,
        isGroupOwner: false,
        groupOwnerAddress: '',
      );
      _connectionController.add(_currentConnection);
      return res;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _peersController.close();
    _connectionController.close();
    _statusController.close();
  }
}
