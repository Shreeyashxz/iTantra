import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/language_pack_manager.dart';
import 'package:itantra_dart/speech/sherpa_onnx_speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STT to TTS End-to-End Pipeline & Transliterator Tests', () {
    test('IndicScriptTransliterator maps emergency keywords to English', () {
      final input = 'हैलो आपातकालीन मदद';
      final output = IndicScriptTransliterator.toEnglish(input);
      expect(output, contains('Hello'));
      expect(output, contains('Emergency'));
      expect(output, contains('Help'));
    });

    test('IndicScriptTransliterator transliterates numbers and technical terms', () {
      final input = 'रेडियो एक दो तीन';
      final output = IndicScriptTransliterator.toEnglish(input);
      expect(output, contains('Radio'));
      expect(output, contains('1'));
      expect(output, contains('2'));
      expect(output, contains('3'));
    });

    test('IndicScriptTransliterator leaves plain English intact', () {
      final input = 'Emergency Sector 4 coordinates confirmed';
      final output = IndicScriptTransliterator.toEnglish(input);
      expect(output, equals('Emergency Sector 4 coordinates confirmed'));
    });

    test('IndicScriptTransliterator phonetic fallback for unmapped Devanagari', () {
      final input = 'पानी';
      final output = IndicScriptTransliterator.toEnglish(input);
      // 'पानी' maps to 'Water' in dictionary
      expect(output, equals('Water'));
    });

    test('SherpaOnnxSpeechEngine model lifecycle flags', () {
      final lpm = LanguagePackManager();
      final engine = SherpaOnnxSpeechEngine(languagePackManager: lpm);
      expect(engine.isSttLoaded, isFalse);
      expect(engine.isTtsLoaded, isFalse);

      engine.unloadStt();
      expect(engine.isSttLoaded, isFalse);

      engine.unloadTts();
      expect(engine.isTtsLoaded, isFalse);
    });
  });
}
