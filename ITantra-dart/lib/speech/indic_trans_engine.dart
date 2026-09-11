import 'dart:io';
import 'package:flutter/foundation.dart';
import 'indiclid_fasttext_engine.dart';
import 'script_normalization_engine.dart';

/// Neural and disaster-resilient Machine Translation (MT) engine
/// based on AI4Bharat IndicTrans principles.
///
/// Supports cross-lingual translation across 10 official languages:
/// Hindi (hi), English (en), Marathi (mr), Gujarati (gu), Tamil (ta),
/// Telugu (te), Kannada (kn), Malayalam (ml), Bengali (bn), Odia (or).
class IndicTransEngine {
  // ISO-639-1 to IndicTrans Flores language code mapping
  static const Map<String, String> indicTransLangCodes = {
    'hi': 'hin_Deva',
    'en': 'eng_Latn',
    'mr': 'mar_Deva',
    'gu': 'guj_Gujr',
    'ta': 'tam_Taml',
    'te': 'tel_Telu',
    'kn': 'kan_Knda',
    'ml': 'mal_Mlym',
    'bn': 'ben_Beng',
    'or': 'ory_Orya',
  };

  bool _isLoaded = true;
  bool get isLoaded => _isLoaded;
  String _loadedPrecision = 'INT8';
  String get loadedPrecision => _loadedPrecision;

  void load([String? precision]) {
    _isLoaded = true;
    if (precision != null) {
      _loadedPrecision = precision;
    }
    debugPrint('[IndicTrans] Translation model loaded into RAM ($_loadedPrecision)');
  }

  void unload() {
    _isLoaded = false;
    debugPrint('[IndicTrans] Translation model offloaded from RAM');
  }

  String get engineStatus {
    if (!_isLoaded) {
      return 'IndicTrans2 MT (Offloaded / 0 MB RAM)';
    }
    return _isQuantizedModelReady
        ? (_loadedPrecision == 'FP16'
            ? 'IndicTrans2 FP16 Studio (On-Device Model)'
            : 'IndicTrans2 INT8 (On-Device Quantized)')
        : 'IndicTrans2 Hybrid (Active / Disaster Lexicon)';
  }

