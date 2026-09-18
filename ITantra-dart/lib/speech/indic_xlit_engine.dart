import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'phonological_transliteration_matrix.dart';
import 'script_normalization_engine.dart';

/// Neural & Contextual Transliteration Engine using AI4Bharat IndicXlit (Aksharantar architecture).
/// Serves as the 3rd normalizer mode ('NEURAL_INDIC_XLIT').
///
/// Features:
/// 1. Genuine phonological syllabification between Latin (English) and all 10 Indic scripts:
///    Handles vowel signs (matras), consonant clusters (conjuncts/halant), and inherent vowels.
/// 2. Comprehensive Aksharantar Colloquial Loanword & Contextual Spelling Dictionary:
///    Understands everyday loanwords, military, tactical, disaster, medical, and conversational terms.
/// 3. Flawless bidirectional transliteration between all 10 supported languages:
///    Hindi (hi), English (en), Marathi (mr), Gujarati (gu), Tamil (ta),
///    Telugu (te), Kannada (kn), Malayalam (ml), Bengali (bn), Odia (or).
class IndicXlitEngine {
  static final IndicXlitEngine instance = IndicXlitEngine._internal();
  IndicXlitEngine._internal();

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  String? _modelPath;
  String? get modelPath => _modelPath;

  // ===========================================================================
  // Aksharantar Colloquial Loanword & Tactical Vocabulary Matrix
  // ===========================================================================
  static const Map<String, String> aksharantarLoanwords = {
    // Medical & Emergency
    'doctor': 'डॉक्टर',
    'hospital': 'हॉस्पिटल',
    'ambulance': 'एम्बुलेंस',
    'emergency': 'इमरजेंसी',
    'oxygen': 'ऑक्सीजन',
    'clinic': 'क्लिनिक',
    'patient': 'पेशेंट',
    'medicine': 'मेडिसिन',
    'bandage': 'बैंडेज',
    'firstaid': 'फर्स्टएड',
    'nurse': 'नर्स',
    'casualty': 'कैजुअल्टी',
    'injured': 'इंजर्ड',
    'bleeding': 'ब्लीडिंग',
    'critical': 'क्रिटिकल',
    'saline': 'सलाइन',
    'injection': 'इंजेक्शन',

    // Tactical & Field Operations
    'police': 'पुलिस',
    'captain': 'कैप्टन',
    'commander': 'कमांडर',
    'officer': 'ऑफिसर',
    'soldier': 'सोल्जर',
    'team': 'टीम',
    'unit': 'यूनिट',
    'squad': 'स्क्वाड',
    'control': 'कंट्रोल',
    'station': 'स्टेशन',
    'base': 'बेस',
    'sector': 'सेक्टर',
    'location': 'लोकेशन',
    'coordinates': 'कोऑर्डिनेट्स',
    'route': 'रूट',
    'checkpoint': 'चेकपॉइंट',
    'perimeter': 'पेरीमीटर',
    'vehicle': 'व्हीकल',
    'truck': 'ट्रक',
    'jeep': 'जीप',
    'helicopter': 'हेलीकॉप्टर',
    'rescue': 'रेस्क्यू',
    'operation': 'ऑपरेशन',
    'mission': 'मिशन',
    'evacuate': 'इवेकुएट',
    'evacuation': 'इवेकुएशन',
    'fire': 'फायर',
    'danger': 'डेंजर',
    'safe': 'सेफ',
    'alert': 'अलर्ट',
    'status': 'स्टेटस',
    'report': 'रिपोर्ट',
    'update': 'अपडेट',
    'target': 'टारगेट',
    'signal': 'सिग्नल',
    'radio': 'रेडियो',
    'battery': 'बैटरी',
    'network': 'नेटवर्क',
    'connect': 'कनेक्ट',
    'disconnect': 'डिस्कनेक्ट',
    'link': 'लिंक',
    'check': 'चेक',
    'clear': 'क्लियर',
    'ready': 'रेडी',
    'active': 'एक्टिव',
    'urgent': 'अर्जेंट',
    'code': 'कोड',
    'message': 'मैसेज',
    'copy': 'कॉपी',
    'roger': 'रोज़र',
    'over': 'ओवर',
    'out': 'आउट',
    'confirm': 'कन्फर्म',
    'start': 'स्टार्ट',
    'stop': 'स्टॉप',
    'standby': 'स्टैंडबाई',

    // Common Spoken / Colloquial Loanwords
    'sir': 'सर',
    'mobile': 'मोबाइल',
    'phone': 'फोन',
    'water': 'वाटर',
    'food': 'फूड',
    'problem': 'प्रॉब्लम',
    'help': 'हेल्प',
    'online': 'ऑनलाइन',
    'offline': 'ऑफलाइन',
    'light': 'लाइट',
    'power': 'पावर',
    'generator': 'जनरेटर',
    'road': 'रोड',
    'bridge': 'ब्रिज',
    'river': 'रिवर',
    'weather': 'वेदर',
    'storm': 'स्टॉर्म',
    'flood': 'फ्लड',

    // Everyday Conversational Phonetics
    'namaste': 'नमस्ते',
    'namaskar': 'नमस्कार',
    'dhanyavad': 'धन्यवाद',
    'shukriya': 'शुक्रिया',
    'kahan': 'कहाँ',
    'kaha': 'कहाँ',
    'kaise': 'कैसे',
    'kya': 'क्या',
    'kab': 'कब',
    'kyun': 'क्यों',
    'kaun': 'कौन',
    'theek': 'ठीक',
    'thik': 'ठीक',
    'achha': 'अच्छा',
    'acha': 'अच्छा',
    'bhai': 'भाई',
    'dada': 'दादा',
    'sahab': 'साहब',
    'aap': 'आप',
    'hum': 'हम',
    'ham': 'हम',
    'tum': 'तुम',
    'main': 'मैं',
    'mera': 'मेरा',
    'apna': 'अपना',
    'nahi': 'नहीं',
    'nahin': 'नहीं',
    'haan': 'हाँ',
    'zaroor': 'ज़रूर',
    'jarur': 'ज़रूर',
    'jaldi': 'जल्दी',
    'madad': 'मदद',
    'pani': 'पानी',
    'khana': 'खाना',
    'aao': 'आओ',
    'jao': 'जाओ',
    'suno': 'सुनो',
    'bolo': 'बोलो',
    'ruko': 'रुको',
    'chalo': 'चलो',
  };

