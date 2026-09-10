import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'vad_engine.dart';

/// Hybrid Neural & Adaptive Voice Activity Detection Engine.
/// Primary: Official Silero VAD ONNX model via sherpa_onnx (models/silero_vad.onnx).
/// Fallback: Pure Dart floating-point RMS energy computation with dynamic sensitivity gating.
class SileroVadEngine implements VadEngine {
  double sensitivity; // 0.1 (least sensitive) to 1.0 (most sensitive)
  final double minSilenceDuration;
  final double minSpeechDuration;
  final int sampleRate;

  // Neural Silero VAD state
  sherpa.VoiceActivityDetector? _sherpaVad;
  bool _isNeuralInitialized = false;
  bool get isNeuralActive => _isNeuralInitialized && _sherpaVad != null;

  bool _isSpeechActive = false;
  int _consecutiveSilenceFrames = 0;
  int _consecutiveSpeechFrames = 0;
  StreamSubscription<Int16List>? _subscription;
  final _speechStateController = StreamController<bool>.broadcast();

  // Running noise floor estimator (fallback)
  double _noiseFloorRms = 0.008;
  static const double _noiseFloorAlpha = 0.03;

  // Pre-speech lookback buffer (~200ms lookback at 16kHz to prevent first-syllable clipping)
  final Queue<Int16List> _ringBuffer = Queue<Int16List>();
  static const int _maxRingBufferChunks = 5;

  SileroVadEngine({
    this.sensitivity = 0.6,
    this.minSilenceDuration = 0.4,
    this.minSpeechDuration = 0.15,
    this.sampleRate = 16000,
  }) {
    _initNeuralVad();
  }

  /// Extracts bundled silero_vad.onnx from assets to device storage and initializes sherpa.VoiceActivityDetector
  Future<void> _initNeuralVad() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final modelDir = Directory(p.join(baseDir.path, 'models'));
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final modelFile = File(p.join(modelDir.path, 'silero_vad.onnx'));
      if (!await modelFile.exists() || await modelFile.length() < 1024) {
        debugPrint('[SileroVAD] Extracting bundled silero_vad.onnx from assets...');
        final byteData = await rootBundle.load('assets/models/silero_vad.onnx');
        await modelFile.writeAsBytes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true,
        );
      }

      if (await modelFile.exists()) {
        if (Platform.isWindows) {
          try {
            final exeDir = File(Platform.resolvedExecutable).parent.path;
            final ortPath = p.join(exeDir, 'onnxruntime.dll');
            if (File(ortPath).existsSync()) {
              DynamicLibrary.open(ortPath);
            }
          } catch (_) {}
        }

        final config = sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: modelFile.path,
            threshold: (0.5 * (2.0 - sensitivity)).clamp(0.2, 0.8),
            minSilenceDuration: minSilenceDuration,
            minSpeechDuration: minSpeechDuration,
            windowSize: 512,
            maxSpeechDuration: 30.0,
          ),
          sampleRate: sampleRate,
          numThreads: 1,
          provider: 'cpu',
          debug: false,
        );

        _sherpaVad = sherpa.VoiceActivityDetector(
          config: config,
          bufferSizeInSeconds: 10.0,
        );
        _isNeuralInitialized = true;
        debugPrint('[SileroVAD] Neural ONNX model loaded successfully (${modelFile.path})');
      }
    } catch (e) {
      debugPrint('[SileroVAD] Neural VAD init notice (will use adaptive RMS fallback): $e');
      _sherpaVad = null;
      _isNeuralInitialized = false;
    }
  }

  void setSensitivity(double value) {
    sensitivity = value.clamp(0.1, 1.0);
  }

  @override
  List<Int16List> get lookbackBuffer => _ringBuffer.toList();

  @override
  Stream<bool> startVad(Stream<Int16List> audioData) {
    _subscription?.cancel();
    _subscription = audioData.listen((chunk) {
      final isSpeech = _detectVoiceActivity(chunk);
      if (isSpeech != _isSpeechActive) {
        _isSpeechActive = isSpeech;
        _speechStateController.add(_isSpeechActive);
      }
    });
    return _speechStateController.stream;
  }

  bool _detectVoiceActivity(Int16List samples) {
    if (samples.isEmpty) return false;

    // Maintain lookback ring buffer
    _ringBuffer.addLast(samples);
    if (_ringBuffer.length > _maxRingBufferChunks) {
      _ringBuffer.removeFirst();
    }

    // 1. Primary: Neural Silero VAD execution
    if (_sherpaVad != null) {
      try {
        final floatSamples = Float32List(samples.length);
        for (int i = 0; i < samples.length; i++) {
          floatSamples[i] = samples[i] / 32768.0;
        }

        _sherpaVad!.acceptWaveform(floatSamples);
        return _sherpaVad!.isDetected();
      } catch (e) {
        debugPrint('[SileroVAD] Neural detection error, falling back to RMS: $e');
      }
    }

    // 2. Fallback: Adaptive RMS Energy Gating
    double sum = 0;
    for (int i = 0; i < samples.length; i++) {
      final normalized = samples[i] / 32768.0;
      sum += normalized * normalized;
    }
    final rms = sqrt(sum / samples.length);

    if (!_isSpeechActive && rms < 0.04) {
      _noiseFloorRms = (_noiseFloorAlpha * rms) + ((1.0 - _noiseFloorAlpha) * _noiseFloorRms);
    }

    final sensitivityMultiplier = 1.6 + ((1.0 - sensitivity) * 3.2);
    final staticCutoff = 0.005 + ((1.0 - sensitivity) * 0.030);
    final adaptiveCutoff = max(staticCutoff * 0.75, _noiseFloorRms * sensitivityMultiplier);

    final isVoiceFrame = rms > adaptiveCutoff;
    final frameDurationMs = (samples.length / sampleRate) * 1000;
    final minSpeechFrames = (minSpeechDuration * 1000) / frameDurationMs;
    final minSilenceFrames = (minSilenceDuration * 1000) / frameDurationMs;

    if (isVoiceFrame) {
      _consecutiveSpeechFrames++;
      _consecutiveSilenceFrames = 0;
      if (_consecutiveSpeechFrames >= minSpeechFrames) {
        return true;
      }
    } else {
      _consecutiveSilenceFrames++;
      _consecutiveSpeechFrames = 0;
      if (_consecutiveSilenceFrames >= minSilenceFrames) {
        return false;
      }
    }

    return _isSpeechActive;
  }

  /// Explicitly re-initializes neural Silero VAD into memory
  Future<bool> initNeuralVad() async {
    if (_sherpaVad != null && _isNeuralInitialized) return true;
    await _initNeuralVad();
    return isNeuralActive;
  }

  /// Offloads neural Silero VAD from RAM to reclaim memory
  void unloadNeuralVad() {
    try {
      _sherpaVad?.free();
      _sherpaVad = null;
    } catch (_) {}
    _isNeuralInitialized = false;
    debugPrint('[SileroVAD] Neural VAD model offloaded from RAM (using adaptive RMS fallback)');
  }

  @override
  void stopVad() {
    _sherpaVad?.reset();
    _isSpeechActive = false;
    _consecutiveSpeechFrames = 0;
    _consecutiveSilenceFrames = 0;
  }

  @override
  void release() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _sherpaVad?.free();
      _sherpaVad = null;
    } catch (_) {}
    _isNeuralInitialized = false;
    _ringBuffer.clear();
  }
}
