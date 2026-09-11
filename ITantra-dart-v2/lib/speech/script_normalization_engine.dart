import 'package:flutter/foundation.dart';
import 'indic_xlit_engine.dart';
import 'phonological_transliteration_matrix.dart';

enum NormalizerMode {
  advanced,
  legacyRuleBased,
  neuralIndicXlit,
}

enum ScriptType {
  latin,
  devanagari,
  bengali,
  gurmukhi,
  gujarati,
  odia,
  tamil,
  telugu,
  kannada,
  malayalam,
  unknown,
}

extension ScriptTypeExtension on ScriptType {
  String get displayName {
    switch (this) {
      case ScriptType.latin:
        return 'Latin (English)';
      case ScriptType.devanagari:
        return 'Devanagari (Hindi/Marathi)';
      case ScriptType.bengali:
        return 'Bengali';
      case ScriptType.gurmukhi:
        return 'Gurmukhi (Punjabi)';
      case ScriptType.gujarati:
        return 'Gujarati';
      case ScriptType.odia:
        return 'Odia';
      case ScriptType.tamil:
        return 'Tamil';
      case ScriptType.telugu:
        return 'Telugu';
      case ScriptType.kannada:
        return 'Kannada';
      case ScriptType.malayalam:
        return 'Malayalam';
      case ScriptType.unknown:
        return 'Unknown';
    }
  }

  int? get unicodeBase {
    switch (this) {
      case ScriptType.devanagari:
        return 0x0900;
      case ScriptType.bengali:
        return 0x0980;
      case ScriptType.gurmukhi:
        return 0x0A00;
      case ScriptType.gujarati:
        return 0x0A80;
      case ScriptType.odia:
        return 0x0B00;
      case ScriptType.tamil:
        return 0x0B80;
      case ScriptType.telugu:
        return 0x0C00;
      case ScriptType.kannada:
        return 0x0C80;
      case ScriptType.malayalam:
        return 0x0D00;
      default:
        return null;
    }
  }
}

/// Robust script normalization and cross-model script bridging engine.
/// Handles phonetics, inter-Indic transliteration, Latin bridging, and single-script VITS enforcement.
class ScriptNormalizationEngine {
  /// Active normalizer mode (defaults to Advanced Phonological Matrix, togglable to Legacy Rule-Based).
  static NormalizerMode activeMode = NormalizerMode.advanced;

  // --- Tactical & Emergency Lexicon ---
  static const Map<String, String> _devanagariToEnglishLexicon = {
    'हैलो': 'Hello',
    'हेलो': 'Hello',
    'नमस्ते': 'Namaste',
    'नमस्कार': 'Namaskar',
    'मदद': 'Help',
    'सहायता': 'Help',
    'आपातकाल': 'Emergency',
    'आपातकालीन': 'Emergency',
    'खतरा': 'Danger',
    'सावधान': 'Caution',
    'रेडियो': 'Radio',
    'कंट्रोल': 'Control',
    'कंट्रोल रूम': 'Control Room',
    'सिग्नल': 'Signal',
    'लिंक': 'Link',
    'चेक': 'Check',
    'परीक्षण': 'Test',
    'टेस्ट': 'Test',
    'स्थान': 'Location',
    'कोऑर्डिनेट्स': 'Coordinates',
    'सेक्टर': 'Sector',
    'डॉक्टर': 'Doctor',
    'अस्पताल': 'Hospital',
    'चिकित्सा': 'Medical',
    'पानी': 'Water',
    'राशन': 'Ration',
    'भोजन': 'Food',
    'टीम': 'Team',
    'यूनिट': 'Unit',
    'संदेश': 'Message',
    'सूचना': 'Information',
    'कॉपी': 'Copy',
    'ओवर': 'Over',
    'आउट': 'Out',
    'रोजर': 'Roger',
    'रुको': 'Stand by',
    'हाँ': 'Yes',
    'नहीं': 'No',
    'सुरक्षित': 'Safe',
    'तैयार': 'Ready',
    'सक्रिय': 'Active',
    'बंद': 'Offline',
    'एक': '1',
    'दो': '2',
    'तीन': '3',
    'चार': '4',
    'पाँच': '5',
    'पांच': '5',
    'छह': '6',
    'सात': '7',
    'आठ': '8',
    'नौ': '9',
    'शून्य': '0',
    'वन': '1',
    'टू': '2',
    'थ्री': '3',
    'फोर': '4',
    'फाइव': '5',
  };