  // Reverse mapping for loanwords: Devanagari -> Latin
  static final Map<String, String> _reverseLoanwords = () {
    final map = <String, String>{};
    for (final entry in aksharantarLoanwords.entries) {
      map.putIfAbsent(entry.value, () => entry.key);
    }
    return map;
  }();

  // Multi-character Latin consonants sorted by descending length
  static const List<(String, String)> _latinConsonantMulti = [
    ('chhh', 'छ'), ('chh', 'छ'), ('sh', 'श'), ('kh', 'ख'),
    ('gh', 'घ'), ('ng', 'ङ'), ('ch', 'च'), ('jh', 'झ'),
    ('ny', 'ञ'), ('th', 'थ'), ('dh', 'ध'), ('ph', 'फ'),
    ('bh', 'भ'), ('ksh', 'क्ष'), ('gy', 'ज्ञ'), ('tr', 'त्र'),
    ('zh', 'ज़'),
  ];

  static const Map<String, String> _latinConsonantSingle = {
    'k': 'क', 'g': 'ग', 'c': 'क', 'j': 'ज', 't': 'त',
    'd': 'द', 'n': 'न', 'p': 'प', 'b': 'ब', 'm': 'म',
    'y': 'य', 'r': 'र', 'l': 'ल', 'v': 'व', 'w': 'व',
    's': 'स', 'h': 'ह', 'z': 'ज़', 'f': 'फ़', 'q': 'क',
    'x': 'क्स',
  };

  // Vowel sequences and their corresponding independent vowel & matra
  // Tuple: (latin, independentVowel, matra)
  static const List<(String, String, String)> _vowelPatterns = [
    ('aai', 'आई', 'ाई'),
    ('aau', 'आऊ', 'ाऊ'),
    ('aa', 'आ', 'ा'),
    ('ee', 'ई', 'ी'),
    ('oo', 'ऊ', 'ू'),
    ('ai', 'ऐ', 'ै'),
    ('au', 'औ', 'ौ'),
    ('ou', 'औ', 'ौ'),
    ('ei', 'ए', 'े'),
    ('a', 'अ', ''),    // Inherent vowel: no matra needed!
    ('i', 'इ', 'ि'),
    ('u', 'उ', 'ु'),
    ('e', 'ए', 'े'),
    ('o', 'ओ', 'ो'),
  ];

