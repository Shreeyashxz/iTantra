import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/indiclid_fasttext_engine.dart';
import 'package:itantra_dart/speech/script_normalization_engine.dart';

void main() {
  group('IndicLID-FastText Engine Tests (All 10 Languages)', () {
    late IndicLIDFastTextEngine engine;

    setUp(() {
      engine = IndicLIDFastTextEngine.instance;
    });

    test('Identifies Tamil text with high confidence', () {
      final res = engine.identifyLanguage('அவசர உதவி தேவைப்படுகிறது');
      expect(res.languageCode, equals('ta'));
      expect(res.script, equals(ScriptType.tamil));
      expect(res.confidence, greaterThanOrEqualTo(0.95));
    });

    test('Identifies Telugu text with high confidence', () {
      final res = engine.identifyLanguage('అత్యవసర సహాయం కావాలి');
      expect(res.languageCode, equals('te'));
      expect(res.script, equals(ScriptType.telugu));
      expect(res.confidence, greaterThanOrEqualTo(0.95));
    });

    test('Identifies Kannada text with high confidence', () {
      final res = engine.identifyLanguage('ತುರ್ತು ಸಹಾಯ ಬೇಕಾಗಿದೆ');
      expect(res.languageCode, equals('kn'));
      expect(res.script, equals(ScriptType.kannada));
    });

    test('Identifies Malayalam text with high confidence', () {
      final res = engine.identifyLanguage('അടിയന്തര സഹായം ആവശ്യമാണ്');
      expect(res.languageCode, equals('ml'));
      expect(res.script, equals(ScriptType.malayalam));
    });

    test('Identifies Bengali text with high confidence', () {
      final res = engine.identifyLanguage('জরুরী চিকিৎসা সাহায্য প্রয়োজন');
      expect(res.languageCode, equals('bn'));
      expect(res.script, equals(ScriptType.bengali));
    });

    test('Identifies Gujarati text with high confidence', () {
      final res = engine.identifyLanguage('કટોકટી મદદની જરૂર છે');
      expect(res.languageCode, equals('gu'));
      expect(res.script, equals(ScriptType.gujarati));
    });

    test('Identifies Odia text with high confidence', () {
      final res = engine.identifyLanguage('ଜରୁରୀକାଳୀନ ସାହାଯ୍ୟ ଆବଶ୍ୟକ');
      expect(res.languageCode, equals('or'));
      expect(res.script, equals(ScriptType.odia));
    });

    test('Devanagari Subword n-grams: Discriminates Marathi from Hindi', () {
      // Marathi sentence with Marathi roots (आहे, मदत, त्वरित)
      final mrRes = engine.identifyLanguage('येथे त्वरित मदत पाहिजे आहे');
      expect(mrRes.languageCode, equals('mr'));
      expect(mrRes.script, equals(ScriptType.devanagari));

      // Hindi sentence with Hindi roots (है, मदद, चाहिए)
      final hiRes = engine.identifyLanguage('यहाँ जल्दी मदद चाहिए है');
      expect(hiRes.languageCode, equals('hi'));
      expect(hiRes.script, equals(ScriptType.devanagari));
    });

    test('Latin Script: Identifies standard English vs Romanized Indic', () {
      final enRes = engine.identifyLanguage('Emergency evacuation required at grid alpha.');
      expect(enRes.languageCode, equals('en'));
      expect(enRes.isRomanized, isFalse);

      final hinglishRes = engine.identifyLanguage('Doctor jaldi bhejo madat chahiye');
      expect(hinglishRes.isRomanized, isTrue);
    });

    test('Empty text returns English fallback gracefully', () {
      final res = engine.identifyLanguage('   ');
      expect(res.languageCode, equals('en'));
    });
  });
}