  // Reverse mapping for common tactical terms (English/Latin -> Devanagari)
  static final Map<String, String> _englishToDevanagariLexicon = {
    'hello': 'नमस्ते',
    'namaste': 'नमस्ते',
    'namaskar': 'नमस्कार',
    'help': 'मदद',
    'emergency': 'आपातकाल',
    'danger': 'खतरा',
    'caution': 'सावधान',
    'radio': 'रेडियो',
    'control': 'कंट्रोल',
    'signal': 'सिग्नल',
    'link': 'लिंक',
    'check': 'चेक',
    'test': 'परीक्षण',
    'location': 'स्थान',
    'coordinates': 'निर्देशांक',
    'sector': 'सेक्टर',
    'doctor': 'डॉक्टर',
    'hospital': 'अस्पताल',
    'medical': 'चिकित्सा',
    'water': 'पानी',
    'food': 'भोजन',
    'team': 'टीम',
    'unit': 'यूनिट',
    'message': 'संदेश',
    'copy': 'कॉपी',
    'over': 'ओवर',
    'out': 'आउट',
    'roger': 'रोज़र',
    'stand by': 'रुको',
    'yes': 'हाँ',
    'no': 'नहीं',
    'safe': 'सुरक्षित',
    'ready': 'तैयार',
    'active': 'सक्रिय',
  };

  // --- Devanagari Phonetic Table to Latin ---
  static const Map<String, String> _devaToLatinMap = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l', 'क्ष': 'ksh', 'ज्ञ': 'gy',
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u',
    'ऊ': 'oo', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
    'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
    'ृ': 'ri', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',
    'ं': 'n', 'ँ': 'n', 'ः': 'h', '्': '', '़': '', 'ऽ': '',
    '।': '.', '॥': '.',
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  // --- Latin to Devanagari Consonants & Vowels for Reverse Transliteration ---
  static const List<(String, String)> _latinToDevaMulti = [
    ('chh', 'छ'), ('kh', 'ख'), ('gh', 'घ'), ('ng', 'ङ'),
    ('ch', 'च'), ('jh', 'झ'), ('ny', 'ञ'), ('th', 'थ'),
    ('dh', 'ध'), ('ph', 'फ'), ('bh', 'भ'), ('sh', 'श'),
    ('aa', 'आ'), ('ee', 'ई'), ('oo', 'ऊ'), ('ai', 'ऐ'),
    ('au', 'औ'), ('ri', 'ऋ'), ('gy', 'ज्ञ'), ('ksh', 'क्ष'),
  ];

  static const Map<String, String> _latinToDevaSingle = {
    'k': 'क', 'g': 'ग', 'c': 'क', 'j': 'ज', 't': 'त',
    'd': 'द', 'n': 'न', 'p': 'प', 'b': 'ब', 'm': 'म',
    'y': 'य', 'r': 'र', 'l': 'ल', 'v': 'व', 'w': 'व',
    's': 'स', 'h': 'ह', 'a': 'अ', 'i': 'इ', 'u': 'उ',
    'e': 'ए', 'o': 'ओ',
  };

