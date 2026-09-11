import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// OS Native TTS Service utilizing system-bundled engines:
/// - Android: Android TextToSpeech (Google TTS / Samsung TTS / OEM engine)
/// - Windows: SAPI5 / Windows OneCore voices
/// - iOS / macOS: AVFoundation AVSpeechSynthesizer
/// - Web: Web Speech API
class OsNativeTtsService {
  static final OsNativeTtsService instance = OsNativeTtsService._internal();
  OsNativeTtsService._internal();

  FlutterTts? _flutterTts;
  bool _isInitialized = false;

  /// ISO language code to BCP-47 locale mapping
  static const Map<String, String> bcp47Codes = {
    'hi': 'hi-IN',
    'en': 'en-IN',
    'gu': 'gu-IN',
    'mr': 'mr-IN',
    'kn': 'kn-IN',
    'ml': 'ml-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
    'or': 'or-IN',
    'bn': 'bn-IN',
  };

  /// Initializes the native TTS engine with standard playback parameters.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _flutterTts = FlutterTts();
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
      _isInitialized = true;
      debugPrint('[OsNativeTTS] Initialized platform speech synthesizer');
    } catch (e) {
      debugPrint('[OsNativeTTS] Init notice (expected in headless tests): $e');
    }
  }

  /// Speaks the given text in the requested language using the OS native TTS voice.
  Future<bool> speak(String text, String languageCode, [String gender = 'FEMALE']) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    try {
      await init();
      if (_flutterTts == null) return false;

      final locale = bcp47Codes[languageCode.toLowerCase()] ?? 'en-IN';
      await _flutterTts?.setLanguage(locale);

      final isMale = gender.toUpperCase() == 'MALE';
      await _flutterTts?.setPitch(isMale ? 0.85 : 1.15);
      await _flutterTts?.setSpeechRate(isMale ? 0.48 : 0.50);

      final result = await _flutterTts?.speak(clean);
      final ok = result == 1;
      if (ok) {
        debugPrint('[OsNativeTTS] Spoke "$clean" via OS native engine ($locale, gender: $gender)');
      }
      return ok;
    } catch (e) {
      debugPrint('[OsNativeTTS] Platform speech synthesis error for $languageCode: $e');
      return false;
    }
  }

  /// Stops current speech playback.
  Future<void> stop() async {
    try {
      await _flutterTts?.stop();
    } catch (_) {}
  }
}