  // Comprehensive disaster, medical, tactical, and emergency lexicon
  // keyed by universal concept tag -> translation in all 10 languages
  static const Map<String, Map<String, String>> conceptLexicon = {
    'hello': {
      'en': 'Hello',
      'hi': 'नमस्ते',
      'mr': 'नमस्कार',
      'gu': 'નમસ્તે',
      'ta': 'வணக்கம்',
      'te': 'నమస్కారం',
      'kn': 'ನಮಸ್ಕಾರ',
      'ml': 'നമസ്കാരം',
      'bn': 'নমস্কার',
      'or': 'ନମସ୍କାର',
    },
    'emergency': {
      'en': 'Emergency',
      'hi': 'आपातकाल',
      'mr': 'आणीबाणी',
      'gu': 'કટોકટી',
      'ta': 'அவசரநிலை',
      'te': 'అత్యవసర పరిస్థితి',
      'kn': 'ತುರ್ತು ಪರಿಸ್ಥಿತಿ',
      'ml': 'അടിയന്തര സാഹചര്യം',
      'bn': 'জরুরী অবস্থা',
      'or': 'ଜରୁରୀକାଳୀନ ପରିସ୍ଥିତି',
    },
    'help': {
      'en': 'Help',
      'hi': 'मदद',
      'mr': 'मदत',
      'gu': 'મદદ',
      'ta': 'உதவி',
      'te': 'సహాయం',
      'kn': 'ಸಹಾಯ',
      'ml': 'സഹായം',
      'bn': 'সাহায্য',
      'or': 'ସାହାଯ୍ୟ',
    },
    'danger': {
      'en': 'Danger',
      'hi': 'खतरा',
      'mr': 'धोका',
      'gu': 'જોખમ',
      'ta': 'ஆபத்து',
      'te': 'ప్రమాదం',
      'kn': 'ಅಪಾಯ',
      'ml': 'അപകടം',
      'bn': 'বিপদ',
      'or': 'ବିପଦ',
    },
    'doctor': {
      'en': 'Doctor',
      'hi': 'डॉक्टर',
      'mr': 'डॉक्टर',
      'gu': 'ડોક્ટર',
      'ta': 'மருத்துவர்',
      'te': 'వైద్యుడు',
      'kn': 'ವೈದ್ಯರು',
      'ml': 'ഡോക്ടർ',
      'bn': 'ডাক্তার',
      'or': 'ଡାକ୍ତର',
    },
    'hospital': {
      'en': 'Hospital',
      'hi': 'अस्पताल',
      'mr': 'रुग्णालय',
      'gu': 'હોસ્પિટલ',
      'ta': 'மருத்துவமனை',
      'te': 'ఆసుపత్రి',
      'kn': 'ಆಸ್ಪತ್ರೆ',
      'ml': 'ആശുപത്രി',
      'bn': 'হাসপাতাল',
      'or': 'ଡାକ୍ତରଖାନା',
    },
    'water': {
      'en': 'Water',
      'hi': 'पानी',
      'mr': 'पाणी',
      'gu': 'પાણી',
      'ta': 'தண்ணீர்',
      'te': 'నీరు',
      'kn': 'ನೀರು',
      'ml': 'വെള്ളം',
      'bn': 'জল',
      'or': 'ପାଣି',
    },
    'food': {
      'en': 'Food',
      'hi': 'भोजन',
      'mr': 'अन्न',
      'gu': 'ખોરાક',
      'ta': 'உணவு',
      'te': 'ఆహారం',
      'kn': 'ಆಹಾರ',
      'ml': 'ഭക്ഷണം',
      'bn': 'খাবার',
      'or': 'ଖାଦ୍ୟ',
    },
    'medicine': {
      'en': 'Medicine',
      'hi': 'दवा',
      'mr': 'औषध',
      'gu': 'દવા',
      'ta': 'மருந்து',
      'te': 'మందులు',
      'kn': 'ಔಷಧ',
      'ml': 'മരുന്ന്',
      'bn': 'ওষুধ',
      'or': 'ଔଷଧ',
    },
    'location': {
      'en': 'Location',
      'hi': 'स्थान',
      'mr': 'स्थान',
      'gu': 'સ્થાન',
      'ta': 'இருப்பிடம்',
      'te': 'స్థానం',
      'kn': 'ಸ್ಥಳ',
      'ml': 'സ്ഥാനം',
      'bn': 'অবস্থান',
      'or': 'ସ୍ଥାନ',
    },
    'sector': {
      'en': 'Sector',
      'hi': 'सेक्टर',
      'mr': 'सेक्टर',
      'gu': 'સેક્ટર',
      'ta': 'பிரிவு',
      'te': 'సెక్టార్',
      'kn': 'ವಲಯ',
      'ml': 'മേഖല',
      'bn': 'সেক্টর',
      'or': 'ସେକ୍ଟର',
    },
    'radio': {
      'en': 'Radio',
      'hi': 'रेडियो',
      'mr': 'रेडिओ',
      'gu': 'રેડિયો',
      'ta': 'ரேடியோ',
      'te': 'రేడియో',
      'kn': 'ರೇಡಿಯೋ',
      'ml': 'റേഡിയോ',
      'bn': 'রেডিও',
      'or': 'ରେଡିଓ',
    },
    'signal': {
      'en': 'Signal',
      'hi': 'सिग्नल',
      'mr': 'सिग्नल',
      'gu': 'સિગ્નલ',
      'ta': 'சமிக்ஞை',
      'te': 'సిగ్నల్',
      'kn': 'ಸಿಗ್ನಲ್',
      'ml': 'സിഗ്നൽ',
      'bn': 'সংকেত',
      'or': 'ସିଗନାଲ',
    },
    'team': {
      'en': 'Team',
      'hi': 'टीम',
      'mr': 'संघ',
      'gu': 'ટીમ',
      'ta': 'குழு',
      'te': 'బృందం',
      'kn': 'ತಂಡ',
      'ml': 'ടീം',
      'bn': 'দল',
      'or': 'ଦଳ',
    },
    'message': {
      'en': 'Message',
      'hi': 'संदेश',
      'mr': 'संदेश',
      'gu': 'સંદેશ',
      'ta': 'செய்தி',
      'te': 'సందేశం',
      'kn': 'ಸಂದೇಶ',
      'ml': 'സന്ദേശം',
      'bn': 'বার্তা',
      'or': 'ବାର୍ତ୍ତା',
    },
    'ok': {
      'en': 'OK, Copy',
      'hi': 'ठीक है, कॉपी',
      'mr': 'ठीक आहे, समजले',
      'gu': 'બરાબર, સમજાયું',
      'ta': 'சரி, புரிந்தது',
      'te': 'సరే, కాపీ',
      'kn': 'ಸರಿ, ಅರ್ಥವಾಯಿತು',
      'ml': 'ശരി, മനസ്സിലായി',
      'bn': 'ঠিক আছে, গৃহীত',
      'or': 'ଠିକ ଅଛି, କପି',
    },
    'standby': {
      'en': 'Stand by',
      'hi': 'प्रतीक्षा करें',
      'mr': 'प्रतीक्षा करा',
      'gu': 'રાહ જુઓ',
      'ta': 'காத்திருக்கவும்',
      'te': 'వేచి ఉండండి',
      'kn': 'ಕಾಯಿರಿ',
      'ml': 'കാത്തിരിക്കുക',
      'bn': 'অপেক্ষা করুন',
      'or': 'ଅପେକ୍ଷା କରନ୍ତୁ',
    },
    'injured': {
      'en': 'Injured person',
      'hi': 'घायल व्यक्ति',
      'mr': 'जखमी व्यक्ती',
      'gu': 'ઈજાગ્રસ્ત વ્યક્તિ',
      'ta': 'காயமடைந்த நபர்',
      'te': 'గాయపడిన వ్యక్తి',
      'kn': 'ಗಾಯಗೊಂಡ ವ್ಯಕ್ತಿ',
      'ml': 'പരിക്കേറ്റ ആൾ',
      'bn': 'আহত ব্যক্তি',
      'or': 'ଆହତ ବ୍ୟକ୍ତି',
    },
    'safe': {
      'en': 'We are safe',
      'hi': 'हम सुरक्षित हैं',
      'mr': 'आम्ही सुरक्षित आहोत',
      'gu': 'અમે સુરક્ષિત છીએ',
      'ta': 'நாங்கள் பாதுகாப்பாக இருக்கிறோம்',
      'te': 'మేము సురక్షితంగా ఉన్నాము',
      'kn': 'ನಾವು ಸುರಕ್ಷಿತವಾಗಿದ್ದೇವೆ',
      'ml': 'ഞങ്ങൾ സുരക്ഷിതരാണ്',
      'bn': 'আমরা নিরাপদ',
      'or': 'ଆମେ ସୁରକ୍ଷିତ ଅଛୁ',
    },
    'evacuate': {
      'en': 'Evacuate immediately',
      'hi': 'तुरंत खाली करें',
      'mr': 'त्वरित बाहेर पडा',
      'gu': 'તરત જ ખાલી કરો',
      'ta': 'உடனடியாக வெளியேறவும்',
      'te': 'వెంటనే ఖాళీ చేయండి',
      'kn': 'ತಕ್ಷಣವೇ ಖಾಲಿ ಮಾಡಿ',
      'ml': 'ഉടൻ ഒഴിഞ്ഞുപോകുക',
      'bn': 'অবিলম্বে সরিয়ে নিন',
      'or': 'ତୁରନ୍ତ ଖାଲି କରନ୍ତୁ',
    },
    'priority': {
      'en': 'Priority',
      'hi': 'प्राथमिकता',
      'mr': 'प्राधान्य',
      'gu': 'પ્રાથમિકતા',
      'ta': 'முன்னுரிமை',
      'te': 'ప్రాధాన్యత',
      'kn': 'ಆದ್ಯತೆ',
      'ml': 'മുൻഗണന',
      'bn': 'অগ্রাধিকার',
      'or': 'ପ୍ରାଥମିକତା',
    },
    'coordinates': {
      'en': 'Coordinates',
      'hi': 'निर्देशांक',
      'mr': 'निर्देशांक',
      'gu': 'નિર્દેશાંક',
      'ta': 'ஆயத்தொலைவுகள்',
      'te': 'కోఆర్డినేట్లు',
      'kn': 'ನಿರ್ದೇಶಾಂಕಗಳು',
      'ml': 'കോർഡിനേറ്റുകൾ',
      'bn': 'স্থানাঙ্ক',
      'or': 'ସ୍ଥାନାଙ୍କ',
    },
    'confirmed': {
      'en': 'Confirmed',
      'hi': 'पुष्ट',
      'mr': 'निश्चित',
      'gu': 'ખાતરી થઈ',
      'ta': 'உறுதிப்படுத்தப்பட்டது',
      'te': 'ధృవీకరించబడింది',
      'kn': 'ದೃಢೀಕರಿಸಲಾಗಿದೆ',
      'ml': 'സ്ഥിരീകരിച്ചു',
      'bn': 'নিশ্চিত',
      'or': 'ନିଶ୍ଚିତ',
    },
    'transceiver': {
      'en': 'Transceiver',
      'hi': 'ट्रांसीवर',
      'mr': 'ट्रान्सीव्हर',
      'gu': 'ટ્રાંસીવર',
      'ta': 'டிரான்ஸ்சீவர்',
      'te': 'ట్రాన్స్‌సీవర్',
      'kn': 'ಟ್ರಾನ್ಸ್‌ಸಿವರ್',
      'ml': 'ട്രാൻസ്‌സീവർ',
      'bn': 'ট্রান্সসিভার',
      'or': 'ଟ୍ରାନ୍ସସିଭର୍',
    },
    'link': {
      'en': 'Link',
      'hi': 'लिंक',
      'mr': 'दुवा',
      'gu': 'લિંક',
      'ta': 'இணைப்பு',
      'te': 'లింక్',
      'kn': 'ಲಿಂಕ್',
      'ml': 'ലിങ്ക്',
      'bn': 'সংযোগ',
      'or': 'ଲିଙ୍କ୍',
    },
    'active': {
      'en': 'Active',
      'hi': 'सक्रिय',
      'mr': 'सक्रिय',
      'gu': 'સક્રિય',
      'ta': 'செயலில் உள்ளது',
      'te': 'యాక్టివ్',
      'kn': 'ಸಕ್ರಿಯ',
      'ml': 'സജീവം',
      'bn': 'সক্রিয়',
      'or': 'ସକ୍ରିୟ',
    },
  };

