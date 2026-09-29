/// Pipeline composition model: force on/off state, RAM estimates, bad-combo warnings.
/// Pure Dart (no Flutter) so it can be unit-tested.
enum PipelineSeverity { error, warning, info }

class PipelineWarning {
  final PipelineSeverity severity;
  final String stageId;
  final String message;
  const PipelineWarning(this.severity, this.stageId, this.message);
}

class PipelineSnapshot {
  final bool sttLoaded;
  final String sttPrecision; // INT8 / FP32
  final bool ttsLoaded;
  final String ttsEngine; // AI4BHARAT_RASA / META_MMS / OS_NATIVE
  final bool mtNeuralReady;
  final bool mtEnabled;
  final bool xlitNeuralReady;
  final String normalizerMode; // ADVANCED / LEGACY_RULE_BASED / NEURAL_INDIC_XLIT
  final bool lidReady;
  final bool vadNeural;
  final bool autoPlayAudio;
  final String selectedLang;

  const PipelineSnapshot({
    this.sttLoaded = false,
    this.sttPrecision = 'INT8',
    this.ttsLoaded = false,
    this.ttsEngine = 'AI4BHARAT_RASA',
    this.mtNeuralReady = false,
    this.mtEnabled = true,
    this.xlitNeuralReady = false,
    this.normalizerMode = 'ADVANCED',
    this.lidReady = false,
    this.vadNeural = false,
    this.autoPlayAudio = true,
    this.selectedLang = 'hi',
  });
}

class PipelineRamSlice {
  final String stageId;
  final String label;
  final double mb;
  final bool active;
  const PipelineRamSlice(this.stageId, this.label, this.mb, this.active);
}

/// Estimated resident RAM per stage (file size + ORT session overhead).
/// Labelled estimates — Android doesn't expose per-model RSS to Dart.
class PipelineModel {
  static const double baseAppMb = 45;
  static const double sttInt8Mb = 220;
  static const double sttFp32Mb = 450;
  static const double ttsRasaMb = 180;
  static const double ttsMmsMb = 60;
  static const double mtNeuralMb = 300;
  static const double xlitNeuralMb = 120;
  // LID weights are 261MB on disk — resident cost when loaded.
  static const double lidMb = 300;
  static const double vadNeuralMb = 15;

  static List<PipelineRamSlice> ramSlices(PipelineSnapshot s) {
    return [
      const PipelineRamSlice('base', 'App base', baseAppMb, true),
      PipelineRamSlice(
        'stt',
        'STT ${s.sttPrecision}',
        s.sttPrecision == 'FP32' ? sttFp32Mb : sttInt8Mb,
        s.sttLoaded,
      ),
      PipelineRamSlice(
        'tts',
        'TTS ${s.ttsEngine == 'AI4BHARAT_RASA' ? 'Rasa' : s.ttsEngine == 'META_MMS' ? 'MMS' : 'OS'}',
        s.ttsEngine == 'AI4BHARAT_RASA'
            ? ttsRasaMb
            : s.ttsEngine == 'META_MMS'
                ? ttsMmsMb
                : 0,
        s.ttsLoaded,
      ),
      PipelineRamSlice('mt', 'MT neural', mtNeuralMb, s.mtNeuralReady && s.mtEnabled),
      PipelineRamSlice(
        'xlit',
        'Xlit ${s.normalizerMode == 'NEURAL_INDIC_XLIT' ? 'neural' : 'rules'}',
        xlitNeuralMb,
        s.xlitNeuralReady && s.normalizerMode == 'NEURAL_INDIC_XLIT',
      ),
      PipelineRamSlice('lid', 'LID', lidMb, s.lidReady),
      PipelineRamSlice('vad', 'VAD neural', vadNeuralMb, s.vadNeural),
    ];
  }

  static double totalRamMb(PipelineSnapshot s) =>
      ramSlices(s).where((e) => e.active).fold(0.0, (a, b) => a + b.mb);

  /// Bad-composition warnings. Errors block voice, warnings degrade, infos explain fallback.
  static List<PipelineWarning> validate(PipelineSnapshot s) {
    final out = <PipelineWarning>[];

    if (!s.sttLoaded) {
      out.add(const PipelineWarning(
        PipelineSeverity.error,
        'stt',
        'STT is OFF — PTT and hands-free capture are dead. Force-load STT or download the pack.',
      ));
    }
    if (!s.ttsLoaded && s.autoPlayAudio) {
      out.add(const PipelineWarning(
        PipelineSeverity.warning,
        'tts',
        'Auto-play is ON but no TTS voice is loaded — inbound audio will be silent. Load Rasa/MMS or switch to OS native.',
      ));
    }
    if (!s.ttsLoaded && !s.autoPlayAudio) {
      out.add(const PipelineWarning(
        PipelineSeverity.info,
        'tts',
        'TTS is OFF and auto-play is OFF — text-only walkie-talkie. Lowest RAM.',
      ));
    }
    if (s.mtEnabled && !s.mtNeuralReady) {
      out.add(const PipelineWarning(
        PipelineSeverity.info,
        'mt',
        'Neural MT is OFF — cross-language uses instant tactical lexicon (<1ms). Full-sentence neural needs the MT bundle.',
      ));
    }
    if (!s.mtEnabled) {
      out.add(const PipelineWarning(
        PipelineSeverity.warning,
        'mt',
        'Translation is force-disabled — peers in other languages will hear your raw language.',
      ));
    }
    if (s.normalizerMode == 'NEURAL_INDIC_XLIT' && !s.xlitNeuralReady) {
      out.add(const PipelineWarning(
        PipelineSeverity.warning,
        'xlit',
        'Xlit toggle is ON but neural weights are missing — rule-based Aksharantar fallback is active (offline, works). Download ~35MB for true neural.',
      ));
    }
    if (s.normalizerMode == 'LEGACY_RULE_BASED') {
      out.add(const PipelineWarning(
        PipelineSeverity.info,
        'xlit',
        'Legacy ISCII-offset normalizer — fast but lossy for Tamil/Malayalam conjuncts. Prefer ADVANCED.',
      ));
    }
    if (s.ttsEngine == 'AI4BHARAT_RASA' && const {'gu', 'or', 'en'}.contains(s.selectedLang.toLowerCase())) {
      out.add(PipelineWarning(
        PipelineSeverity.warning,
        'tts',
        'Rasa-13 has no ${s.selectedLang} voice — engine auto-falls-back to MMS. Switch TTS to MMS to silence this.',
      ));
    }
    if (!s.vadNeural) {
      out.add(const PipelineWarning(
        PipelineSeverity.info,
        'vad',
        'Neural VAD is OFF — adaptive RMS fallback is active. Fine indoors, weaker in wind/crowd noise.',
      ));
    }
    if (!s.lidReady) {
      out.add(const PipelineWarning(
        PipelineSeverity.info,
        'lid',
        'Language-ID is OFF — auto-correction of wrong language tags is disabled. Manual language select is used.',
      ));
    }
    final total = totalRamMb(s);
    if (total > 800) {
      out.add(PipelineWarning(
        PipelineSeverity.warning,
        'ram',
        'Estimated ${total.round()}MB resident — high for 2-3GB field phones. Consider FP32→INT8 or unloading MT/Xlit neural.',
      ));
    }
    return out;
  }
}
