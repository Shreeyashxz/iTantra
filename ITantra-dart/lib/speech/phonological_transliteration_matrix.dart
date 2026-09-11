import 'script_normalization_engine.dart';

/// Comprehensive phonological transliteration matrix for all 10 iTantra languages.
/// Replaces naive Unicode offset math with genuine linguistic mappings,
/// preventing unassigned/illegal Unicode codepoints across Dravidian and Indo-Aryan scripts.
class PhonologicalTransliterationMatrix {
  // --- Canonical Phoneme Identifiers ---
  // Each entry represents a unique phonetic element in the Indic phonological space.

  // Consonants (Stops, Nasals, Semivowels, Sibilants, Aspirates)
  // Format: [Devanagari, Bengali, Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam, Latin]
  static const List<List<String>> _consonantTable = [
    // Velar stops & nasal
    ['क', 'ক', 'ਕ', 'ક', 'କ', 'க', 'క', 'ಕ', 'ക', 'k'],
    ['ख', 'খ', 'ਖ', 'ખ', 'ଖ', 'க', 'ఖ', 'ಖ', 'ഖ', 'kh'],
    ['ग', 'গ', 'ਗ', 'ગ', 'ଗ', 'க', 'గ', 'ಗ', 'ഗ', 'g'],
    ['घ', 'ঘ', 'ਘ', 'ઘ', 'ଘ', 'க', 'ఘ', 'ಘ', 'ഘ', 'gh'],
    ['ङ', 'ঙ', 'ਙ', 'ઙ', 'ଙ', 'ங', 'ఙ', 'ಙ', 'ങ', 'ng'],

    // Palatal stops & nasal
    ['च', 'চ', 'ਚ', 'ચ', 'ଚ', 'ச', 'చ', 'ಚ', 'ച', 'ch'],
    ['छ', 'ছ', 'ਛ', 'છ', 'ଛ', 'ச', 'ఛ', 'ಛ', 'ഛ', 'chh'],
    ['ज', 'জ', 'ਜ', 'જ', 'ଜ', 'ஜ', 'జ', 'ಜ', 'ജ', 'j'],
    ['झ', 'ঝ', 'ਝ', 'ઝ', 'ଝ', 'ச', 'ఝ', 'ಝ', 'ഝ', 'jh'],
    ['ञ', 'ঞ', 'ਞ', 'ઞ', 'ଞ', 'ஞ', 'ఞ', 'ಞ', 'ഞ', 'ny'],

    // Retroflex stops & nasal
    ['ट', 'ট', 'ਟ', 'ટ', 'ଟ', 'ட', 'ట', 'ಟ', 'ട', 't'],
    ['ठ', 'ঠ', 'ਠ', 'ઠ', 'ଠ', 'ட', 'ఠ', 'ಠ', 'ഠ', 'th'],
    ['ड', 'ড', 'ਡ', 'ડ', 'ଡ', 'ட', 'డ', 'ಡ', 'ഡ', 'd'],
    ['ढ', 'ঢ', 'ਢ', 'ઢ', 'ଢ', 'ட', 'ఢ', 'ಢ', 'ഢ', 'dh'],
    ['ण', 'ণ', 'ਣ', 'ણ', 'ଣ', 'ண', 'ణ', 'ಣ', 'ണ', 'n'],

    // Dental stops & nasal
    ['त', 'ত', 'ਤ', 'ત', 'ତ', 'த', 'త', 'ತ', 'ത', 't'],
    ['थ', 'থ', 'ਥ', 'થ', 'ଥ', 'த', 'థ', 'ಥ', 'ഥ', 'th'],
    ['द', 'দ', 'ਦ', 'દ', 'ଦ', 'த', 'ద', 'ದ', 'ദ', 'd'],
    ['ध', 'ধ', 'ਧ', 'ધ', 'ଧ', 'த', 'ధ', 'ಧ', 'ധ', 'dh'],
    ['न', 'ন', 'ਨ', 'ન', 'ନ', 'ந', 'న', 'ನ', 'ന', 'n'],

    // Labial stops & nasal
    ['प', 'প', 'ਪ', 'પ', 'ପ', 'ப', 'ప', 'ಪ', 'പ', 'p'],
    ['फ', 'ফ', 'ਫ', 'ફ', 'ଫ', 'ப', 'ఫ', 'ಫ', 'ഫ', 'ph'],
    ['ब', 'ব', 'ਬ', 'બ', 'ବ', 'ப', 'బ', 'ಬ', 'ബ', 'b'],
    ['भ', 'ভ', 'ਭ', 'ભ', 'ଭ', 'ப', 'భ', 'ಭ', 'ഭ', 'bh'],
    ['म', 'ম', 'ਮ', 'મ', 'ମ', 'ம', 'మ', 'ಮ', 'മ', 'm'],

    // Semivowels / Approximants
    ['य', 'য', 'ਯ', 'ય', 'ଯ', 'ய', 'య', 'ಯ', 'യ', 'y'],
    ['र', 'র', 'ਰ', 'ર', 'ର', 'ர', 'ర', 'ರ', 'ര', 'r'],
    ['ल', 'ল', 'ਲ', 'લ', 'ଲ', 'ல', 'ల', 'ಲ', 'ല', 'l'],
    ['व', 'ব', 'ਵ', 'વ', 'ଵ', 'வ', 'వ', 'ವ', 'വ', 'v'],

    // Sibilants & Aspirate
    ['श', 'শ', 'ਸ਼', 'શ', 'ଶ', 'ச', 'శ', 'ಶ', 'ശ', 'sh'],
    ['ष', 'ষ', 'ਸ਼', 'ષ', 'ଷ', 'ஷ', 'ష', 'ಷ', 'ഷ', 'sh'],
    ['स', 'স', 'ਸ', 'સ', 'ସ', 'ஸ', 'స', 'ಸ', 'സ', 's'],
    ['ह', 'হ', 'ਹ', 'હ', 'ହ', 'ஹ', 'హ', 'ಹ', 'ഹ', 'h'],

    // Additional Dravidian / regional consonants
    ['ळ', 'ল', 'ਲ਼', 'ળ', 'ଳ', 'ள', 'ళ', 'ಳ', 'ള', 'l'],
    ['ऱ', 'র', 'ਰ', 'ર', 'ର', 'ற', 'ఱ', 'ಱ', 'റ', 'r'],
    ['ऴ', 'য', 'ਯ', 'ય', 'ଯ', 'ழ', 'ళ', 'ೞ', 'ഴ', 'zh'],
    ['ऩ', 'ন', 'ਨ', 'ન', 'ନ', 'ன', 'న', 'ನ', 'ന', 'n'],
    ['क्ष', 'ক্ষ', 'ਕ੍ਸ਼', 'ક્ષ', 'କ୍ଷ', 'க்ஷ', 'క్ష', 'ಕ್ಷ', 'ക്ഷ', 'ksh'],
    ['ज्ञ', 'জ্ঞ', 'ਗ੍ਯ', 'જ્ઞ', 'ଜ୍ଞ', 'ஜ்ஞ', 'జ్ఞ', 'ಜ್ಞ', 'ജ്ഞ', 'gy'],
  ];

