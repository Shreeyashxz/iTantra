import 'dart:async';

abstract class SpeechEngine {
  Stream<String> startListening([String languageCode = 'hi']);
  void stopListening();
  Future<String> stopListeningAndTranscribe([String? languageCode]);

  Future<void> synthesizeSpeech(
    String text,
    String languageCode, [
    String gender = 'FEMALE',
    String ttsEngineType = 'AI4BHARAT_RASA',
  ]);
  void stopSpeech();

  bool get isSttLoaded;
  void unloadStt();
  bool get isTtsLoaded;
  void unloadTts();

  void release();
}
