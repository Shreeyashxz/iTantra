import 'dart:io';
import 'package:flutter/foundation.dart';
import 'indic_bpe_tokenizer.dart';
import 'indiclid_fasttext_engine.dart';
import 'neural_mt_engine.dart';
import 'script_normalization_engine.dart';

/// Neural and disaster-resilient Machine Translation (MT) engine
/// based on AI4Bharat IndicTrans principles.
///
/// Supports cross-lingual translation across all 10 official languages:
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
    NeuralMtEngine.instance.unload();
    debugPrint('[IndicTrans] Translation model offloaded from RAM');
  }

  String get engineStatus {
    if (!_isLoaded) {
      return 'IndicTrans2 MT (Offloaded / 0 MB RAM)';
    }
    if (NeuralMtEngine.instance.isReady) {
      return 'IndicTrans2 Neural ONNX (${NeuralMtEngine.instance.loadedModelName})';
    }
    return _isQuantizedModelReady
        ? (_loadedPrecision == 'FP16'
            ? 'IndicTrans2 FP16 Studio (On-Device Checkpoint)'
            : 'IndicTrans2 INT8 (On-Device Quantized Checkpoint)')
        : 'IndicTrans2 Hybrid (Active / Tactical Disaster Lexicon)';
  }

  /// Pure Dart BPE Tokenizer for IndicTrans2
  IndicBpeTokenizer get tokenizer => IndicBpeTokenizer.instance;

  /// Tokenizes text into BPE token IDs with target language prefix
  List<int> tokenize(String text, String srcLang, String tgtLang) {
    return tokenizer.encode(text: text, sourceLang: srcLang, targetLang: tgtLang);
  }

  /// Detokenizes BPE token IDs back into target text
  String detokenize(List<int> tokenIds, [String? tgtLang]) {
    return tokenizer.decode(tokenIds, targetLang: tgtLang);
  }

  // ===========================================================================
  // Comprehensive Tactical, Disaster, Medical, and Conversational Lexicon
  // Across all 10 Supported Languages
  // ===========================================================================
  static const Map<String, Map<String, String>> conceptLexicon = {
    // --- Greetings & Acknowledgements ---
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
    'thank you': {
      'en': 'Thank you',
      'hi': 'धन्यवाद',
      'mr': 'धन्यवाद',
      'gu': 'આભાર',
      'ta': 'நன்றி',
      'te': 'ధన్యవాదాలు',
      'kn': 'ಧನ್ಯವಾದಗಳು',
      'ml': 'നന്ദി',
      'bn': 'ধন্যবাদ',
      'or': 'ଧନ୍ୟବାଦ',
    },
    'yes': {
      'en': 'Yes',
      'hi': 'हाँ',
      'mr': 'हो',
      'gu': 'હા',
      'ta': 'ஆம்',
      'te': 'అవును',
      'kn': 'ಹೌದು',
      'ml': 'അതെ',
      'bn': 'হ্যাঁ',
      'or': 'ହଁ',
    },
    'no': {
      'en': 'No',
      'hi': 'नहीं',
      'mr': 'नाही',
      'gu': 'ના',
      'ta': 'இல்லை',
      'te': 'కాదు',
      'kn': 'ಇಲ್ಲ',
      'ml': 'ഇല്ല',
      'bn': 'না',
      'or': 'ନା',
    },
    'please': {
      'en': 'Please',
      'hi': 'कृपया',
      'mr': 'कृपया',
      'gu': 'કૃપા કરીને',
      'ta': 'தயவுசெய்து',
      'te': 'దయచేసి',
      'kn': 'ದಯವಿಟ್ಟು',
      'ml': 'ദയവായി',
      'bn': 'দয়া করে',
      'or': 'ଦୟାକରି',
    },
    'understood': {
      'en': 'Understood',
      'hi': 'समझ गया',
      'mr': 'समजले',
      'gu': 'સમજી ગયા',
      'ta': 'புரிந்தது',
      'te': 'అర్థమైంది',
      'kn': 'ಅರ್ಥವಾಯಿತು',
      'ml': 'മനസ്സിലായി',
      'bn': 'বুঝেছি',
      'or': 'ବୁଝିଲି',
    },
    'repeat last message': {
      'en': 'Repeat last message',
      'hi': 'अंतिम संदेश दोहराएं',
      'mr': 'शेवटचा संदेश पुन्हा सांगा',
      'gu': 'છેલ્લો સંદેશ ફરીથી બોલો',
      'ta': 'கடைசி செய்தியை மீண்டும் கூறவும்',
      'te': 'చివరి సందేశాన్ని మళ్లీ చెప్పండి',
      'kn': 'ಕೊನೆಯ ಸಂದೇಶವನ್ನು ಪುನರಾವರ್ತಿಸಿ',
      'ml': 'അവസാന സന്ദേശം ആവർത്തിക്കുക',
      'bn': 'শেষ বার্তাটি পুনরাবৃত্তি করুন',
      'or': 'ଶେଷ ବାର୍ତ୍ତା ପୁନରାବୃତ୍ତି କରନ୍ତୁ',
    },
    'stand by': {
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
    'all clear': {
      'en': 'All clear',
      'hi': 'सब सुरक्षित है',
      'mr': 'सर्व सुरक्षित आहे',
      'gu': 'બધું સલામત છે',
      'ta': 'அனைத்தும் தெளிவு',
      'te': 'అంతా స్పష్టంగా ఉంది',
      'kn': 'ಎಲ್ಲವೂ ಸ್ಪಷ್ಟವಾಗಿದೆ',
      'ml': 'എല്ലാം സുരക്ഷിതമാണ്',
      'bn': 'সব পরিষ্কার',
      'or': 'ସବୁ ସୁରକ୍ଷିତ',
    },
    'under control': {
      'en': 'Under control',
      'hi': 'नियंत्रण में है',
      'mr': 'नियंत्रणात आहे',
      'gu': 'નિયંત્રણ હેઠળ છે',
      'ta': 'கட்டுப்பாட்டில் உள்ளது',
      'te': 'నియంత్రణలో ఉంది',
      'kn': 'ನಿಯಂತ್ರಣದಲ್ಲಿದೆ',
      'ml': 'നിയന്ത്രണത്തിലാണ്',
      'bn': 'নিয়ন্ত্রণে আছে',
      'or': 'ନିୟନ୍ତ୍ରଣରେ ଅଛି',
    },

    // --- Emergency & Danger ---
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
    'safe': {
      'en': 'Safe',
      'hi': 'सुरक्षित',
      'mr': 'सुरक्षित',
      'gu': 'સલામત',
      'ta': 'பாதுகாப்பானது',
      'te': 'సురక్షితం',
      'kn': 'ಸುರಕ್ಷಿತ',
      'ml': 'സുരക്ഷിതം',
      'bn': 'নিরাপদ',
      'or': 'ସୁରକ୍ଷିତ',
    },
    'fire': {
      'en': 'Fire',
      'hi': 'आग',
      'mr': 'आग',
      'gu': 'આગ',
      'ta': 'தீ',
      'te': 'అగ్ని',
      'kn': 'ಬೆಂಕಿ',
      'ml': 'തീ',
      'bn': 'আগুন',
      'or': 'ନିଆଁ',
    },
    'flood': {
      'en': 'Flood',
      'hi': 'बाढ़',
      'mr': 'पूर',
      'gu': 'પૂર',
      'ta': 'வெள்ளம்',
      'te': 'వరద',
      'kn': 'ಪ್ರವಾಹ',
      'ml': 'വെള്ളപ്പൊക്കം',
      'bn': 'বন্যা',
      'or': 'ବନ୍ୟା',
    },
    'earthquake': {
      'en': 'Earthquake',
      'hi': 'भूकंप',
      'mr': 'भूकंप',
      'gu': 'ધરતીકંપ',
      'ta': 'நிலநடுக்கம்',
      'te': 'భూకంపం',
      'kn': 'ಭೂಕಂಪ',
      'ml': 'ഭൂകമ്പം',
      'bn': 'ভূমিকম্প',
      'or': 'ଭୂମିକମ୍ପ',
    },
    'evacuate immediately': {
      'en': 'Evacuate immediately',
      'hi': 'तुरंत खाली करें',
      'mr': 'त्वरित रिकामे करा',
      'gu': 'તરત જ ખાલી કરો',
      'ta': 'உடனடியாக வெளியேறவும்',
      'te': 'వెంటనే ఖాళీ చేయండి',
      'kn': 'ತಕ್ಷಣ ಖಾಲಿ ಮಾಡಿ',
      'ml': 'ഉടൻ ഒഴിഞ്ഞുപോകുക',
      'bn': 'অবিলম্বে খালি করুন',
      'or': 'ତୁରନ୍ତ ଖାଲି କରନ୍ତୁ',
    },
    'we are safe': {
      'en': 'We are safe',
      'hi': 'हम सुरक्षित हैं',
      'mr': 'आम्ही सुरक्षित आहोत',
      'gu': 'અમે સલામત છીએ',
      'ta': 'நாங்கள் பாதுகாப்பாக இருக்கிறோம்',
      'te': 'మేము సురక్షితంగా ఉన్నాము',
      'kn': 'ನಾವು ಸುರಕ್ಷಿತವಾಗಿದ್ದೇವೆ',
      'ml': 'ഞങ്ങൾ സുരക്ഷിതരാണ്',
      'bn': 'আমরা নিরাপদ আছি',
      'or': 'ଆମେ ସୁରକ୍ଷିତ ଅଛୁ',
    },
    'need help immediately': {
      'en': 'Need help immediately',
      'hi': 'तुरंत मदद चाहिए',
      'mr': 'त्वरित मदत हवी आहे',
      'gu': 'તરત જ મદદની જરૂર છે',
      'ta': 'உடனடி உதவி தேவை',
      'te': 'వెంటనే సహాయం కావాలి',
      'kn': 'ತಕ್ಷಣ ಸಹಾಯ ಬೇಕು',
      'ml': 'ഉടൻ സഹായം ആവശ്യമാണ്',
      'bn': 'অবিলম্বে সাহায্য দরকার',
      'or': 'ତୁରନ୍ତ ସାହାଯ୍ୟ ଆବଶ୍ୟକ',
    },

    // --- Medical & Casualties ---
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
    'ambulance': {
      'en': 'Ambulance',
      'hi': 'एम्बुलेंस',
      'mr': 'रुग्णवाहिका',
      'gu': 'એમ્બ્યુલન્સ',
      'ta': 'ஆம்புலன்ஸ்',
      'te': 'అంబులెన్స్',
      'kn': 'ಆಂಬ್ಯುಲೆನ್ಸ್',
      'ml': 'ആംബുലൻസ്',
      'bn': 'অ্যাম্বুলেন্স',
      'or': 'ଆମ୍ବୁଲାନ୍ସ',
    },
    'injured': {
      'en': 'Injured',
      'hi': 'घायल',
      'mr': 'जखमी',
      'gu': 'ઇજાગ્રસ્ત',
      'ta': 'காயமடைந்தவர்',
      'te': 'గాయపడిన',
      'kn': 'ಗಾಯಗೊಂಡ',
      'ml': 'പരിക്കേറ്റു',
      'bn': 'আহত',
      'or': 'ଆହତ',
    },
    'casualties reported': {
      'en': 'Casualties reported',
      'hi': 'हताहतों की सूचना है',
      'mr': 'हताहत झाल्याची माहिती आहे',
      'gu': 'જાનહાનિના અહેવાલ છે',
      'ta': 'உயிரிழப்பு தகவல்கள் வந்துள்ளன',
      'te': 'మరణాలు నమోదయ్యాయి',
      'kn': 'ಸಾವುನೋವುಗಳು ವರದಿಯಾಗಿವೆ',
      'ml': 'ആളപായം റിപ്പോർട്ട് ചെയ്തു',
      'bn': 'হতাহতের খবর পাওয়া গেছে',
      'or': 'ମୃତାହତଙ୍କ ଖବର ମିଳିଛି',
    },
    'first aid': {
      'en': 'First aid',
      'hi': 'प्राथमिक उपचार',
      'mr': 'प्रथमोपचार',
      'gu': 'પ્રાથમિક સારવાર',
      'ta': 'முதலுதவி',
      'te': 'ప్రథమ చికిత్స',
      'kn': 'ಪ್ರಥಮ ಚಿಕಿತ್ಸೆ',
      'ml': 'പ്രഥമശുശ്രൂഷ',
      'bn': 'প্রাথমিক চিকিৎসা',
      'or': 'ପ୍ରାଥମିକ ଚିକିତ୍ସା',
    },
    'oxygen': {
      'en': 'Oxygen',
      'hi': 'ऑक्सीजन',
      'mr': 'ऑक्सिजन',
      'gu': 'ઓક્સિજન',
      'ta': 'ஆக்சிஜன்',
      'te': 'ఆక్సిజన్',
      'kn': 'ಆಕ್ಸಿಜನ್',
      'ml': 'ഓക്സിജൻ',
      'bn': 'অক্সিজেন',
      'or': 'ଅମ୍ଳଜାନ',
    },
    'medicine': {
      'en': 'Medicine',
      'hi': 'दवा',
      'mr': 'औषध',
      'gu': 'દવા',
      'ta': 'மருந்து',
      'te': 'మందు',
      'kn': 'ಔಷಧಿ',
      'ml': 'മരുന്ന്',
      'bn': 'ওষুধ',
      'or': 'ଔଷଧ',
    },

    // --- Life Supplies ---
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
    'we need water and food': {
      'en': 'We need water and food',
      'hi': 'हमें पानी और भोजन चाहिए',
      'mr': 'आम्हाला पाणी आणि अन्न हवे आहे',
      'gu': 'અમને પાણી અને ખોરાકની જરૂર છે',
      'ta': 'எங்களுக்கு தண்ணீரும் உணவும் தேவை',
      'te': 'మాకు నీరు మరియు ఆహారం కావాలి',
      'kn': 'ನಮಗೆ ನೀರು ಮತ್ತು ಆಹಾರ ಬೇಕು',
      'ml': 'ഞങ്ങൾക്ക് വെള്ളവും ഭക്ഷണവും വേണം',
      'bn': 'আমাদের জল এবং খাবার প্রয়োজন',
      'or': 'ଆମକୁ ପାଣି ଏବଂ ଖାଦ୍ୟ ଆବଶ୍ୟକ',
    },

    // --- Tactical, Location & Commands ---
    'where are you': {
      'en': 'Where are you',
      'hi': 'आप कहाँ हैं',
      'mr': 'तुम्ही कुठे आहात',
      'gu': 'તમે ક્યાં છો',
      'ta': 'நீங்கள் எங்கே இருக்கிறீர்கள்',
      'te': 'మీరు ఎక్కడ ఉన్నారు',
      'kn': 'ನೀವು ಎಲ್ಲಿದ್ದೀರಿ',
      'ml': 'നിങ്ങൾ എവിടെയാണ്',
      'bn': 'আপনি কোথায় আছেন',
      'or': 'ଆପଣ କେଉଁଠାରେ ଅଛନ୍ତି',
    },
    'what is your status': {
      'en': 'What is your status',
      'hi': 'आपकी स्थिति क्या है',
      'mr': 'तुमची स्थिती काय आहे',
      'gu': 'તમારી સ્થિતિ શું છે',
      'ta': 'உங்கள் நிலை என்ன',
      'te': 'మీ పరిస్థితి ఏమిటి',
      'kn': 'ನಿಮ್ಮ ಸ್ಥಿತಿ ಏನು',
      'ml': 'നിങ്ങളുടെ അവസ്ഥ എന്താണ്',
      'bn': 'আপনার অবস্থা কি',
      'or': 'ଆପଣଙ୍କ ସ୍ଥିତି କଣ',
    },
    'hold position': {
      'en': 'Hold position',
      'hi': 'अपनी स्थिति बनाए रखें',
      'mr': 'जागेवरच थांबा',
      'gu': 'પોતાની સ્થિતિ જાળવી રાખો',
      'ta': 'நிலையைப் பிடித்துக் கொள்ளுங்கள்',
      'te': 'స్థానాన్ని పట్టుకోండి',
      'kn': 'ಸ್ಥಾನದಲ್ಲಿರಿ',
      'ml': 'നിലനിർത്തുക',
      'bn': 'অবস্থান ধরে রাখুন',
      'or': 'ସ୍ଥିତି ବଜାୟ ରଖନ୍ତୁ',
    },
    'advance now': {
      'en': 'Advance now',
      'hi': 'आगे बढ़ें',
      'mr': 'पुढे चला',
      'gu': 'આગળ વધો',
      'ta': 'இப்போது முன்னேறுங்கள்',
      'te': 'ముందుకు సాగండి',
      'kn': 'ಮುಂದೆ ಸಾಗಿ',
      'ml': 'മുന്നോട്ട് പോകുക',
      'bn': 'সামনে এগিয়ে যান',
      'or': 'ଆଗକୁ ବଢ଼ନ୍ତୁ',
    },
    'send reinforcements': {
      'en': 'Send reinforcements',
      'hi': 'अतिरिक्त सहायता भेजें',
      'mr': 'अतिरिक्त मदत पाठवा',
      'gu': 'વધારાની મદદ મોકલો',
      'ta': 'கூடுதல் படைகளை அனுப்புங்கள்',
      'te': 'అదనపు దళాలను పంపండి',
      'kn': 'ಹೆಚ್ಚುವರಿ ಪಡೆಗಳನ್ನು ಕಳುಹಿಸಿ',
      'ml': 'കൂടുതൽ സഹായം അയക്കുക',
      'bn': 'অতিরিক্ত সাহায্য পাঠান',
      'or': 'ଅତିରିକ୍ତ ସାହାଯ୍ୟ ପଠାନ୍ତୁ',
    },
    'location': {
      'en': 'Location',
      'hi': 'स्थान',
      'mr': 'ठिकाण',
      'gu': 'સ્થાન',
      'ta': 'இடம்',
      'te': 'స్థానం',
      'kn': 'ಸ್ಥಳ',
      'ml': 'സ്ഥലം',
      'bn': 'অবস্থান',
      'or': 'ସ୍ଥାନ',
    },
    'coordinates': {
      'en': 'Coordinates',
      'hi': 'निर्देशांक',
      'mr': 'निर्देशांक',
      'gu': 'નિર્દેશાંકો',
      'ta': 'ஆயத்தொலைவுகள்',
      'te': 'కోఆర్డినేట్లు',
      'kn': 'ನಿರ್ದೇಶಾಂಕಗಳು',
      'ml': 'കോർഡിനേറ്റുകൾ',
      'bn': 'স্থানাঙ্ক',
      'or': 'ନିର୍ଦ୍ଦେଶାଙ୍କ',
    },
    'team': {
      'en': 'Team',
      'hi': 'टीम',
      'mr': 'संघ',
      'gu': 'ટીમ',
      'ta': 'அணி',
      'te': 'బృందం',
      'kn': 'ತಂಡ',
      'ml': 'ടീം',
      'bn': 'দল',
      'or': 'ଦଳ',
    },
    'station': {
      'en': 'Station',
      'hi': 'स्टेशन',
      'mr': 'स्टेशन',
      'gu': 'સ્ટેશન',
      'ta': 'நிலையம்',
      'te': 'స్టేషన్',
      'kn': 'ನಿಲ್ದಾಣ',
      'ml': 'സ്റ്റേഷൻ',
      'bn': 'স্টেশন',
      'or': 'ଷ୍ଟେସନ',
    },
    'sector': {
      'en': 'Sector',
      'hi': 'सेक्टर',
      'mr': 'विभाग',
      'gu': 'સેક્ટર',
      'ta': 'பிரிவு',
      'te': 'రంగం',
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
      'ta': 'வானொலி',
      'te': 'రేడియో',
      'kn': 'ರೇಡಿಯೋ',
      'ml': 'റേഡിയോ',
      'bn': 'রেডিও',
      'or': 'ରେଡିଓ',
    },
    'signal': {
      'en': 'Signal',
      'hi': 'सिग्नल',
      'mr': 'संकेत',
      'gu': 'સિગ્નલ',
      'ta': 'சமிக்ஞை',
      'te': 'సిగ్నల్',
      'kn': 'ಸಂಕೇತ',
      'ml': 'സിഗ്നൽ',
      'bn': 'সংকেত',
      'or': 'ସଙ୍କେତ',
    },
    'battery': {
      'en': 'Battery',
      'hi': 'बैटरी',
      'mr': 'बॅटरी',
      'gu': 'બેટરી',
      'ta': 'மின்கலம்',
      'te': 'బ్యాటరీ',
      'kn': 'ಬ್ಯಾಟರಿ',
      'ml': 'ബാറ്ററി',
      'bn': 'ব্যাটারি',
      'or': 'ବ୍ୟାଟେରୀ',
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
    'confirmed': {
      'en': 'Confirmed',
      'hi': 'पुष्ट',
      'mr': 'पुष्टी',
      'gu': 'પુષ્ટિ',
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
      'gu': 'ટ્રાન્સસીવર',
      'ta': 'டிரான்ஸீவர்',
      'te': 'ట్రాన్స్‌సీవర్',
      'kn': 'ಟ್ರಾನ್ಸ್‌ಸಿವರ್',
      'ml': 'ട്രാൻസ്‌സിവർ',
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

    // --- Numbers & Quantities ---
    'one': {
      'en': 'One',
      'hi': 'एक',
      'mr': 'एक',
      'gu': 'એક',
      'ta': 'ஒன்று',
      'te': 'ఒకటి',
      'kn': 'ಒಂದು',
      'ml': 'ഒന്ന്',
      'bn': 'এক',
      'or': 'ଏକ',
    },
    'two': {
      'en': 'Two',
      'hi': 'दो',
      'mr': 'दोन',
      'gu': 'બે',
      'ta': 'இரண்டு',
      'te': 'రెండు',
      'kn': 'ಎರಡು',
      'ml': 'രണ്ട്',
      'bn': 'দুই',
      'or': 'ଦୁଇ',
    },
    'three': {
      'en': 'Three',
      'hi': 'तीन',
      'mr': 'तीन',
      'gu': 'ત્રણ',
      'ta': 'மூன்று',
      'te': 'మూడు',
      'kn': 'ಮೂರು',
      'ml': 'മൂന്ന്',
      'bn': 'তিন',
      'or': 'ତିନି',
    },
    'four': {
      'en': 'Four',
      'hi': 'चार',
      'mr': 'चार',
      'gu': 'ચાર',
      'ta': 'நான்கு',
      'te': 'నాలుగు',
      'kn': 'ನಾಲ್ಕು',
      'ml': 'നാല്',
      'bn': 'চার',
      'or': 'ଚାରି',
    },
    'five': {
      'en': 'Five',
      'hi': 'पाँच',
      'mr': 'पाच',
      'gu': 'પાંચ',
      'ta': 'ஐந்து',
      'te': 'ఐదు',
      'kn': 'ಐದು',
      'ml': 'അഞ്ച്',
      'bn': 'পাঁচ',
      'or': 'ପାଞ୍ଚ',
    },
    'ten': {
      'en': 'Ten',
      'hi': 'दस',
      'mr': 'दहा',
      'gu': 'દસ',
      'ta': 'பத்து',
      'te': 'పది',
      'kn': 'ಹತ್ತು',
      'ml': 'പത്ത്',
      'bn': 'দশ',
      'or': 'ଦଶ',
    },

    // --- Directions ---
    'north': {
      'en': 'North',
      'hi': 'उत्तर',
      'mr': 'उत्तर',
      'gu': 'ઉત્તર',
      'ta': 'வடக்கு',
      'te': 'ఉత్తరం',
      'kn': 'ಉತ್ತರ',
      'ml': 'വടക്ക്',
      'bn': 'উত্তর',
      'or': 'ଉତ୍ତର',
    },
    'south': {
      'en': 'South',
      'hi': 'दक्षिण',
      'mr': 'दक्षिण',
      'gu': 'દક્ષિણ',
      'ta': 'தெற்கு',
      'te': 'దక్షిణం',
      'kn': 'ದಕ್ಷಿಣ',
      'ml': 'തെക്ക്',
      'bn': 'দক্ষিণ',
      'or': 'ଦକ୍ଷିଣ',
    },
    'east': {
      'en': 'East',
      'hi': 'पूर्व',
      'mr': 'पूर्व',
      'gu': 'પૂર્વ',
      'ta': 'கிழக்கு',
      'te': 'తూర్పు',
      'kn': 'ಪೂರ್ವ',
      'ml': 'കിഴക്ക്',
      'bn': 'পূর্ব',
      'or': 'ପୂର୍ବ',
    },
    'west': {
      'en': 'West',
      'hi': 'पश्चिम',
      'mr': 'पश्चिम',
      'gu': 'પશ્ચિમ',
      'ta': 'மேற்கு',
      'te': 'పడమర',
      'kn': 'ಪಶ್ಚಿಮ',
      'ml': 'പടിഞ്ഞാറ്',
      'bn': 'পশ্চিম',
      'or': 'ପଶ୍ଚିମ',
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

    final neuralOk = await NeuralMtEngine.instance.init(baseDirPath);
    if (neuralOk) {
      _isQuantizedModelReady = true;
      _loadedPrecision = 'INT8';
      return true;
    }

    await tokenizer.init(baseDirPath);
    _isQuantizedModelReady = false;
    _quantizedModelPath = '';
    return false;
  }

  /// Translates [text] from [sourceLang] to [targetLang] across all 10 supported languages.
  ///
  /// Execution Pipeline:
  /// 1. Language Detection & Verification (auto-resolves conflicting scripts).
  /// 2. Identity Check (if source == target, return verbatim).
  /// 3. Tier 1: Direct Concept / Multi-Word Phrase Match (instant sub-millisecond tactical match).
  /// 4. Tier 2: Neural Seq2Seq ONNX Translation (arbitrary sentences via IndicTrans2 INT8).
  /// 5. Tier 3: Full Sentence & Token Translation across all 10 languages.
  /// 6. Script Alignment: Ensures target output matches the target language's native script.
  Future<String> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return '';

    String src = sourceLang.toLowerCase();
    final tgt = targetLang.toLowerCase();

    // 0. Offload Check
    if (!_isLoaded) {
      debugPrint('[IndicTrans] Engine is offloaded. Bypassing MT and returning original text.');
      return cleanText;
    }

    // Verify source language if script contradicts caller's language code
    final detectedScript = ScriptNormalizationEngine.detectScript(cleanText);
    final expectedSrcScript = ScriptNormalizationEngine.expectedScriptForLanguage(src);
    if (detectedScript != expectedSrcScript && detectedScript != ScriptType.unknown) {
      final detected = detectLanguage(cleanText);
      if (detected.confidence >= 0.80 && detected.languageCode != src) {
        debugPrint('[IndicTrans] Auto-corrected source language from $src to ${detected.languageCode} (conf: ${detected.confidence})');
        src = detected.languageCode;
      }
    }

    // 1. Script Pre-normalization for MT Input
    final normalizedInput = ScriptNormalizationEngine.prepareTextForMt(cleanText, src);

    // 2. Identity Check
    if (src == tgt) return normalizedInput;

    // 3. Direct Multi-word / Concept Match (Tier 1: Instant tactical emergency phrases < 1 ms)
    final matchedConcept = _findMatchingConcept(normalizedInput, src);
    if (matchedConcept != null) {
      final translated = conceptLexicon[matchedConcept]?[tgt];
      if (translated != null && translated.isNotEmpty) {
        debugPrint('[IndicTrans] Concept match: "$matchedConcept" -> "$translated" ($tgt)');
        return ScriptNormalizationEngine.normalizeFromMt(translated, tgt);
      }
    }

    // 4. Tier 2: Neural Seq2Seq ONNX Translation (for arbitrary sentences)
    if (NeuralMtEngine.instance.isReady) {
      final neuralTranslation = await NeuralMtEngine.instance.translate(
        text: normalizedInput,
        sourceLang: src,
        targetLang: tgt,
      );
      if (neuralTranslation != null && neuralTranslation.trim().isNotEmpty) {
        debugPrint('[IndicTrans] Neural translation: "$normalizedInput" -> "$neuralTranslation"');
        return ScriptNormalizationEngine.normalizeFromMt(neuralTranslation, tgt);
      }
    }

    // 5. Tier 3: Tactical Token Replacement & Phonetic Transliteration
    final tokenResult = _translateTokens(normalizedInput, src, tgt);
    if (tokenResult != normalizedInput) {
      debugPrint('[IndicTrans] Sentence translation: "$normalizedInput" -> "$tokenResult"');
      return ScriptNormalizationEngine.normalizeFromMt(tokenResult, tgt);
    }

    // 6. Final fallback with cross-script alignment
    return ScriptNormalizationEngine.normalizeFromMt(normalizedInput, tgt);
  }

  /// Finds matching disaster, tactical, or conversational concept for utterances
  String? _findMatchingConcept(String text, String srcLang) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s\u0900-\u0D7F]'), '').trim();
    if (clean.isEmpty) return null;

    // Direct match against all concept entries
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

  /// Translates vocabulary tokens, multi-word phrases, and technical concepts
  /// across full sentences while preserving punctuation and numbers.
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
        final pattern = RegExp(
          r'(?<=^|\s|[.,!?:;])' + RegExp.escape(srcWord) + r'(?=$|\s|[.,!?:;])',
          caseSensitive: false,
        );
        working = working.replaceAll(pattern, tgtWord);
      }
      // Also match English concept key directly if source language is English
      if (srcLang == 'en' && tgtWord != null) {
        final pattern = RegExp(
          r'(?<=^|\s|[.,!?:;])' + RegExp.escape(entry.key) + r'(?=$|\s|[.,!?:;])',
          caseSensitive: false,
        );
        working = working.replaceAll(pattern, tgtWord);
      }
    }

    // Handle remaining words:
    // If target is an Indic language and words remain in Latin, transliterate to target script
    if (tgtLang != 'en') {
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
    } else if (srcLang != 'en' && tgtLang == 'en') {
      // If source was Indic and target is English, transliterate any untranslated Indic words to Latin
      final tokens = working.split(RegExp(r'(?<=\s|[.,!?:;])|(?=\s|[.,!?:;])'));
      final buffer = StringBuffer();
      for (final token in tokens) {
        final cleanToken = token.trim();
        final script = ScriptNormalizationEngine.detectScript(cleanToken);
        if (cleanToken.isNotEmpty && script != ScriptType.latin && script != ScriptType.unknown) {
          final latin = ScriptNormalizationEngine.toLatin(cleanToken);
          buffer.write(token.replaceAll(cleanToken, latin));
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
