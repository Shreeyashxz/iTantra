import 'dart:async';

abstract class SpeechEngine {
  Stream<String> startListening();
  void stopListening();

  Future<void> synthesizeSpeech(String text, String languageCode);
  void stopSpeech();

  void release();
}
