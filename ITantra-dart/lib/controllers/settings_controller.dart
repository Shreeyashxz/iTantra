import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/app_database.dart';
import '../data/entities/user_settings_entity.dart';
import '../speech/language_pack_manager.dart';
import '../speech/neural_mt_engine.dart';
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

  bool _isMtIndicIndicReady = false;
  bool get isMtIndicIndicReady => _isMtIndicIndicReady;

  bool _isMtIndicEnReady = false;
  bool get isMtIndicEnReady => _isMtIndicEnReady;

  bool _isMtFp16Ready = false;
  bool get isMtFp16Ready => _isMtFp16Ready;

  bool _isRasa13Ready = false;
  bool get isRasa13Ready => _isRasa13Ready;

  bool _isIndicXlitReady = false;
  bool get isIndicXlitReady => _isIndicXlitReady;

  bool _isLidReady = false;
  bool get isLidReady => _isLidReady;

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
    switch (_settings.normalizerMode) {
      case 'LEGACY_RULE_BASED':
        ScriptNormalizationEngine.activeMode = NormalizerMode.legacyRuleBased;
        break;
      case 'NEURAL_INDIC_XLIT':
        ScriptNormalizationEngine.activeMode = NormalizerMode.neuralIndicXlit;
        break;
      case 'ADVANCED':
      default:
        ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
        break;
    }
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
    _isMtIndicIndicReady = await languagePackManager.isMtIndicIndicAvailable();
    _isMtIndicEnReady = await languagePackManager.isMtIndicEnAvailable();
    _isMtReady = _isMtIndicIndicReady || _isMtIndicEnReady || await languagePackManager.isMtAvailable();
    _isMtFp16Ready = await languagePackManager.isMtFp16Available();
    _isRasa13Ready = await languagePackManager.isRasa13Available();
    _isIndicXlitReady = await languagePackManager.isIndicXlitAvailable();
    _isLidReady = await languagePackManager.isLidAvailable();
    for (final lang in LanguagePackManager.supportedLanguages) {
      _ttsReadyMap[lang.code] = await languagePackManager.isTtsAvailable(lang.code);
      _mmsReadyMap[lang.code] = await languagePackManager.isMmsAvailable(lang.code);
    }
    if (_isMtIndicIndicReady || _isMtIndicEnReady) {
      await NeuralMtEngine.instance.init();
    }
    notifyListeners();
  }

  Future<void> downloadStt() async {
    await languagePackManager.downloadStt();
    await checkModelStatus();
  }

  Future<void> downloadMt() async {
    await downloadMtIndicIndic();
  }

  Future<void> deleteMt() async {
    await languagePackManager.deleteMt();
    await checkModelStatus();
  }

  Future<void> downloadMtIndicIndic() async {
    await languagePackManager.downloadMtIndicIndic();
    await checkModelStatus();
  }

  Future<void> deleteMtIndicIndic() async {
    await languagePackManager.deleteMtIndicIndic();
    await checkModelStatus();
  }

  Future<void> downloadMtIndicEn() async {
    await languagePackManager.downloadMtIndicEn();
    await checkModelStatus();
  }

  Future<void> deleteMtIndicEn() async {
    await languagePackManager.deleteMtIndicEn();
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

  Future<void> downloadIndicXlit() async {
    await languagePackManager.downloadIndicXlit();
    await checkModelStatus();
  }

  Future<void> deleteIndicXlit() async {
    await languagePackManager.deleteIndicXlit();
    await checkModelStatus();
  }

  Future<void> downloadLid() async {
    await languagePackManager.downloadLid();
    await checkModelStatus();
  }

  Future<void> deleteLid() async {
    await languagePackManager.deleteLid();
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

  String get normalizerMode => _settings.normalizerMode;
  bool get isAdvancedNormalizer => _settings.normalizerMode == 'ADVANCED';
  bool get isLegacyNormalizer => _settings.normalizerMode == 'LEGACY_RULE_BASED';
  bool get isNeuralIndicXlit => _settings.normalizerMode == 'NEURAL_INDIC_XLIT';

  Future<void> updateNormalizerMode(String mode) async {
    _settings = _settings.copyWith(normalizerMode: mode);
    await database.saveSettings(_settings);
    switch (mode) {
      case 'LEGACY_RULE_BASED':
        ScriptNormalizationEngine.activeMode = NormalizerMode.legacyRuleBased;
        break;
      case 'NEURAL_INDIC_XLIT':
        ScriptNormalizationEngine.activeMode = NormalizerMode.neuralIndicXlit;
        break;
      case 'ADVANCED':
      default:
        ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
        break;
    }
    notifyListeners();
  }

  Future<void> toggleNormalizerMode() async {
    String next;
    if (isAdvancedNormalizer) {
      next = 'LEGACY_RULE_BASED';
    } else if (isLegacyNormalizer) {
      next = 'NEURAL_INDIC_XLIT';
    } else {
      next = 'ADVANCED';
    }
    await updateNormalizerMode(next);
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }
}
