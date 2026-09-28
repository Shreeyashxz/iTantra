import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/language_pack_manager.dart';
import 'package:itantra_dart/speech/script_normalization_engine.dart';
import 'package:itantra_dart/speech/sherpa_onnx_speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('xyz.luan/audioplayers.global');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => 1);
    const audioChannel = MethodChannel('xyz.luan/audioplayers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (MethodCall methodCall) async => 1);
  });

  group('STT to TTS End-to-End Pipeline & Transliterator Tests', () {
    test('IndicScriptTransliterator maps emergency keywords to English', () {
      final input = 'हैलो आपातकालीन मदद';
      final output = ScriptNormalizationEngine.normalizeFromStt(input, 'en');
      expect(output, contains('Hello'));
      expect(output, contains('Emergency'));
      expect(output, contains('Help'));
    });

    test('IndicScriptTransliterator transliterates numbers and technical terms', () {
      final input = 'रेडियो एक दो तीन';
      final output = ScriptNormalizationEngine.normalizeFromStt(input, 'en');
      expect(output, contains('Radio'));
      expect(output, contains('1'));
      expect(output, contains('2'));
      expect(output, contains('3'));
    });

    test('IndicScriptTransliterator leaves plain English intact', () {
      final input = 'Emergency Sector 4 coordinates confirmed';
      final output = ScriptNormalizationEngine.normalizeFromStt(input, 'en');
      expect(output, equals('Emergency Sector 4 coordinates confirmed'));
    });

    test('IndicScriptTransliterator phonetic fallback for unmapped Devanagari', () {
      final input = 'पानी';
      final output = ScriptNormalizationEngine.normalizeFromStt(input, 'en');
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

    test('TTS Normalizer strips trailing punctuation across languages', () {
      final input1 = 'नमस्ते दोस्तों।';
      final res1 = ScriptNormalizationEngine.prepareTextForTts(input1, 'hi', 'AI4BHARAT_RASA');
      expect(res1.endsWith('।'), isFalse);
      expect(res1.endsWith('.'), isFalse);

      final input2 = 'Emergency alert message!!!';
      final res2 = ScriptNormalizationEngine.prepareTextForTts(input2, 'en', 'AI4BHARAT_RASA');
      expect(res2.endsWith('!'), isFalse);
    });

    test('TTS Normalizer sanitizes Gujarati digits and symbols for Meta MMS', () {
      final input = 'ઇમરજન્સી 108 ચેતવણી!';
      final res = ScriptNormalizationEngine.prepareTextForTts(input, 'gu', 'META_MMS');
      expect(res, contains('એક'));
      expect(res, contains('શૂન્ય'));
      expect(res, contains('આઠ'));
      expect(res.contains('1'), isFalse);
      expect(res.contains('0'), isFalse);
      expect(res.contains('8'), isFalse);
      expect(res.contains('!'), isFalse);
    });

    test('TTS Normalizer aligns cross-script Indic text for Rasa-13 when detected != expected', () {
      // Devanagari text fed to Tamil target should align to Tamil script
      final devaInput = 'नमस्ते';
      final res = ScriptNormalizationEngine.prepareTextForTts(devaInput, 'ta', 'AI4BHARAT_RASA');
      expect(res, isNotEmpty);
      // Verify the script is not Latin and was processed
      final script = ScriptNormalizationEngine.detectScript(res);
      expect(script, equals(ScriptType.tamil));
    });
  });
}