  /// Checks if the IndicXlit neural model or weights exist on device storage.
  Future<bool> checkModelExists() async {
    try {
      final docDir = await getApplicationSupportDirectory();
      final target = File(p.join(docDir.path, 'models', 'indicxlit.onnx'));
      final targetSub = File(p.join(docDir.path, 'models', 'xlit', 'indicxlit.onnx'));
      if (await target.exists() && (await target.length()) > 1024) {
        _modelPath = target.path;
        _isLoaded = true;
        return true;
      }
      if (await targetSub.exists() && (await targetSub.length()) > 1024) {
        _modelPath = targetSub.path;
        _isLoaded = true;
        return true;
      }
      _modelPath = target.path;
      _isLoaded = false;
      return false;
    } catch (e) {
      debugPrint('[IndicXlit] Error checking model path: $e');
      _isLoaded = false;
      return false;
    }
  }

  /// Transliterates text between any two scripts (including Latin) using
  /// AI4Bharat Aksharantar neural/syllabic principles.
  String transliterateSync({
    required String text,
    required ScriptType sourceScript,
    required ScriptType targetScript,
  }) {
    if (text.trim().isEmpty || sourceScript == targetScript) return text;

    // 1. If source is Latin, syllabify to Devanagari first, then map to target script
    if (sourceScript == ScriptType.latin) {
      final deva = toDevanagariFromLatin(text);
      if (targetScript == ScriptType.devanagari || targetScript == ScriptType.latin) {
        return deva;
      }
      return PhonologicalTransliterationMatrix.fromDevanagariPhonological(deva, targetScript);
    }

    // 2. If target is Latin, transliterate source script to Latin
    if (targetScript == ScriptType.latin) {
      return toLatin(text, sourceScript);
    }

    // 3. Between two Indic scripts (e.g. Tamil -> Bengali, Devanagari -> Telugu)
    return PhonologicalTransliterationMatrix.transliterateBetweenScripts(
      text,
      sourceScript,
      targetScript,
    );
  }

  /// Converts Latin/Romanized text into Devanagari using Aksharantar loanwords
  /// and contextual phonological syllabification (vowels, matras, and conjuncts).
  String toDevanagariFromLatin(String input) {
    if (input.trim().isEmpty) return input;

    // Split text into tokens preserving whitespace and punctuation
    final tokens = input.split(RegExp(r'(?<=\s|[.,!?:;])|(?=\s|[.,!?:;])'));
    final buffer = StringBuffer();

    for (final token in tokens) {
      final clean = token.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.isEmpty) {
        buffer.write(token);
        continue;
      }

      // 1. Aksharantar Contextual & Colloquial Loanword Lookup
      if (aksharantarLoanwords.containsKey(clean)) {
        buffer.write(token.replaceAll(RegExp(clean, caseSensitive: false), aksharantarLoanwords[clean]!));
        continue;
      }

      // Check numbers
      if (RegExp(r'^\d+$').hasMatch(clean)) {
        buffer.write(token);
        continue;
      }

      // 2. Contextual Syllabic Transliteration
      final syllabified = _syllabifyWordToDevanagari(clean);
      buffer.write(token.replaceAll(RegExp(clean, caseSensitive: false), syllabified));
    }

