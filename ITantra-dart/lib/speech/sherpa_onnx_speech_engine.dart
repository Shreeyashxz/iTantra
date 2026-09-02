import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'language_pack_manager.dart';
import 'speech_engine.dart';

class SherpaOnnxSpeechEngine implements SpeechEngine {
  final LanguagePackManager languagePackManager;
  final FlutterTts _flutterTts = FlutterTts();

  StreamController<String>? _sttStreamController;
  bool _isListening = false;
  String? _currentTtsLanguage;

  static const Map<String, String> _languageLocaleMap = {
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

  SherpaOnnxSpeechEngine({required this.languagePackManager}) {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setLanguage('hi-IN');
      _currentTtsLanguage = 'hi';
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  @override
  Stream<String> startListening() {
    _sttStreamController?.close();
    _sttStreamController = StreamController<String>.broadcast();
    _isListening = true;
    return _sttStreamController!.stream;
  }

  /// Ingests recognized or transcribed text into the active listening stream
  void pushTranscribedText(String text) {
    if (_isListening && _sttStreamController != null && !_sttStreamController!.isClosed) {
      _sttStreamController!.add(text);
    }
  }

  @override
  void stopListening() {
    _isListening = false;
    _sttStreamController?.close();
    _sttStreamController = null;
  }

  @override
  Future<void> synthesizeSpeech(String text, String languageCode) async {
    if (text.trim().isEmpty) return;

    try {
      final locale = _languageLocaleMap[languageCode] ?? 'en-IN';
      if (_currentTtsLanguage != languageCode) {
        await _flutterTts.setLanguage(locale);
        _currentTtsLanguage = languageCode;
      }
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Error synthesizing speech ($languageCode): $e');
    }
  }

  @override
  void stopSpeech() {
    try {
      _flutterTts.stop();
    } catch (e) {
      debugPrint('Error stopping speech: $e');
    }
  }

  @override
  void release() {
    stopListening();
    stopSpeech();
  }
}
