import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/app_database.dart';
import '../data/entities/user_settings_entity.dart';
import '../speech/language_pack_manager.dart';
import '../speech/script_normalization_engine.dart';
import '../speech/sherpa_onnx_speech_engine.dart';

class SettingsController extends ChangeNotifier {
  final AppDatabase database;
  final LanguagePackManager languagePackManager;
  final SherpaOnnxSpeechEngine? speechEngine;

  UserSettingsEntity _settings = UserSettingsEntity();
  UserSettingsEntity get settings => _settings;

  DownloadState _downloadState = const DownloadStateIdle();
  DownloadState get downloadState => _downloadState;

  bool _isSttReady = false;
  bool get isSttReady => _isSttReady;

  bool _isSttFp32Ready = false;
  bool get isSttFp32Ready => _isSttFp32Ready;

  bool _isMtReady = false;
  bool get isMtReady => _isMtReady;

  bool _isMtFp16Ready = false;
  bool get isMtFp16Ready => _isMtFp16Ready;

  bool _isRasa13Ready = false;
  bool get isRasa13Ready => _isRasa13Ready;

  final Map<String, bool> _ttsReadyMap = {};
  bool isTtsReady(String lang) => _ttsReadyMap[lang] ?? false;
  bool get isEnTtsReady => isTtsReady('en');

  final Map<String, bool> _mmsReadyMap = {};
  bool isMmsReady(String lang) => _mmsReadyMap[lang] ?? false;

  List<LanguageMetadata> get languages => LanguagePackManager.supportedLanguages;

  StreamSubscription<DownloadState>? _downloadSubscription;

  SettingsController({
    required this.database,
    required this.languagePackManager,
    this.speechEngine,
  }) {
    _init();
  }

  Future<void> _init() async {
    _settings = await database.getSettings();
    await checkModelStatus();
    notifyListeners();

    _downloadSubscription = languagePackManager.downloadState.listen((state) async {
      _downloadState = state;
      if (state is DownloadStateCompleted) {
        await checkModelStatus();
      }
      notifyListeners();
    });
  }

  Future<void> checkModelStatus() async {
    _isSttReady = await languagePackManager.isSttAvailable();
    _isSttFp32Ready = await languagePackManager.isSttFp32Available();
    _isMtReady = await languagePackManager.isMtAvailable();
    _isMtFp16Ready = await languagePackManager.isMtFp16Available();
    _isRasa13Ready = await languagePackManager.isRasa13Available();
    for (final lang in LanguagePackManager.supportedLanguages) {
      _ttsReadyMap[lang.code] = await languagePackManager.isTtsAvailable(lang.code);
      _mmsReadyMap[lang.code] = await languagePackManager.isMmsAvailable(lang.code);
    }
    notifyListeners();
  }

  Future<void> downloadStt() async {
    await languagePackManager.downloadStt();
    await checkModelStatus();
  }

  Future<void> downloadMt() async {
    await languagePackManager.downloadMt();
    await checkModelStatus();
  }

  Future<void> deleteMt() async {
    await languagePackManager.deleteMt();
    await checkModelStatus();
  }

  Future<void> downloadMtFp16() async {
    await languagePackManager.downloadMtFp16();
    await checkModelStatus();
  }

  Future<void> deleteMtFp16() async {
    await languagePackManager.deleteMtFp16();
    await checkModelStatus();
  }

  Future<void> downloadRasa13() async {
    await languagePackManager.downloadRasa13();
    await checkModelStatus();
  }

  Future<void> deleteRasa13() async {
    await languagePackManager.deleteRasa13();
    await checkModelStatus();
  }

  Future<void> downloadTts(String languageCode) async {
    await languagePackManager.downloadTts(languageCode);
    await checkModelStatus();
  }

  Future<void> downloadAllLanguages() async {
    await languagePackManager.downloadAllLanguages();
    await checkModelStatus();
  }

  Future<void> downloadAllEssentials() async {
    await languagePackManager.downloadAllEssentials();
    await checkModelStatus();
  }

  Future<void> deleteStt() async {
    await languagePackManager.deleteStt();
    await checkModelStatus();
  }

  Future<void> downloadSttFp32() async {
    await languagePackManager.downloadSttFp32();
    await checkModelStatus();
  }

  Future<void> deleteSttFp32() async {
    await languagePackManager.deleteSttFp32();
    await checkModelStatus();
  }

  String get sttPrecision => _settings.sttPrecision;

  Future<void> updateSttPrecision(String precision) async {
    _settings = _settings.copyWith(sttPrecision: precision);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  String get mtPrecision => _settings.mtPrecision;

  Future<void> updateMtPrecision(String precision) async {
    _settings = _settings.copyWith(mtPrecision: precision);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> deleteTts(String languageCode) async {
    await languagePackManager.deleteTts(languageCode);
    await checkModelStatus();
  }

  Future<void> deleteAllModels() async {
    await languagePackManager.deleteAllModels();
    await checkModelStatus();
  }

  Future<void> updateTtsSpeed(double speed) async {
    _settings = _settings.copyWith(ttsSpeed: speed);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  String get ttsGender => _settings.ttsGender;

  Future<void> updateTtsGender(String gender) async {
    _settings = _settings.copyWith(ttsGender: gender);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  String get ttsEngineType => _settings.ttsEngineType;

  Future<void> updateTtsEngineType(String engineType) async {
    _settings = _settings.copyWith(ttsEngineType: engineType);
    await database.saveSettings(_settings);
    // Immediately switch the active in-memory TTS engine in RAM
    try {
      speechEngine?.unloadTts();
      await speechEngine?.initTts(_settings.preferredLanguage, engineType);
    } catch (e) {
      debugPrint('[SettingsController] Error reloading TTS engine: $e');
    }
    notifyListeners();
  }

  double get vadSensitivity => _settings.vadSensitivity;

  Future<void> updateVadSensitivity(double val) async {
    _settings = _settings.copyWith(vadSensitivity: val);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateAutoPlayAudio(bool autoPlay) async {
    _settings = _settings.copyWith(autoPlayAudio: autoPlay);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  bool get isMtEnabled => _settings.isMtEnabled;

  Future<void> updateMtEnabled(bool enabled) async {
    _settings = _settings.copyWith(isMtEnabled: enabled);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updatePreferredLanguage(String lang) async {
    _settings = _settings.copyWith(preferredLanguage: lang);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateInstalledPacks(String packs) async {
    _settings = _settings.copyWith(installedLanguagePacks: packs);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updatePttMode(String mode) async {
    _settings = _settings.copyWith(pttMode: mode);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }
}
