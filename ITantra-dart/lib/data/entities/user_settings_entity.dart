class UserSettingsEntity {
  final int id;
  final String preferredLanguage;
  final double ttsSpeed;
  final String pttMode; // 'HOLD' or 'TOGGLE'
  final String installedLanguagePacks;
  final bool alertVolumeMax;
  final bool autoPlayAudio;

  UserSettingsEntity({
    this.id = 1,
    this.preferredLanguage = 'hi',
    this.ttsSpeed = 1.0,
    this.pttMode = 'HOLD',
    this.installedLanguagePacks = 'hi,en',
    this.alertVolumeMax = true,
    this.autoPlayAudio = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'preferredLanguage': preferredLanguage,
    'ttsSpeed': ttsSpeed,
    'pttMode': pttMode,
    'installedLanguagePacks': installedLanguagePacks,
    'alertVolumeMax': alertVolumeMax ? 1 : 0,
    'autoPlayAudio': autoPlayAudio ? 1 : 0,
  };

  factory UserSettingsEntity.fromMap(Map<String, dynamic> map) => UserSettingsEntity(
    id: map['id'] as int? ?? 1,
    preferredLanguage: map['preferredLanguage'] as String? ?? 'hi',
    ttsSpeed: (map['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
    pttMode: map['pttMode'] as String? ?? 'HOLD',
    installedLanguagePacks: map['installedLanguagePacks'] as String? ?? 'hi,en',
    alertVolumeMax: (map['alertVolumeMax'] as int? ?? 1) == 1,
    autoPlayAudio: (map['autoPlayAudio'] as int? ?? 1) == 1,
  );

  UserSettingsEntity copyWith({
    int? id,
    String? preferredLanguage,
    double? ttsSpeed,
    String? pttMode,
    String? installedLanguagePacks,
    bool? alertVolumeMax,
    bool? autoPlayAudio,
  }) => UserSettingsEntity(
    id: id ?? this.id,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    pttMode: pttMode ?? this.pttMode,
    installedLanguagePacks: installedLanguagePacks ?? this.installedLanguagePacks,
    alertVolumeMax: alertVolumeMax ?? this.alertVolumeMax,
    autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
  );
}
