import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/indic_trans_engine.dart';

void main() {
  group('AI4Bharat IndicTrans Machine Translation Engine Tests', () {
    late IndicTransEngine engine;

    setUp(() {
      engine = IndicTransEngine();
    });

    test('Identity translation returns unchanged text when source equals target', () async {
      final res = await engine.translate(
        text: 'Emergency evacuation required',
        sourceLang: 'en',
        targetLang: 'en',
      );
      expect(res, equals('Emergency evacuation required'));
    });

    test('Translates emergency keywords from Hindi to English', () async {
      final res = await engine.translate(
        text: 'आपातकाल',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(res, equals('Emergency'));
    });

    test('Translates help request from Hindi to Marathi', () async {
      final res = await engine.translate(
        text: 'मदद',
        sourceLang: 'hi',
        targetLang: 'mr',
      );
      expect(res, equals('मदत'));
    });

    test('Translates medical terms from English to Hindi', () async {
      final res = await engine.translate(
        text: 'Doctor',
        sourceLang: 'en',
        targetLang: 'hi',
      );
      expect(res, equals('डॉक्टर'));
    });

    test('Translates tactical terms from English to Tamil', () async {
      final res = await engine.translate(
        text: 'Help',
        sourceLang: 'en',
        targetLang: 'ta',
      );
      expect(res, equals('உதவி'));
    });

    test('Empty text returns empty string gracefully', () async {
      final res = await engine.translate(
        text: '   ',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(res, equals(''));
    });

    test('Quantized model state defaults to hybrid disaster lexicon until on-device weights loaded', () {
      expect(engine.isQuantizedModelReady, isFalse);
      expect(engine.engineStatus, contains('IndicTrans2'));
    });

    test('IndicTransEngine offloading and loading lifecycle', () async {
      expect(engine.isLoaded, isTrue);

      engine.unload();
      expect(engine.isLoaded, isFalse);
      expect(engine.engineStatus, contains('Offloaded / 0 MB RAM'));

      // Translation while offloaded bypasses and returns original text
      final bypassed = await engine.translate(
        text: 'आपातकाल',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(bypassed, equals('आपातकाल'));

      // Reloading restores translation
      engine.load();
      expect(engine.isLoaded, isTrue);
      final translated = await engine.translate(
        text: 'आपातकाल',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(translated, equals('Emergency'));
    });

    test('Translates full emergency multi-word preset sentence without truncating to one word', () async {
      final res = await engine.translate(
        text: 'Emergency priority message. Coordinates confirmed. Transceiver link active.',
        sourceLang: 'en',
        targetLang: 'hi',
      );
      // Verify all segments are translated and full sentence structure with punctuation is preserved
      expect(res, contains('आपातकाल'));
      expect(res, contains('प्राथमिकता'));
      expect(res, contains('संदेश'));
      expect(res, contains('निर्देशांक'));
      expect(res, contains('पुष्ट'));
      expect(res, contains('ट्रांसीवर'));
      expect(res, contains('सक्रिय'));
      // Must not be truncated to a single word
      expect(res.split(' ').length, greaterThanOrEqualTo(5));
    });
  });
}
