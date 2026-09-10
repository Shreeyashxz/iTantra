class UserSettingsEntity {
  final int id;
  final String preferredLanguage;
  final double ttsSpeed;
  final String ttsGender; // 'FEMALE' or 'MALE'
  final String ttsEngineType; // 'AI4BHARAT_RASA' or 'META_MMS'
  final double vadSensitivity; // 0.1 to 1.0 (default 0.6)
  final String pttMode; // 'HOLD' or 'TOGGLE'
  final String installedLanguagePacks;
  final bool alertVolumeMax;
  final bool autoPlayAudio;
  final bool isMtEnabled;
  final String sttPrecision; // 'INT8' or 'FP32'
  final String mtPrecision; // 'INT8' or 'FP16'

  UserSettingsEntity({
    this.id = 1,
    this.preferredLanguage = 'hi',
    this.ttsSpeed = 1.0,
    this.ttsGender = 'FEMALE',
    this.ttsEngineType = 'AI4BHARAT_RASA',
    this.vadSensitivity = 0.6,
    this.pttMode = 'HOLD',
    this.installedLanguagePacks = 'hi,en',
    this.alertVolumeMax = true,
    this.autoPlayAudio = true,
    this.isMtEnabled = true,
    this.sttPrecision = 'INT8',
    this.mtPrecision = 'INT8',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'preferredLanguage': preferredLanguage,
    'ttsSpeed': ttsSpeed,
    'ttsGender': ttsGender,
    'ttsEngineType': ttsEngineType,
    'vadSensitivity': vadSensitivity,
    'pttMode': pttMode,
    'installedLanguagePacks': installedLanguagePacks,
    'alertVolumeMax': alertVolumeMax ? 1 : 0,
    'autoPlayAudio': autoPlayAudio ? 1 : 0,
    'isMtEnabled': isMtEnabled ? 1 : 0,
    'sttPrecision': sttPrecision,
    'mtPrecision': mtPrecision,
  };

  factory UserSettingsEntity.fromMap(Map<String, dynamic> map) => UserSettingsEntity(
    id: map['id'] as int? ?? 1,
    preferredLanguage: map['preferredLanguage'] as String? ?? 'hi',
    ttsSpeed: (map['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
    ttsGender: map['ttsGender'] as String? ?? 'FEMALE',
    ttsEngineType: map['ttsEngineType'] as String? ?? 'AI4BHARAT_RASA',
    vadSensitivity: (map['vadSensitivity'] as num?)?.toDouble() ?? 0.6,
    pttMode: map['pttMode'] as String? ?? 'HOLD',
    installedLanguagePacks: map['installedLanguagePacks'] as String? ?? 'hi,en',
    alertVolumeMax: (map['alertVolumeMax'] as int? ?? 1) == 1,
    autoPlayAudio: (map['autoPlayAudio'] as int? ?? 1) == 1,
    isMtEnabled: (map['isMtEnabled'] as int? ?? 1) == 1,
    sttPrecision: map['sttPrecision'] as String? ?? 'INT8',
    mtPrecision: map['mtPrecision'] as String? ?? 'INT8',
  );

  UserSettingsEntity copyWith({
    int? id,
    String? preferredLanguage,
    double? ttsSpeed,
    String? ttsGender,
    String? ttsEngineType,
    double? vadSensitivity,
    String? pttMode,
    String? installedLanguagePacks,
    bool? alertVolumeMax,
    bool? autoPlayAudio,
    bool? isMtEnabled,
    String? sttPrecision,
    String? mtPrecision,
  }) => UserSettingsEntity(
    id: id ?? this.id,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    ttsGender: ttsGender ?? this.ttsGender,
    ttsEngineType: ttsEngineType ?? this.ttsEngineType,
    vadSensitivity: vadSensitivity ?? this.vadSensitivity,
    pttMode: pttMode ?? this.pttMode,
    installedLanguagePacks: installedLanguagePacks ?? this.installedLanguagePacks,
    alertVolumeMax: alertVolumeMax ?? this.alertVolumeMax,
    autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
    isMtEnabled: isMtEnabled ?? this.isMtEnabled,
    sttPrecision: sttPrecision ?? this.sttPrecision,
    mtPrecision: mtPrecision ?? this.mtPrecision,
  );
}
