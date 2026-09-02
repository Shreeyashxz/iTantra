import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/app_database.dart';
import '../data/entities/user_settings_entity.dart';
import '../speech/language_pack_manager.dart';

class SettingsController extends ChangeNotifier {
  final AppDatabase database;
  final LanguagePackManager languagePackManager;

  UserSettingsEntity _settings = UserSettingsEntity();
  UserSettingsEntity get settings => _settings;

  DownloadState _downloadState = const DownloadStateIdle();
  DownloadState get downloadState => _downloadState;

  bool _isSttReady = false;
  bool get isSttReady => _isSttReady;

  bool _isHiTtsReady = false;
  bool get isHiTtsReady => _isHiTtsReady;

  bool _isEnTtsReady = false;
  bool get isEnTtsReady => _isEnTtsReady;

  StreamSubscription<DownloadState>? _downloadSubscription;

  SettingsController({
    required this.database,
    required this.languagePackManager,
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
    _isHiTtsReady = await languagePackManager.isTtsAvailable('hi');
    _isEnTtsReady = await languagePackManager.isTtsAvailable('en');
    notifyListeners();
  }

  Future<void> downloadStt() async {
    await languagePackManager.downloadStt();
    await checkModelStatus();
  }

  Future<void> downloadTts(String languageCode) async {
    await languagePackManager.downloadTts(languageCode);
    await checkModelStatus();
  }

  Future<void> downloadAllEssentials() async {
    await languagePackManager.downloadAllEssentials();
    await checkModelStatus();
  }

  Future<void> updateTtsSpeed(double speed) async {
    _settings = _settings.copyWith(ttsSpeed: speed);
    await database.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateAutoPlayAudio(bool autoPlay) async {
    _settings = _settings.copyWith(autoPlayAudio: autoPlay);
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
