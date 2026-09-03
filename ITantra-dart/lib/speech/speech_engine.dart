import 'dart:async';

abstract class SpeechEngine {
  Stream<String> startListening([String languageCode = 'hi']);
  void stopListening();
  Future<String> stopListeningAndTranscribe([String? languageCode]);

  Future<void> synthesizeSpeech(String text, String languageCode, [String gender = 'FEMALE']);
  void stopSpeech();

  void release();
}