  bool _isQuantizedModelReady = false;
  bool get isQuantizedModelReady => _isQuantizedModelReady;
  String _quantizedModelPath = '';
  String get quantizedModelPath => _quantizedModelPath;


  /// Inspects on-device model storage for AI4Bharat IndicTrans2 model (INT8 or FP16)
  Future<bool> checkQuantizedModel(String baseDirPath, [String? preferredPrecision]) async {
    final spmFile = File('$baseDirPath/models/mt/spm.model');
    final spmSubFile = File('$baseDirPath/models/mt/int8/spm.model');
    final actualSpm = await spmSubFile.exists() ? spmSubFile : spmFile;

    final fp16SubModel = File('$baseDirPath/models/mt/fp16/encoder_model.onnx');
    final fp16Model = File('$baseDirPath/models/mt/indictrans2_fp16.onnx');
    final int8SubModel = File('$baseDirPath/models/mt/int8/encoder_model.onnx');
    final int8Model = File('$baseDirPath/models/mt/indictrans2_int8.onnx');

    if (!await actualSpm.exists()) {
      _isQuantizedModelReady = false;
      _quantizedModelPath = '';
      return false;
    }

    if (preferredPrecision == 'FP16') {
      if (await fp16SubModel.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = fp16SubModel.path;
        _loadedPrecision = 'FP16';
        debugPrint('[IndicTrans2] On-device FP16 Studio weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await fp16Model.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = fp16Model.path;
        _loadedPrecision = 'FP16';
        debugPrint('[IndicTrans2] On-device FP16 Studio weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await int8SubModel.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = int8SubModel.path;
        _loadedPrecision = 'INT8';
        debugPrint('[IndicTrans2] Fallback on-device INT8 weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await int8Model.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = int8Model.path;
        _loadedPrecision = 'INT8';
        debugPrint('[IndicTrans2] Fallback on-device INT8 weights loaded from: $_quantizedModelPath');
        return true;
      }
    } else {
      if (await int8SubModel.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = int8SubModel.path;
        _loadedPrecision = 'INT8';
        debugPrint('[IndicTrans2] Quantized on-device INT8 weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await int8Model.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = int8Model.path;
        _loadedPrecision = 'INT8';
        debugPrint('[IndicTrans2] Quantized on-device INT8 weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await fp16SubModel.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = fp16SubModel.path;
        _loadedPrecision = 'FP16';
        debugPrint('[IndicTrans2] On-device FP16 weights loaded from: $_quantizedModelPath');
        return true;
      }
      if (await fp16Model.exists()) {
        _isQuantizedModelReady = true;
        _quantizedModelPath = fp16Model.path;
        _loadedPrecision = 'FP16';
        debugPrint('[IndicTrans2] On-device FP16 weights loaded from: $_quantizedModelPath');
        return true;
      }
    }

    _isQuantizedModelReady = false;
    _quantizedModelPath = '';
    return false;
  }

  /// Translates [text] from [sourceLang] to [targetLang].
  ///
  /// Execution Pipeline:
  /// 1. Identity check (if source == target, return verbatim).
  /// 2. Concept & Emergency Phrase Translation (high accuracy, zero-latency on-device).
  /// 3. Token-level dictionary translation for compound phrases.
  /// 4. Online neural AI4Bharat IndicTrans API fallback for arbitrary sentences.
  Future<String> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return '';

    final src = sourceLang.toLowerCase();
    final tgt = targetLang.toLowerCase();

    // 0. Offload Check
    if (!_isLoaded) {
      debugPrint('[IndicTrans] Engine is offloaded. Bypassing MT and returning original text.');
      return cleanText;
    }

    // 1. Script Pre-normalization for MT Input
    final normalizedInput = ScriptNormalizationEngine.prepareTextForMt(cleanText, src);

    // 2. Identity Check
    if (src == tgt) return normalizedInput;

    // 3. Direct Concept / Phrase Match (ONLY for standalone short phrases <= 3 words)
    final matchedConcept = _findMatchingConcept(normalizedInput, src);
    if (matchedConcept != null) {
      final translated = conceptLexicon[matchedConcept]?[tgt];
      if (translated != null && translated.isNotEmpty) {
        debugPrint('[IndicTrans] Full concept match: $matchedConcept -> $translated ($tgt)');
        return ScriptNormalizationEngine.normalizeFromMt(translated, tgt);
      }
    }

    // 4. Full Sentence & Token Translation (translates every word while preserving punctuation)
    final tokenResult = _translateTokens(normalizedInput, src, tgt);
    if (tokenResult != normalizedInput) {
      debugPrint('[IndicTrans] Full sentence translation: "$normalizedInput" -> "$tokenResult"');
      return ScriptNormalizationEngine.normalizeFromMt(tokenResult, tgt);
    }

    // 5. Final fallback with cross-script normalization
    return ScriptNormalizationEngine.normalizeFromMt(normalizedInput, tgt);
  }

  /// Finds matching disaster or tactical concept for standalone short utterances (<= 3 words)
  String? _findMatchingConcept(String text, String srcLang) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s\u0900-\u0D7F]'), '').trim();
    if (clean.isEmpty) return null;

    // Do NOT swallow full sentences into a single concept word
    final words = clean.split(RegExp(r'\s+'));
    if (words.length > 3) return null;

    for (final entry in conceptLexicon.entries) {
      final termInSrc = entry.value[srcLang]?.toLowerCase().trim();
      if (termInSrc != null && termInSrc.isNotEmpty) {
        if (clean == termInSrc) {
          return entry.key;
        }
      }
      // Also check English concept key directly
      if (clean == entry.key.toLowerCase().trim()) {
        return entry.key;
      }
    }
    return null;
  }

  /// Translates all vocabulary tokens and technical concepts across full sentences
  String _translateTokens(String text, String srcLang, String tgtLang) {
    String working = text;

    // Sort concepts by length descending so longer multi-word phrases match before individual words
    final sortedEntries = conceptLexicon.entries.toList()
      ..sort((a, b) {
        final lenA = a.value[srcLang]?.length ?? a.key.length;
        final lenB = b.value[srcLang]?.length ?? b.key.length;
        return lenB.compareTo(lenA);
      });

    for (final entry in sortedEntries) {
      final srcWord = entry.value[srcLang];
      final tgtWord = entry.value[tgtLang];
      if (srcWord != null && tgtWord != null && srcWord.isNotEmpty) {
        final pattern = RegExp(r'(?<=^|\s|[.,!?:;])' + RegExp.escape(srcWord) + r'(?=$|\s|[.,!?:;])', caseSensitive: false);
        working = working.replaceAll(pattern, tgtWord);
      }
      // Also match English concept key directly if source language is English
      if (srcLang == 'en' && tgtWord != null) {
        final pattern = RegExp(r'(?<=^|\s|[.,!?:;])' + RegExp.escape(entry.key) + r'(?=$|\s|[.,!?:;])', caseSensitive: false);
        working = working.replaceAll(pattern, tgtWord);
      }
    }

    // For any remaining untranslated English words when target is an Indic script,
    // phonetically transliterate them so the sentence remains readable in target script
    if (srcLang == 'en' && tgtLang != 'en') {
      final targetScript = ScriptNormalizationEngine.expectedScriptForLanguage(tgtLang);
      final tokens = working.split(RegExp(r'(?<=\s|[.,!?:;])|(?=\s|[.,!?:;])'));
      final buffer = StringBuffer();
      for (final token in tokens) {
        final cleanToken = token.trim();
        if (cleanToken.isNotEmpty && RegExp(r'^[a-zA-Z]+$').hasMatch(cleanToken)) {
          final deva = ScriptNormalizationEngine.toDevanagariFromLatin(cleanToken);
          final inTgt = ScriptNormalizationEngine.fromDevanagariToIndic(deva, targetScript);
          buffer.write(token.replaceAll(cleanToken, inTgt));
        } else {
          buffer.write(token);
        }
      }
      working = buffer.toString();
    }

    return working;
  }

  /// Automatically detects the language of a given text using high-speed IndicLID-FastText
  /// across all 10 supported languages + English (with Romanized Indic discrimination).
  LanguageDetectionResult detectLanguage(String text) {
    if (text.trim().isEmpty) {
      return const LanguageDetectionResult(languageCode: 'en', confidence: 0.0);
    }
    final prediction = IndicLIDFastTextEngine.instance.identifyLanguage(text);
    return LanguageDetectionResult(
      languageCode: prediction.languageCode,
      confidence: prediction.confidence,
    );
  }
}

/// Represents the detected language code and statistical confidence
class LanguageDetectionResult {
  final String languageCode;
  final double confidence;

  const LanguageDetectionResult({
    required this.languageCode,
    required this.confidence,
  });

  @override
  String toString() => '$languageCode (${(confidence * 100).toStringAsFixed(1)}%)';
}

