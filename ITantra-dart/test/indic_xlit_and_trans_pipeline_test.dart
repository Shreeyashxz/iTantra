import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/indic_trans_engine.dart';
import 'package:itantra_dart/speech/indic_xlit_engine.dart';
import 'package:itantra_dart/speech/indiclid_fasttext_engine.dart';
import 'package:itantra_dart/speech/script_normalization_engine.dart';

void main() {
  group('Neural IndicXlit & Aksharantar Transliteration Across All Languages', () {
    late IndicXlitEngine xlit;

    setUp(() {
      xlit = IndicXlitEngine.instance;
      ScriptNormalizationEngine.activeMode = NormalizerMode.neuralIndicXlit;
    });

    test('Aksharantar colloquial loanwords accurately map to Devanagari', () {
      expect(xlit.toDevanagariFromLatin('hospital'), equals('हॉस्पिटल'));
      expect(xlit.toDevanagariFromLatin('doctor'), equals('डॉक्टर'));
      expect(xlit.toDevanagariFromLatin('ambulance'), equals('एम्बुलेंस'));
      expect(xlit.toDevanagariFromLatin('police'), equals('पुलिस'));
      expect(xlit.toDevanagariFromLatin('oxygen'), equals('ऑक्सीजन'));
      expect(xlit.toDevanagariFromLatin('emergency'), equals('इमरजेंसी'));
      expect(xlit.toDevanagariFromLatin('captain'), equals('कैप्टन'));
      expect(xlit.toDevanagariFromLatin('radio'), equals('रेडियो'));
      expect(xlit.toDevanagariFromLatin('station'), equals('स्टेशन'));
      expect(xlit.toDevanagariFromLatin('coordinates'), equals('कोऑर्डिनेट्स'));
    });

    test('Contextual phonological syllabification handles conjuncts and matras', () {
      // Syllabifies consonants + matras without naive broken characters
      expect(xlit.toDevanagariFromLatin('namaste'), equals('नमस्ते'));
      expect(xlit.toDevanagariFromLatin('dhanyavad'), equals('धन्यवाद'));
      expect(xlit.toDevanagariFromLatin('pani'), equals('पानी'));
      expect(xlit.toDevanagariFromLatin('kahan'), equals('कहाँ'));
    });

    test('Devanagari to Latin romanization preserves inherent vowels and rhythm', () {
      final latin = xlit.toLatin('नमस्ते', ScriptType.devanagari);
      expect(latin.toLowerCase(), contains('namaste'));

      final bharat = xlit.toLatin('भारत', ScriptType.devanagari);
      expect(bharat.toLowerCase(), contains('bharat'));
    });

    test('Bidirectional transliteration operates across all 10 language scripts', () {
      const latinGreeting = 'namaste';
      final deva = xlit.toDevanagariFromLatin(latinGreeting);
      expect(deva, equals('नमस्ते'));

      // 1. Gujarati
      final gu = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.gujarati);
      expect(gu, equals('નમસ્તે'));

      // 2. Bengali
      final bn = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.bengali);
      expect(bn, equals('নমস্তে'));

      // 3. Tamil
      final ta = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.tamil);
      expect(ta, equals('நமஸ்தே'));

      // 4. Telugu
      final te = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.telugu);
      expect(te, equals('నమస్తే'));

      // 5. Kannada
      final kn = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.kannada);
      expect(kn, equals('ನಮಸ್ತೇ'));

      // 6. Malayalam
      final ml = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.malayalam);
      expect(ml, equals('നമസ്തേ'));

      // 7. Odia
      final or = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.odia);
      expect(or, equals('ନମସ୍ତେ'));

      // 8. Gurmukhi
      final pa = ScriptNormalizationEngine.fromDevanagariToIndic(deva, ScriptType.gurmukhi);
      expect(pa, equals('ਨਮਸ੍ਤੇ'));

      // Reverse conversion back to Devanagari
      expect(ScriptNormalizationEngine.toDevanagari(gu), equals(deva));
      expect(ScriptNormalizationEngine.toDevanagari(bn), equals(deva));
    });
  });

  group('IndicLID Language Identification Tests', () {
    late IndicLIDFastTextEngine lid;

    setUp(() {
      lid = IndicLIDFastTextEngine.instance;
    });

    test('Identifies native script exclusive languages with near 100% confidence', () {
      expect(lid.identifyLanguage('வணக்கம் எப்படி இருக்கிறீர்கள்').languageCode, equals('ta'));
      expect(lid.identifyLanguage('నమస్కారం ఎలా ఉన్నారు').languageCode, equals('te'));
      expect(lid.identifyLanguage('ನಮಸ್ಕಾರ ಹೇಗಿದ್ದೀರಾ').languageCode, equals('kn'));
      expect(lid.identifyLanguage('നമസ്കാരം സുഖമാണോ').languageCode, equals('ml'));
      expect(lid.identifyLanguage('নমস্কার কেমন আছেন').languageCode, equals('bn'));
      expect(lid.identifyLanguage('નમસ્તે કેમ છો').languageCode, equals('gu'));
      expect(lid.identifyLanguage('ନମସ୍କାର କେମିତି ଅଛନ୍ତି').languageCode, equals('or'));
    });

    test('Discriminates shared Devanagari script between Hindi and Marathi', () {
      // Marathi distinctive roots and characters (ळ, आहे, झाले)
      final mrResult = lid.identifyLanguage('आम्ही सुरक्षित आहोत काळजी करू नका');
      expect(mrResult.languageCode, equals('mr'));

      // Hindi distinctive roots (हैं, हम, रहा)
      final hiResult = lid.identifyLanguage('हम सुरक्षित हैं कोई चिंता की बात नहीं है');
      expect(hiResult.languageCode, equals('hi'));
    });

    test('Discriminates Romanized Indic vs standard English', () {
      // Standard English
      final enResult = lid.identifyLanguage('Evacuate immediately to zone bravo');
      expect(enResult.languageCode, equals('en'));
      expect(enResult.isRomanized, isFalse);

      // Romanized Hindi (Hinglish)
      final hinglish = lid.identifyLanguage('jaldi madad bhejo pani chahiye');
      expect(hinglish.languageCode, equals('hi'));
      expect(hinglish.isRomanized, isTrue);

      // Romanized Tamil (Tanglish)
      final tanglish = lid.identifyLanguage('vanga seri venum');
      expect(tanglish.languageCode, equals('ta'));
      expect(tanglish.isRomanized, isTrue);

      // Romanized Telugu
      final telish = lid.identifyLanguage('undhi ledu cheyyandi');
      expect(telish.languageCode, equals('te'));
      expect(telish.isRomanized, isTrue);
    });
  });

  group('IndicTrans Machine Translation Across All 10 Languages', () {
    late IndicTransEngine mt;

    setUp(() {
      mt = IndicTransEngine();
    });

    test('Translates critical disaster sentences across all 10 languages', () async {
      const input = 'We are safe';

      final hi = await mt.translate(text: input, sourceLang: 'en', targetLang: 'hi');
      expect(hi, equals('हम सुरक्षित हैं'));

      final mr = await mt.translate(text: input, sourceLang: 'en', targetLang: 'mr');
      expect(mr, equals('आम्ही सुरक्षित आहोत'));

      final ta = await mt.translate(text: input, sourceLang: 'en', targetLang: 'ta');
      expect(ta, equals('நாங்கள் பாதுகாப்பாக இருக்கிறோம்'));

      final te = await mt.translate(text: input, sourceLang: 'en', targetLang: 'te');
      expect(te, equals('మేము సురక్షితంగా ఉన్నాము'));

      final bn = await mt.translate(text: input, sourceLang: 'en', targetLang: 'bn');
      expect(bn, equals('আমরা নিরাপদ আছি'));

      final gu = await mt.translate(text: input, sourceLang: 'en', targetLang: 'gu');
      expect(gu, equals('અમે સલામત છીએ'));

      final kn = await mt.translate(text: input, sourceLang: 'en', targetLang: 'kn');
      expect(kn, equals('ನಾವು ಸುರಕ್ಷಿತವಾಗಿದ್ದೇವೆ'));

      final ml = await mt.translate(text: input, sourceLang: 'en', targetLang: 'ml');
      expect(ml, equals('ഞങ്ങൾ സുരക്ഷിതരാണ്'));

      final or_ = await mt.translate(text: input, sourceLang: 'en', targetLang: 'or');
      expect(or_, equals('ଆମେ ସୁରକ୍ଷିତ ଅଛୁ'));
    });

    test('Translates tactical commands and status queries', () async {
      final statusEn = await mt.translate(
        text: 'आपकी स्थिति क्या है',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(statusEn, equals('What is your status'));

      final holdTa = await mt.translate(
        text: 'Hold position',
        sourceLang: 'en',
        targetLang: 'ta',
      );
      expect(holdTa, equals('நிலையைப் பிடித்துக் கொள்ளுங்கள்'));
    });

    test('Auto-corrects conflicting source language code using IndicLID', () async {
      // Caller says 'en' but text is clearly Devanagari Hindi
      final res = await mt.translate(
        text: 'तुरंत मदद चाहिए',
        sourceLang: 'en', // Conflicting tag
        targetLang: 'en',
      );
      expect(res, equals('Need help immediately'));
    });
  });
}