  // Independent Vowels
  // Format: [Devanagari, Bengali, Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam, Latin]
  static const List<List<String>> _vowelTable = [
    ['अ', 'অ', 'ਅ', 'અ', 'ଅ', 'அ', 'అ', 'ಅ', 'അ', 'a'],
    ['आ', 'আ', 'ਆ', 'આ', 'ଆ', 'ஆ', 'ఆ', 'ಆ', 'ആ', 'aa'],
    ['इ', 'ই', 'ਇ', 'ઇ', 'ଇ', 'இ', 'ఇ', 'ಇ', 'ഇ', 'i'],
    ['ई', 'ঈ', 'ਈ', 'ઈ', 'ଈ', 'ஈ', 'ఈ', 'ಈ', 'ഈ', 'ee'],
    ['उ', 'উ', 'ਉ', 'ઉ', 'ଉ', 'உ', 'ఉ', 'ಉ', 'ഉ', 'u'],
    ['ऊ', 'ঊ', 'ਊ', 'ઊ', 'ଊ', 'ஊ', 'ఊ', 'ಊ', 'ഊ', 'oo'],
    ['ऋ', 'ঋ', 'ਰਿ', 'ઋ', 'ଋ', 'ரி', 'ఋ', 'ಋ', 'ഋ', 'ri'],
    ['ए', 'এ', 'ਏ', 'એ', 'ଏ', 'ஏ', 'ఏ', 'ಏ', 'ഏ', 'e'],
    ['ऐ', 'ঐ', 'ਐ', 'ઐ', 'ଐ', 'ஐ', 'ఐ', 'ಐ', 'ഐ', 'ai'],
    ['ओ', 'ও', 'ਓ', 'ઓ', 'ଓ', 'ஓ', 'ఓ', 'ಓ', 'ഓ', 'o'],
    ['औ', 'ঔ', 'ਔ', 'ઔ', 'ଔ', 'ஔ', 'ఔ', 'ಔ', 'ഔ', 'au'],
    // Dravidian Short Vowels (Short e, Short o)
    ['ऎ', 'এ', 'ਏ', 'એ', 'ଏ', 'எ', 'ఎ', 'ಎ', 'എ', 'e'],
    ['ऒ', 'ও', 'ਓ', 'ઓ', 'ଓ', 'ஒ', 'ఒ', 'ಒ', 'ഒ', 'o'],
  ];