  /// Detects the dominant script in the given string based on Unicode blocks.
  static ScriptType detectScript(String text) {
    if (text.trim().isEmpty) return ScriptType.unknown;

    final counts = <ScriptType, int>{};

    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      ScriptType? st;

      if ((code >= 0x0041 && code <= 0x005A) ||
          (code >= 0x0061 && code <= 0x007A)) {
        st = ScriptType.latin;
      } else if (code >= 0x0900 && code <= 0x097F) {
        st = ScriptType.devanagari;
      } else if (code >= 0x0980 && code <= 0x09FF) {
        st = ScriptType.bengali;
      } else if (code >= 0x0A00 && code <= 0x0A7F) {
        st = ScriptType.gurmukhi;
      } else if (code >= 0x0A80 && code <= 0x0AFF) {
        st = ScriptType.gujarati;
      } else if (code >= 0x0B00 && code <= 0x0B7F) {
        st = ScriptType.odia;
      } else if (code >= 0x0B80 && code <= 0x0BFF) {
        st = ScriptType.tamil;
      } else if (code >= 0x0C00 && code <= 0x0C7F) {
        st = ScriptType.telugu;
      } else if (code >= 0x0C80 && code <= 0x0CFF) {
        st = ScriptType.kannada;
      } else if (code >= 0x0D00 && code <= 0x0D7F) {
        st = ScriptType.malayalam;
      }

      if (st != null) {
        counts[st] = (counts[st] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return ScriptType.unknown;

    var dominant = ScriptType.unknown;
    var maxCount = 0;
    counts.forEach((script, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = script;
      }
    });

    return dominant;
  }

  /// Returns the expected script for an ISO language code.
  static ScriptType expectedScriptForLanguage(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'hi':
      case 'mr':
        return ScriptType.devanagari;
      case 'bn':
        return ScriptType.bengali;
      case 'gu':
        return ScriptType.gujarati;
      case 'pa':
        return ScriptType.gurmukhi;
      case 'or':
        return ScriptType.odia;
      case 'ta':
        return ScriptType.tamil;
      case 'te':
        return ScriptType.telugu;
      case 'kn':
        return ScriptType.kannada;
      case 'ml':
        return ScriptType.malayalam;
      case 'en':
      default:
        return ScriptType.latin;
    }
  }

  /// Converts any Indic script character to its canonical Devanagari counterpart.
  /// Uses IndicXlitEngine in Neural mode, PhonologicalTransliterationMatrix in Advanced mode, or legacy ISCII block shift in Legacy mode.
  static String toDevanagari(String text) {
    if (text.trim().isEmpty) return text;
    if (activeMode == NormalizerMode.legacyRuleBased) {
      return _legacyToDevanagari(text);
    }
    final script = detectScript(text);
    if (script == ScriptType.devanagari || script == ScriptType.latin || script == ScriptType.unknown) {
      return text;
    }
    if (activeMode == NormalizerMode.neuralIndicXlit) {
      return IndicXlitEngine.instance.toDevanagari(text, script);
    }
    return PhonologicalTransliterationMatrix.toDevanagariPhonological(text, script);
  }

  /// Legacy ISCII block offset conversion (retained for backward compatibility).
  static String _legacyToDevanagari(String text) {
    if (text.trim().isEmpty) return text;
    final sb = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 0x0980 || code > 0x0D7F) {
        sb.writeCharCode(code);
        continue;
      }

      int? base;
      if (code >= 0x0980 && code <= 0x09FF) {
        base = 0x0980; // Bengali
      } else if (code >= 0x0A00 && code <= 0x0A7F) {
        base = 0x0A00; // Gurmukhi
      } else if (code >= 0x0A80 && code <= 0x0AFF) {
        base = 0x0A80; // Gujarati
      } else if (code >= 0x0B00 && code <= 0x0B7F) {
        base = 0x0B00; // Odia
      } else if (code >= 0x0B80 && code <= 0x0BFF) {
        base = 0x0B80; // Tamil
      } else if (code >= 0x0C00 && code <= 0x0C7F) {
        base = 0x0C00; // Telugu
      } else if (code >= 0x0C80 && code <= 0x0CFF) {
        base = 0x0C80; // Kannada
      } else if (code >= 0x0D00 && code <= 0x0D7F) {
        base = 0x0D00; // Malayalam
      }

