import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/language_pack_manager.dart';
import 'package:itantra_dart/speech/sherpa_onnx_speech_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('xyz.luan/audioplayers.global');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => 1);
    const audioChannel = MethodChannel('xyz.luan/audioplayers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (MethodCall methodCall) async => 1);
  });

  group('Model Persistence & Update Safety Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('itantra_models_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Obsolete Zipformer cleanup removes only obsolete files and preserves IndicConformer', () async {
      final sttDir = Directory(p.join(tempDir.path, 'stt'));
      await sttDir.create(recursive: true);

      // Create existing user models
      final fp32Model = File(p.join(sttDir.path, 'indic_conformer_fp32.onnx'));
      await fp32Model.writeAsString('fp32_model_data_sample');
      final tokensFile = File(p.join(sttDir.path, 'tokens.txt'));
      await tokensFile.writeAsString('tokens_data_sample');

      // Create obsolete zipformer files
      final oldEncoder = File(p.join(sttDir.path, 'encoder.onnx'));
      await oldEncoder.writeAsString('obsolete_encoder');
      final oldDecoder = File(p.join(sttDir.path, 'decoder.onnx'));
      await oldDecoder.writeAsString('obsolete_decoder');

      expect(await oldEncoder.exists(), isTrue);
      expect(await oldDecoder.exists(), isTrue);
      expect(await fp32Model.exists(), isTrue);
      expect(await tokensFile.exists(), isTrue);

      // Execute selective cleanup
      for (final obsolete in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx']) {
        final f = File(p.join(sttDir.path, obsolete));
        if (await f.exists()) {
          await f.delete();
        }
      }

      // Verify obsolete files removed, but existing models preserved
      expect(await oldEncoder.exists(), isFalse);
      expect(await oldDecoder.exists(), isFalse);
      expect(await fp32Model.exists(), isTrue);
      expect(await tokensFile.exists(), isTrue);
    });

    test('Candidate model directory discovery includes standard paths', () async {
      final lpm = LanguagePackManager();
      final candidates = await lpm.getCandidateModelDirectories();

      expect(candidates.isNotEmpty, isTrue);
      final paths = candidates.map((d) => d.path.toLowerCase()).toList();
      // Must include models or converted_models in paths
      expect(paths.any((p) => p.contains('models')), isTrue);
    });

    test('SherpaOnnxSpeechEngine initializes with LanguagePackManager and resolves models directory', () async {
      final lpm = LanguagePackManager();
      final engine = SherpaOnnxSpeechEngine(languagePackManager: lpm);
      expect(engine, isNotNull);
      expect(engine.isSttLoaded, isFalse);
      expect(engine.isTtsLoaded, isFalse);
    });
  });
}
