import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'vad_engine.dart';

/// Real-time Voice Activity Detection Engine matching Silero VAD parameters
class SileroVadEngine implements VadEngine {
  double sensitivity; // 0.1 (least sensitive) to 1.0 (most sensitive)
  final double minSilenceDuration;
  final double minSpeechDuration;
  final int sampleRate;

  bool _isSpeechActive = false;
  int _consecutiveSilenceFrames = 0;
  int _consecutiveSpeechFrames = 0;
  StreamSubscription<Int16List>? _subscription;
  final _speechStateController = StreamController<bool>.broadcast();

  SileroVadEngine({
    this.sensitivity = 0.6,
    this.minSilenceDuration = 0.4,
    this.minSpeechDuration = 0.15,
    this.sampleRate = 16000,
  });

  void setSensitivity(double value) {
    sensitivity = value.clamp(0.1, 1.0);
  }

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

    // Calculate Root Mean Square (RMS) energy normalized to [0, 1]
    double sum = 0;
    for (int i = 0; i < samples.length; i++) {
      final normalized = samples[i] / 32768.0;
      sum += normalized * normalized;
    }
    final rms = sqrt(sum / samples.length);

    // Dynamic energy thresholding calibrated for sensitivity:
    // 1.0 = High Sensitivity (cutoff 0.005, detects soft speech/whispers)
    // 0.6 = Balanced/Normal (cutoff 0.017)
    // 0.1 = Low Sensitivity (cutoff 0.032, filters loud ambient noise)
    final cutoff = 0.005 + (1.0 - sensitivity) * 0.030;
    final isVoiceFrame = rms > cutoff;

    // Frame duration based on chunk length
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
      if (_consecutiveSilenceFrames >= minSilenceFrames) {
        _consecutiveSpeechFrames = 0;
        return false;
      }
    }

    return _isSpeechActive;
  }

  @override
  void stopVad() {
    _subscription?.cancel();
    _subscription = null;
    _isSpeechActive = false;
    _consecutiveSilenceFrames = 0;
    _consecutiveSpeechFrames = 0;
  }

  @override
  void release() {
    stopVad();
    _speechStateController.close();
  }
}