  // Dependent Vowel Signs (Matras)
  // Format: [Devanagari, Bengali, Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam, Latin]
  static const List<List<String>> _matraTable = [
    ['ा', 'া', 'ਾ', 'ા', 'ା', 'ா', 'ా', 'ಾ', 'ാ', 'aa'],
    ['ि', 'ি', 'ਿ', 'િ', 'ି', 'ி', 'ి', 'ಿ', 'ി', 'i'],
    ['ी', 'ী', 'ੀ', 'ી', 'ୀ', 'ீ', 'ీ', 'ೀ', 'ീ', 'ee'],
    ['ु', 'ু', 'ੁ', 'ુ', 'ୁ', 'ு', 'ు', 'ು', 'ു', 'u'],
    ['ू', 'ূ', 'ੂ', 'ૂ', 'ୂ', 'ூ', 'ూ', 'ೂ', 'ൂ', 'oo'],
    ['ृ', 'ৃ', '੍ਰਿ', 'ૃ', 'ୃ', '்ரி', 'ృ', 'ೃ', 'ൃ', 'ri'],
    ['े', 'ে', 'ੇ', 'ે', 'େ', 'ே', 'ే', 'ೇ', 'േ', 'e'],
    ['ै', 'ৈ', 'ੈ', 'ૈ', 'ୈ', 'ை', 'ై', 'ೈ', 'ൈ', 'ai'],
    ['ो', 'ো', 'ੋ', 'ો', 'ୋ', 'ோ', 'ో', 'ೋ', 'ോ', 'o'],
    ['ौ', 'ৌ', 'ੌ', 'ૌ', 'ୌ', 'ௌ', 'ౌ', 'ೌ', 'ൌ', 'au'],
    // Dravidian short vowel matras
    ['ॆ', 'ে', 'ੇ', 'ે', 'େ', 'ெ', 'ె', 'ೆ', 'െ', 'e'],
    ['ॊ', 'ো', 'ੋ', 'ો', 'ୋ', 'ொ', 'ొ', 'ೊ', 'ൊ', 'o'],
  ];

  // Modifiers & Punctuation
  static const List<List<String>> _modifierTable = [
    ['्', '্', '੍', '્', '୍', '்', '్', '್', '്', ''],    // Virama / Halant
    ['ं', 'ং', 'ਂ', 'ં', 'ଂ', 'ம்', 'ం', 'ಂ', 'ം', 'n'],  // Anusvara
    ['ः', 'ঃ', 'ਃ', 'ઃ', 'ଃ', 'ஃ', 'ః', 'ಃ', 'ഃ', 'h'],  // Visarga
    ['ँ', 'ঁ', 'ਁ', 'ઁ', 'ଁ', '', 'ఁ', '', '', 'n'],      // Chandrabindu
    ['़', '়', '਼', '઼', '଼', '', '', '', '', ''],        // Nukta
    ['।', '।', '।', '।', '।', '.', '.', '.', '.', '.'],   // Danda
    ['॥', '॥', '॥', '॥', '॥', '.', '.', '.', '.', '.'],   // Double Danda
  ];

  // Digits
  static const List<List<String>> _digitTable = [
    ['०', '০', '੦', '૦', '୦', '0', '౦', '೦', '൦', '0'],
    ['१', '১', '੧', '૧', '୧', '1', '౧', '೧', '൧', '1'],
    ['२', '২', '੨', '૨', '୨', '2', '౨', '೨', '൨', '2'],
    ['३', '৩', '੩', '૩', '୩', '3', '౩', '೩', '൩', '3'],
    ['४', '৪', '੪', '૪', '୪', '4', '౪', '೪', '൪', '4'],
    ['५', '৫', '੫', '૫', '୫', '5', '౫', '೫', '൫', '5'],
    ['६', '৬', '੬', '૬', '୬', '6', '౬', '೬', '൬', '6'],
    ['७', '৭', '੭', '૭', '୭', '7', '౭', '೭', '൭', '7'],
    ['८', '৮', '੮', '૮', '୮', '8', '౮', '೮', '൮', '8'],
    ['९', '৯', '੯', '૯', '୯', '9', '౯', '೯', '൯', '9'],
  ];

