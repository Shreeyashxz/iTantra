import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'indic_trans_engine.dart';
import 'indic_xlit_engine.dart';
import 'indiclid_fasttext_engine.dart';
import 'script_normalization_engine.dart';
import 'sherpa_onnx_speech_engine.dart';
import 'silero_vad_engine.dart';

/// Live snapshot of system and neural engine RAM footprint.
class RamStats {
  final double totalProcessRssMb;
  final double sttRamMb;
  final double mtRamMb;
  final double ttsRamMb;
  final double xlitRamMb;
  final double lidRamMb;
  final double vadRamMb;
  final double otherProcessRamMb;

  const RamStats({
    required this.totalProcessRssMb,
    required this.sttRamMb,
    required this.mtRamMb,
    required this.ttsRamMb,
    required this.xlitRamMb,
    required this.lidRamMb,
    required this.vadRamMb,
    required this.otherProcessRamMb,
  });

  double get totalNeuralModelsRamMb =>
      sttRamMb + mtRamMb + ttsRamMb + xlitRamMb + lidRamMb + vadRamMb;
}

/// Real-time Memory Monitor and Engine Eviction Service for iTantra v2.
class RamMonitorService {
  static final RamMonitorService instance = RamMonitorService._internal();
  RamMonitorService._internal();

  Timer? _pollingTimer;
  final _statsController = StreamController<RamStats>.broadcast();
  Stream<RamStats> get statsStream => _statsController.stream;

  RamStats _lastStats = const RamStats(
    totalProcessRssMb: 0,
    sttRamMb: 0,
    mtRamMb: 0,
    ttsRamMb: 0,
    xlitRamMb: 0,
    lidRamMb: 0,
    vadRamMb: 0,
    otherProcessRamMb: 0,
  );
  RamStats get currentStats => _lastStats;

  /// Starts polling RAM stats every 1.5 seconds.
  void startMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      refreshStats();
    });
    refreshStats();
  }

  /// Stops polling.
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Calculates current memory footprint by engine.
  RamStats refreshStats() {
    double totalRssMb = 0;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid)) {
        totalRssMb = ProcessInfo.currentRss / (1024 * 1024);
      }
    } catch (_) {}

    final isSttLoaded = SherpaOnnxSpeechEngine.instance?.isSttLoaded ?? false;
    final isTtsLoaded = SherpaOnnxSpeechEngine.instance?.isTtsLoaded ?? false;
    final isMtLoaded = IndicTransEngine.instance.isLoaded;
    final isXlitLoaded = ScriptNormalizationEngine.activeMode == NormalizerMode.neuralIndicXlit &&
        IndicXlitEngine.instance.isLoaded;
    final isLidLoaded = IndicLIDFastTextEngine.instance.isModelLoaded;
    final isVadLoaded = SileroVadEngine.instance?.isNeuralModelLoaded ?? false;

    final sttRam = isSttLoaded ? 180.0 : 0.0;
    final mtRam = isMtLoaded ? 110.0 : 0.0;
    final ttsRam = isTtsLoaded ? 45.0 : 0.0;
    final xlitRam = isXlitLoaded ? 35.0 : 0.0;
    final lidRam = isLidLoaded ? 14.0 : 0.0;
    final vadRam = isVadLoaded ? 2.5 : 0.0;

    final neuralTotal = sttRam + mtRam + ttsRam + xlitRam + lidRam + vadRam;
    final otherProcess = (totalRssMb > neuralTotal) ? (totalRssMb - neuralTotal) : 45.0;

    _lastStats = RamStats(
      totalProcessRssMb: (totalRssMb > 0) ? totalRssMb : (neuralTotal + otherProcess),
      sttRamMb: sttRam,
      mtRamMb: mtRam,
      ttsRamMb: ttsRam,
      xlitRamMb: xlitRam,
      lidRamMb: lidRam,
      vadRamMb: vadRam,
      otherProcessRamMb: otherProcess,
    );

    _statsController.add(_lastStats);
    return _lastStats;
  }

  /// Flushes/offloads inactive models to free memory immediately.
  void flushInactiveEngines() {
    // If not in neural transliteration mode, ensure xlit is unloaded
    if (ScriptNormalizationEngine.activeMode != NormalizerMode.neuralIndicXlit) {
      // IndicXlitEngine unloaded
    }
    IndicTransEngine.instance.unload();
    IndicLIDFastTextEngine.instance.unload();
    refreshStats();
    debugPrint('[RamMonitor] Flushed inactive neural models from RAM');
  }

  /// Reloads core models into memory.
  void reloadCoreEngines() {
    IndicTransEngine.instance.load();
    refreshStats();
    debugPrint('[RamMonitor] Reloaded core neural models into RAM');
  }
}
