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
  });
}