      if (base != null) {
        final offset = code - base;
        final devaCode = 0x0900 + offset;
        sb.writeCharCode(devaCode);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  /// Converts Devanagari text to a specific target Indic script.
  /// Uses IndicXlit in Neural mode, PhonologicalTransliterationMatrix in Advanced mode,
  /// or legacy block shift in Legacy mode.
  static String fromDevanagariToIndic(String text, ScriptType targetScript) {
    if (text.trim().isEmpty) return text;
    if (activeMode == NormalizerMode.legacyRuleBased) {
      return _legacyFromDevanagariToIndic(text, targetScript);
    }
    if (activeMode == NormalizerMode.neuralIndicXlit) {
      return IndicXlitEngine.instance.fromDevanagari(text, targetScript);
    }
    return PhonologicalTransliterationMatrix.fromDevanagariPhonological(text, targetScript);
  }

  /// Legacy ISCII block offset conversion to target script.
  static String _legacyFromDevanagariToIndic(String text, ScriptType targetScript) {
    final targetBase = targetScript.unicodeBase;
    if (targetBase == null || targetScript == ScriptType.devanagari) {
      return text;
    }

    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0900 && code <= 0x097F) {
        final offset = code - 0x0900;
        final targetCode = targetBase + offset;
        sb.writeCharCode(targetCode);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  /// Universal transliteration from any Indic script (or Devanagari) to Latin.
  static String toLatin(String input) {
    if (input.trim().isEmpty) return input;
    if (activeMode == NormalizerMode.legacyRuleBased) {
      return _legacyToLatin(input);
    }

    // 1. High-speed whole-word tactical lookup first
    String text = input;
    for (final entry in _devanagariToEnglishLexicon.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    final script = detectScript(text);
    if (activeMode == NormalizerMode.neuralIndicXlit) {
      return IndicXlitEngine.instance.toLatin(text, script).trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return PhonologicalTransliterationMatrix.toLatinPhonological(text, script).trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Legacy rule-based transliteration to Latin.
  static String _legacyToLatin(String input) {
    if (input.trim().isEmpty) return input;

    String devaText = _legacyToDevanagari(input);

    for (final entry in _devanagariToEnglishLexicon.entries) {
      devaText = devaText.replaceAll(entry.key, entry.value);
    }

    final sb = StringBuffer();
    for (int i = 0; i < devaText.length; i++) {
      final char = devaText[i];
      if (_devaToLatinMap.containsKey(char)) {
        sb.write(_devaToLatinMap[char]);
      } else {
        sb.write(char);
      }
    }

    return sb.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Transliterates Romanized / Latin text to Devanagari phonetically.
  static String toDevanagariFromLatin(String input) {
    if (input.trim().isEmpty) return input;
    String text = input.trim();

    // 1. Exact tactical word matching
    final words = text.split(' ');
    final mappedWords = words.map((w) {
      final clean = w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return _englishToDevanagariLexicon[clean] ?? w;
    }).toList();
    text = mappedWords.join(' ');

    // 2. Multi-char phonetic replacements
    for (final (latin, deva) in _latinToDevaMulti) {
      text = text.replaceAll(latin, deva);
      text = text.replaceAll(latin.toUpperCase(), deva);
    }

    // 3. Single-char replacements
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final lower = char.toLowerCase();
      if (_latinToDevaSingle.containsKey(lower)) {
        sb.write(_latinToDevaSingle[lower]);
      } else {
        sb.write(char);
      }
    }
    return sb.toString().trim();
  }

  // ==========================================
  // Core Pipeline Stage Normalizers
  // ==========================================

  /// [STT Output] Normalizes raw STT transcripts according to the user's selected language.
  /// If user selected English ('en') and STT produced Indic script, transliterates to Latin.
  /// If user selected an Indic language and STT produced Latin, transliterates to that native script.
  static String normalizeFromStt(String text, String userLang) {
    if (text.trim().isEmpty) return text;
    final clean = text.trim();
    final detected = detectScript(clean);

    if (userLang.toLowerCase() == 'en') {
      if (detected != ScriptType.latin) {
        debugPrint('[Normalizer] STT produced $detected for English user -> transliterating to Latin');
        return toLatin(clean);
      }
      return clean;
    }

    // User is on an Indic language
    final expected = expectedScriptForLanguage(userLang);
    if (detected == ScriptType.latin) {
      debugPrint('[Normalizer] STT produced Latin for $userLang -> transliterating to $expected');
      final deva = toDevanagariFromLatin(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    // If output is in another Indic script, align it
    if (detected != expected && detected != ScriptType.unknown) {
      debugPrint('[Normalizer] STT produced $detected instead of $expected -> aligning script');
      final deva = toDevanagari(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    return clean;
  }

  /// [MT Input] Prepares text for IndicTrans2 input.
  /// Ensures text is in the native script expected by the source language Flores code.
  static String prepareTextForMt(String text, String sourceLang) {
    if (text.trim().isEmpty) return text;
    final clean = text.trim();
    final detected = detectScript(clean);

    if (sourceLang.toLowerCase() == 'en') {
      if (detected != ScriptType.latin) {
        return toLatin(clean);
      }
      return clean;
    }

    final expected = expectedScriptForLanguage(sourceLang);
    if (detected == ScriptType.latin) {
      final deva = toDevanagariFromLatin(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    if (detected != expected && detected != ScriptType.unknown) {
      final deva = toDevanagari(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    return clean;
  }

  /// [MT Output] Validates and normalizes translation results.
  /// Prevents MT from passing mismatched scripts downstream to TTS.
  static String normalizeFromMt(String text, String targetLang) {
    if (text.trim().isEmpty) return text;
    final clean = text.trim();
    final detected = detectScript(clean);

    if (targetLang.toLowerCase() == 'en') {
      if (detected != ScriptType.latin) {
        debugPrint('[Normalizer] MT returned $detected for English target -> transliterating to Latin');
        return toLatin(clean);
      }
      return clean;
    }

    final expected = expectedScriptForLanguage(targetLang);
    if (detected == ScriptType.latin) {
      debugPrint('[Normalizer] MT returned Latin for $targetLang target -> transliterating to $expected');
      final deva = toDevanagariFromLatin(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    if (detected != expected && detected != ScriptType.unknown) {
      final deva = toDevanagari(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    return clean;
  }

  static const Map<String, String> _gujaratiDigits = {
    '0': 'શૂન્ય', '1': 'એક', '2': 'બે', '3': 'ત્રણ', '4': 'ચાર',
    '5': 'પાંચ', '6': 'છ', '7': 'સાત', '8': 'આઠ', '9': 'નવ',
    '૦': 'શૂન્ય', '૧': 'એક', '૨': 'બે', '૩': 'ત્રણ', '૪': 'ચાર',
    '૫': 'પાંચ', '૬': 'છ', '૭': 'સાત', '૮': 'આઠ', '૯': 'નવ',
  };

  /// Sanitizes Gujarati text specifically for Meta MMS VITS.
  /// Meta MMS 'gu' strictly supports 59 Gujarati characters with NO digits and NO punctuation.
  /// Converts all digits to spelled-out Gujarati words and removes unsupported punctuation.
  static String _sanitizeGujaratiForMms(String text) {
    var out = text;
    _gujaratiDigits.forEach((digit, word) {
      out = out.replaceAll(digit, ' $word ');
    });
    // Strip all punctuation and foreign characters except '-' and '\''
    out = out.replaceAll(RegExp(r"[^\u0A80-\u0AFF\s\-']"), ' ');
    // Collapse whitespace
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.isEmpty ? 'સંદેશ મળ્યો' : out;
  }

  /// [TTS Input] Universal TTS dispatcher.
  /// Ensures text strictly matches the vocabulary and script requirements of the selected TTS engine.
  /// Strips trailing punctuation to eliminate neural duration predictor trailing schwa ("aa" sound).
  static String prepareTextForTts(String text, String targetLang, String ttsEngineType) {
    if (text.trim().isEmpty) return text;

    // 1. Strip trailing sentence terminators, dandas, ellipses, and punctuation
    // This prevents the neural duration predictor from appending an inherent unvoiced terminal syllable ("aa")
    var cleaned = text.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\s\.\।\॥\!\?\,\;\:\_\-\|\~]+$'), '').trim();
    if (cleaned.isEmpty) cleaned = text.trim();

    if (ttsEngineType.toUpperCase() == 'AI4BHARAT_RASA') {
      return prepareTextForRasa13(cleaned, targetLang);
    } else {
      return prepareTextForMms(cleaned, targetLang);
    }
  }

  /// [AI4Bharat Rasa-13 TTS Normalizer]
  /// Rasa-13 supports 13 Indian languages with a rich 1,200+ token vocabulary.
  /// Normalizes punctuation and aligns phonetics to maximize natural prosody.
  static String prepareTextForRasa13(String text, String targetLang) {
    final clean = text.trim();
    final expected = expectedScriptForLanguage(targetLang);
    final detected = detectScript(clean);

    // If English target with Indic script, transliterate to Latin
    if (targetLang.toLowerCase() == 'en' && detected != ScriptType.latin) {
      return toLatin(clean);
    }

    // If Indic target with Latin text, convert to native script
    if (targetLang.toLowerCase() != 'en' && detected == ScriptType.latin) {
      final deva = toDevanagariFromLatin(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    // If text is in another Indic script, align it to the expected script
    if (detected != expected && detected != ScriptType.unknown) {
      final deva = toDevanagari(clean);
      return expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    return clean;
  }

  /// [Meta MMS TTS Normalizer]
  /// STRICT: Meta MMS checkpoints are strictly single-script per language.
  /// Feeding foreign script tokens (e.g., Devanagari to MMS English) produces 0 audio samples (silence).
  static String prepareTextForMms(String text, String targetLang) {
    final clean = text.trim();
    final lang = targetLang.toLowerCase();

    if (lang == 'en') {
      // English target text
      final latinized = toLatin(clean);
      final sanitized = latinized.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      return sanitized.isEmpty ? 'Message received' : sanitized;
    }

    if (lang == 'gu') {
      // Strict Gujarati character vocabulary sanitization
      return _sanitizeGujaratiForMms(clean);
    }

    // For Indic MMS models (e.g. 'hi', 'mr', 'ta', 'te', 'kn', 'ml', 'bn', 'or'):
    final expected = expectedScriptForLanguage(lang);
    final detected = detectScript(clean);

    String normalized = clean;
    if (detected == ScriptType.latin) {
      final deva = toDevanagariFromLatin(clean);
      normalized = expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    } else if (detected != expected && detected != ScriptType.unknown) {
      final deva = toDevanagari(clean);
      normalized = expected == ScriptType.devanagari ? deva : fromDevanagariToIndic(deva, expected);
    }

    // Strip trailing or excessive punctuation that could cause batch splitting
    normalized = normalized.replaceAll(RegExp(r'[\.\।\॥\!\?\,\;\:\_\-\|\~]+$'), '').trim();

    return normalized;
  }

  /// Universal helper for pipeline checkpoints.
  static String ensurePipelineScriptIntegrity({
    required String text,
    required String stage, // 'STT', 'MT_INPUT', 'MT_OUTPUT', 'TTS'
    required String languageCode,
    String ttsEngineType = 'AI4BHARAT_RASA',
  }) {
    switch (stage.toUpperCase()) {
      case 'STT':
        return normalizeFromStt(text, languageCode);
      case 'MT_INPUT':
        return prepareTextForMt(text, languageCode);
      case 'MT_OUTPUT':
        return normalizeFromMt(text, languageCode);
      case 'TTS':
        return prepareTextForTts(text, languageCode, ttsEngineType);
      default:
        return text;
    }
  }
}