  // Helper index mapper for ScriptType
  static int _scriptIndex(ScriptType script) {
    switch (script) {
      case ScriptType.devanagari:
        return 0;
      case ScriptType.bengali:
        return 1;
      case ScriptType.gurmukhi:
        return 2;
      case ScriptType.gujarati:
        return 3;
      case ScriptType.odia:
        return 4;
      case ScriptType.tamil:
        return 5;
      case ScriptType.telugu:
        return 6;
      case ScriptType.kannada:
        return 7;
      case ScriptType.malayalam:
        return 8;
      case ScriptType.latin:
      default:
        return 9;
    }
  }

  // Pre-built fast lookup tables for character conversion
  static final Map<int, Map<String, String>> _toDevanagariCache = {};
  static final Map<int, Map<String, String>> _fromDevanagariCache = {};

  static void _ensureCaches() {
    if (_toDevanagariCache.isNotEmpty) return;

    final allTables = [
      _consonantTable,
      _vowelTable,
      _matraTable,
      _modifierTable,
      _digitTable,
    ];

    for (int sIdx = 1; sIdx <= 8; sIdx++) {
      final toDeva = <String, String>{};
      final fromDeva = <String, String>{};

      for (final table in allTables) {
        for (final row in table) {
          final devaChar = row[0];
          final scriptChar = row[sIdx];

          if (scriptChar.isNotEmpty && devaChar.isNotEmpty) {
            toDeva[scriptChar] = devaChar;
            // First mapped entry for Devanagari wins
            fromDeva.putIfAbsent(devaChar, () => scriptChar);
          }
        }
      }

      _toDevanagariCache[sIdx] = toDeva;
      _fromDevanagariCache[sIdx] = fromDeva;
    }
  }

  /// Converts any source Indic script to authentic Devanagari phonologically.
  static String toDevanagariPhonological(String text, ScriptType sourceScript) {
    if (text.trim().isEmpty) return text;
    if (sourceScript == ScriptType.devanagari) return text;

    _ensureCaches();
    final sIdx = _scriptIndex(sourceScript);
    final map = _toDevanagariCache[sIdx];
    if (map == null) return text;

    final sb = StringBuffer();
    int i = 0;
    while (i < text.length) {
      // Check two-char combinations (conjuncts/graphemes)
      if (i + 1 < text.length) {
        final pair = text.substring(i, i + 2);
        if (map.containsKey(pair)) {
          sb.write(map[pair]);
          i += 2;
          continue;
        }
      }

      final char = text[i];
      if (map.containsKey(char)) {
        sb.write(map[char]);
      } else {
        sb.write(char);
      }
      i++;
    }

    return sb.toString();
  }

  /// Converts Devanagari text to target Indic script with correct Dravidian consonant collapsing.
  static String fromDevanagariPhonological(String text, ScriptType targetScript) {
    if (text.trim().isEmpty) return text;
    if (targetScript == ScriptType.devanagari || targetScript == ScriptType.latin) {
      return text;
    }

    _ensureCaches();
    final tIdx = _scriptIndex(targetScript);
    final map = _fromDevanagariCache[tIdx];
    if (map == null) return text;

    final sb = StringBuffer();
    int i = 0;
    while (i < text.length) {
      // Check multi-character conjuncts first (e.g. क्ष, ज्ञ)
      if (i + 1 < text.length) {
        final pair = text.substring(i, i + 2);
        if (map.containsKey(pair)) {
          sb.write(map[pair]);
          i += 2;
          continue;
        }
      }

      final char = text[i];
      if (map.containsKey(char)) {
        sb.write(map[char]);
      } else {
        sb.write(char);
      }
      i++;
    }

    return sb.toString();
  }

  /// Direct cross-script transliteration between any two Indic scripts.
  static String transliterateBetweenScripts(
    String text,
    ScriptType sourceScript,
    ScriptType targetScript,
  ) {
    if (sourceScript == targetScript) return text;
    final deva = toDevanagariPhonological(text, sourceScript);
    return fromDevanagariPhonological(deva, targetScript);
  }

  /// High-accuracy Romanization to Latin (English) using phonological values.
  static String toLatinPhonological(String text, ScriptType sourceScript) {
    final deva = toDevanagariPhonological(text, sourceScript);
    final sb = StringBuffer();

    // Map Devanagari characters to Latin phonemes
    final devaToLatin = <String, String>{};
    for (final table in [_consonantTable, _vowelTable, _matraTable, _modifierTable, _digitTable]) {
      for (final row in table) {
        if (row[0].isNotEmpty && row[9].isNotEmpty) {
          devaToLatin.putIfAbsent(row[0], () => row[9]);
        }
      }
    }

    for (int i = 0; i < deva.length; i++) {
      final char = deva[i];
      if (devaToLatin.containsKey(char)) {
        sb.write(devaToLatin[char]);
      } else {
        sb.write(char);
      }
    }

    return sb.toString();
  }
}
