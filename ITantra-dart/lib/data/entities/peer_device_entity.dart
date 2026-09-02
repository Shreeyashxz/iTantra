class PeerDeviceEntity {
  final String deviceId;
  final String displayName;
  final int lastConnected;
  final String transportType;
  final bool isConnected;

  PeerDeviceEntity({
    required this.deviceId,
    required this.displayName,
    int? lastConnected,
    this.transportType = 'WIFI_DIRECT',
    this.isConnected = false,
  }) : lastConnected = lastConnected ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'displayName': displayName,
    'lastConnected': lastConnected,
    'transportType': transportType,
    'isConnected': isConnected ? 1 : 0,
  };

  factory PeerDeviceEntity.fromMap(Map<String, dynamic> map) => PeerDeviceEntity(
    deviceId: map['deviceId'] as String? ?? '',
    displayName: map['displayName'] as String? ?? '',
    lastConnected: map['lastConnected'] as int? ?? 0,
    transportType: map['transportType'] as String? ?? 'WIFI_DIRECT',
    isConnected: (map['isConnected'] as int? ?? 0) == 1,
  );
}
