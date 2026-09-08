import 'dart:async';
import 'dart:typed_data';

abstract class VadEngine {
  Stream<bool> startVad(Stream<Int16List> audioData);
  void stopVad();
  void release();

  /// Pre-speech lookback frames to capture the first syllable upon voice trigger
  List<Int16List> get lookbackBuffer => const [];
}
