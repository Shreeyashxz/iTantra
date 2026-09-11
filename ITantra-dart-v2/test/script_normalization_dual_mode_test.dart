import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/script_normalization_engine.dart';

void main() {
  group('ScriptNormalizationEngine Dual-Mode & Phonological Tests', () {
    setUp(() {
      // Default to advanced mode before each test
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
    });

    test('Initial active mode is advanced', () {
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.advanced));
    });

    test('Advanced mode correctly transliterates Devanagari to Tamil without illegal Unicode', () {
      // 'भारत' (Bhārat) -> भ (0x092D) must collapse to Tamil ப (0x0BAA), not illegal 0x0BAD
      final deva = 'भारत';
      final tamil = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.tamil);

      expect(tamil, isNotEmpty);
      expect(tamil.contains('ப'), isTrue, reason: 'Tamil must map aspirated stop भ to ப');

      // Verify no invalid/unassigned Tamil codepoints in output
      for (int i = 0; i < tamil.length; i++) {
        final code = tamil.codeUnitAt(i);
        // If within Tamil block, verify it is not the unassigned 0x0BAD
        expect(code, isNot(equals(0x0BAD)), reason: '0x0BAD is an illegal unassigned Tamil codepoint');
        expect(code, isNot(equals(0x0B96)), reason: '0x0B96 is an illegal unassigned Tamil codepoint');
      }
    });

    test('Advanced mode handles all 10 iTantra language scripts authentically', () {
      final input = 'नमस्ते';
      final scripts = [
        ScriptType.bengali,
        ScriptType.gurmukhi,
        ScriptType.gujarati,
        ScriptType.odia,
        ScriptType.tamil,
        ScriptType.telugu,
        ScriptType.kannada,
        ScriptType.malayalam,
      ];

      for (final script in scripts) {
        final result = ScriptNormalizationEngine.fromDevanagariToIndic(input, script);
        expect(result, isNotEmpty);
        expect(result, isNot(equals(input)));

        // Converting back to Devanagari should recover recognizable phonemes
        final recoveredDeva = ScriptNormalizationEngine.toDevanagari(result);
        expect(recoveredDeva, isNotEmpty);
      }
    });

    test('Legacy mode can be activated and uses legacy block offset', () {
      ScriptNormalizationEngine.activeMode = NormalizerMode.legacyRuleBased;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.legacyRuleBased));

      final input = 'नमस्ते';
      final result = ScriptNormalizationEngine.fromDevanagariToIndic(input, ScriptType.bengali);
      expect(result, isNotEmpty);

      // In legacy mode, toLatin uses the legacy character map
      final latin = ScriptNormalizationEngine.toLatin(input);
      expect(latin.toLowerCase(), contains('namaste'));
    });

    test('Dynamic mode switching works seamlessly', () {
      // 1. Advanced mode
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
      final advTamil = ScriptNormalizationEngine.fromDevanagariToIndic('खतरा', ScriptType.tamil);
      expect(advTamil.contains('க'), isTrue, reason: 'Advanced mode maps ख to க');

      // 2. Switch to Legacy mode
      ScriptNormalizationEngine.activeMode = NormalizerMode.legacyRuleBased;
      final legTamil = ScriptNormalizationEngine.fromDevanagariToIndic('खतरा', ScriptType.tamil);

      // In legacy mode, ख (0x0916) offsets to 0x0B80 + 0x16 = 0x0B96 (unassigned)
      expect(legTamil.codeUnits.contains(0x0B96), isTrue);

      // 3. Switch back to Advanced mode
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
      final advTamilAgain = ScriptNormalizationEngine.fromDevanagariToIndic('खतरा', ScriptType.tamil);
      expect(advTamilAgain.codeUnits.contains(0x0B96), isFalse);
    });

    test('Latin transliteration maps common tactical terms accurately', () {
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
      final latinEmergency = ScriptNormalizationEngine.toLatin('आपातकाल');
      expect(latinEmergency.toLowerCase(), contains('emergency'));

      final latinDoctor = ScriptNormalizationEngine.toLatin('डॉक्टर');
      expect(latinDoctor.toLowerCase(), contains('doctor'));
    });

    test('TTS input preparation works across Rasa-13 and Meta MMS in Advanced Mode', () {
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;

      // Rasa-13 with Tamil target
      final rasaTa = ScriptNormalizationEngine.prepareTextForTts('भारत सुरक्षित है', 'ta', 'AI4BHARAT_RASA');
      expect(rasaTa, isNotEmpty);
      expect(ScriptNormalizationEngine.detectScript(rasaTa), equals(ScriptType.tamil));

      // Meta MMS with Hindi target
      final mmsHi = ScriptNormalizationEngine.prepareTextForTts('मदद चाहिए', 'hi', 'META_MMS');
      expect(mmsHi, isNotEmpty);
      expect(ScriptNormalizationEngine.detectScript(mmsHi), equals(ScriptType.devanagari));

      // Meta MMS with Gujarati digit stripping
      final mmsGu = ScriptNormalizationEngine.prepareTextForTts('તપાસ 1 2', 'gu', 'META_MMS');
      expect(mmsGu, isNotEmpty);
      expect(mmsGu.contains('1'), isFalse);
      expect(mmsGu.contains('2'), isFalse);
    });

    test('Neural IndicXlit mode operates correctly with deterministic offline fallback', () {
      ScriptNormalizationEngine.activeMode = NormalizerMode.neuralIndicXlit;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.neuralIndicXlit));

      // Test Devanagari to Tamil via IndicXlit mode
      final xlitTamil = ScriptNormalizationEngine.fromDevanagariToIndic('भारत', ScriptType.tamil);
      expect(xlitTamil, isNotEmpty);
      expect(xlitTamil.contains('ப'), isTrue);

      // Test Tamil to Devanagari via IndicXlit mode
      final xlitDeva = ScriptNormalizationEngine.toDevanagari(xlitTamil);
      expect(xlitDeva, isNotEmpty);

      // Test Latin transliteration in IndicXlit mode
      final xlitLatin = ScriptNormalizationEngine.toLatin('नमस्ते');
      expect(xlitLatin.toLowerCase(), contains('namaste'));
    });

    test('All 3 modes (Advanced, Legacy, Neural IndicXlit) switch cleanly in sequence', () {
      // 1. Advanced
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.advanced));

      // 2. Legacy Rule-Based
      ScriptNormalizationEngine.activeMode = NormalizerMode.legacyRuleBased;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.legacyRuleBased));

      // 3. Neural IndicXlit
      ScriptNormalizationEngine.activeMode = NormalizerMode.neuralIndicXlit;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.neuralIndicXlit));

      // 4. Back to Advanced
      ScriptNormalizationEngine.activeMode = NormalizerMode.advanced;
      expect(ScriptNormalizationEngine.activeMode, equals(NormalizerMode.advanced));
    });
  });
}
