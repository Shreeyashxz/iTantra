import 'dart:async';
import 'dart:typed_data';

abstract class VadEngine {
  Stream<bool> startVad(Stream<Int16List> audioData);
  void stopVad();
  void release();
}
