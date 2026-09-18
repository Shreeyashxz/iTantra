import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/indic_trans_engine.dart';
import 'package:itantra_dart/speech/neural_mt_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NeuralMtEngine & IndicTrans2 Inference Tests', () {
    late NeuralMtEngine engine;

    setUp(() {
      engine = NeuralMtEngine.instance;
    });

    test('NeuralMtEngine singleton is accessible and starts uninitialized without models', () {
      expect(engine, isNotNull);
      expect(engine.tokenizer, isNotNull);
      expect(engine.isReady, isFalse);
      expect(engine.loadedModelName, isEmpty);
    });

    test('NeuralMtEngine.init handles missing model files gracefully without throwing', () async {
      final tempDir = Directory.systemTemp.createTempSync('mt_test_empty_');
      try {
        final ready = await engine.init(tempDir.path);
        expect(ready, isFalse);
        expect(engine.isReady, isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('NeuralMtEngine.translate returns null when models are not loaded (permitting fallback)', () async {
      final result = await engine.translate(
        text: 'The blue bird flew over the yellow fence',
        sourceLang: 'en',
        targetLang: 'hi',
      );
      expect(result, isNull);
    });

    test('IndicTransEngine seamlessly falls back to Tier 1 and transliteration when neural weights are absent', () async {
      final mt = IndicTransEngine();
      
      // Tier 1: Exact tactical match works instantly (<1 ms)
      final emergencyHi = await mt.translate(
        text: 'Emergency',
        sourceLang: 'en',
        targetLang: 'hi',
      );
      expect(emergencyHi, equals('आपातकाल'));

      // Arbitrary sentence: Without neural weights on disk, gracefully transliterates into target script
      final arbitraryHi = await mt.translate(
        text: 'Blue bird flight active',
        sourceLang: 'en',
        targetLang: 'hi',
      );
      expect(arbitraryHi, isNotEmpty);
      expect(arbitraryHi, contains('सक्रिय')); // 'active' -> 'सक्रिय'
    });

    test('NeuralMtEngine unload reclaims resources safely', () async {
      await engine.unload();
      expect(engine.isReady, isFalse);
      expect(engine.loadedModelName, isEmpty);
    });
  });
}