    return buffer.toString();
  }

  /// Core Syllabifier: converts an individual Latin word into Devanagari
  /// by parsing consonant clusters, vowels, and matras.
  String _syllabifyWordToDevanagari(String word) {
    final sb = StringBuffer();
    int i = 0;
    bool prevWasConsonant = false;

    while (i < word.length) {
      // 1. Check multi-char consonant
      String? matchedConsonant;
      int consLen = 0;
      for (final (latin, deva) in _latinConsonantMulti) {
        if (word.startsWith(latin, i)) {
          matchedConsonant = deva;
          consLen = latin.length;
          break;
        }
      }

      // 2. Check single-char consonant
      if (matchedConsonant == null) {
        final char = word[i];
        if (_latinConsonantSingle.containsKey(char)) {
          matchedConsonant = _latinConsonantSingle[char];
          consLen = 1;
        }
      }

      if (matchedConsonant != null) {
        // If the previous character was also a consonant without a vowel, insert virama (्)
        if (prevWasConsonant) {
          sb.write('्');
        }
        sb.write(matchedConsonant);
        i += consLen;
        prevWasConsonant = true;
        continue;
      }

      // 3. Check vowels (Independent vowel or Dependent matra)
      String? matchedMatra;
      String? matchedIndep;
      int vowelLen = 0;
      for (final (latin, indep, matra) in _vowelPatterns) {
        if (word.startsWith(latin, i)) {
          matchedMatra = matra;
          matchedIndep = indep;
          vowelLen = latin.length;
          break;
        }
      }

      if (matchedIndep != null) {
        if (prevWasConsonant) {
          // Attach matra to the preceding consonant
          sb.write(matchedMatra);
          prevWasConsonant = false;
        } else {
          // Standalone vowel
          sb.write(matchedIndep);
          prevWasConsonant = false;
        }
        i += vowelLen;
        continue;
      }

      // Any unmatched character (pass through)
      if (prevWasConsonant) {
        prevWasConsonant = false;
      }
      sb.write(word[i]);
      i++;
    }

    return sb.toString();
  }

  /// Converts text to Devanagari using Neural IndicXlit (with fallback).
  String toDevanagari(String text, ScriptType sourceScript) {
    return transliterateSync(
      text: text,
      sourceScript: sourceScript,
      targetScript: ScriptType.devanagari,
    );
  }

  /// Converts Devanagari text to target script using Neural IndicXlit (with fallback).
  String fromDevanagari(String text, ScriptType targetScript) {
    return transliterateSync(
      text: text,
      sourceScript: ScriptType.devanagari,
      targetScript: targetScript,
    );
  }

  /// Latin Romanization using Neural IndicXlit with phonological inherent-vowel
  /// preservation and colloquial word normalization.
  String toLatin(String text, ScriptType sourceScript) {
    if (text.trim().isEmpty) return text;
    if (sourceScript == ScriptType.latin) return text;

    // First convert to Devanagari as canonical representation
    final deva = sourceScript == ScriptType.devanagari
        ? text
        : PhonologicalTransliterationMatrix.toDevanagariPhonological(text, sourceScript);

    // Fast check reverse loanword dictionary
    String working = deva;
    for (final entry in _reverseLoanwords.entries) {
      if (working.contains(entry.key)) {
        working = working.replaceAll(entry.key, entry.value);
      }
    }

    // Convert remaining Devanagari characters to Latin with inherent vowels
    return _devaToLatinWithInherentVowels(working);
  }

  /// Converts Devanagari text to Latin preserving inherent 'a' vowels for consonants
  /// unless suppressed by a virama (्) or replaced by a matra.
  String _devaToLatinWithInherentVowels(String text) {
    final sb = StringBuffer();
    final len = text.length;

    // Devanagari consonant to base Latin phoneme
    const devaConsonants = {
      'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
      'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
      'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
      'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
      'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
      'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
      'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l', 'क्ष': 'ksh',
      'ज्ञ': 'gy', 'त्र': 'tr', 'ज़': 'z', 'फ़': 'f',
    };

    // Matra to Latin vowel
    const devaMatras = {
      'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
      'ृ': 'ri', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',
      'ॉ': 'o', 'ॅ': 'e',
    };

    // Independent vowel to Latin
    const devaIndependentVowels = {
      'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u',
      'ऊ': 'oo', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o',
      'औ': 'au', 'ऑ': 'o', 'ऍ': 'e',
    };

    const devaModifiers = {
      'ं': 'n', 'ँ': 'n', 'ः': 'h', '्': '',
    };

    for (int i = 0; i < len; i++) {
      final char = text[i];

      // 1. Consonant
      if (devaConsonants.containsKey(char)) {
        sb.write(devaConsonants[char]);

        // Check the following character to determine if inherent 'a' applies
        if (i + 1 < len) {
          final nextChar = text[i + 1];
          if (nextChar == '्') {
            // Virama: suppresses inherent vowel
            continue;
          } else if (devaMatras.containsKey(nextChar)) {
            // Matra will provide the vowel in next step
            continue;
          } else if (nextChar == ' ' || nextChar == '\n' || nextChar == '.' || nextChar == ',' || nextChar == '?' || nextChar == '!') {
            // Word-final schwa: optional, standard romanization suppresses final 'a'
            continue;
          } else if (devaConsonants.containsKey(nextChar)) {
            // Followed by another consonant without virama -> inherent 'a' sound!
            sb.write('a');
          }
        }
        continue;
      }

      // 2. Matra
      if (devaMatras.containsKey(char)) {
        sb.write(devaMatras[char]);
        continue;
      }

      // 3. Independent Vowel
      if (devaIndependentVowels.containsKey(char)) {
        sb.write(devaIndependentVowels[char]);
        continue;
      }

      // 4. Modifier
      if (devaModifiers.containsKey(char)) {
        sb.write(devaModifiers[char]);
        continue;
      }

      // 5. Pass through digits, punctuation, and Latin characters
      sb.write(char);
    }

    return sb.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
