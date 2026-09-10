import 'dart:async';

abstract class SpeechEngine {
  Stream<String> startListening([String languageCode = 'hi']);
  void stopListening();
  Future<String> stopListeningAndTranscribe([String? languageCode]);

  Future<void> synthesizeSpeech(
    String text,
    String languageCode, [
    String gender = 'FEMALE',
    String ttsEngineType = 'META_MMS',
  ]);
  void stopSpeech();

  bool get isSttLoaded;
  void unloadStt();
  String? get loadedSttVariant;

  bool get isTtsLoaded;
  void unloadTts();
  List<String> get loadedTtsKeys;
  bool isTtsKeyLoaded(String key);
  void unloadTtsKey(String key);

  void release();
}
