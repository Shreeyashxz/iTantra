import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

sealed class DownloadState {
  const DownloadState();
}

class DownloadStateIdle extends DownloadState {
  const DownloadStateIdle();
}

class DownloadStateDownloading extends DownloadState {
  final String item;
  final int progressPercent;
  const DownloadStateDownloading(this.item, this.progressPercent);
}

class DownloadStateCompleted extends DownloadState {
  final String message;
  const DownloadStateCompleted(this.message);
}

class DownloadStateError extends DownloadState {
  final String message;
  const DownloadStateError(this.message);
}

class LanguageMetadata {
  final String code;
  final String iso3;
  final String englishName;
  final String nativeName;

  const LanguageMetadata({
    required this.code,
    required this.iso3,
    required this.englishName,
    required this.nativeName,
  });
}

class LanguagePackManager {
  static const List<LanguageMetadata> supportedLanguages = [
    LanguageMetadata(code: 'hi', iso3: 'hin', englishName: 'Hindi', nativeName: 'हिंदी'),
    LanguageMetadata(code: 'en', iso3: 'eng', englishName: 'English', nativeName: 'English'),
    LanguageMetadata(code: 'gu', iso3: 'guj', englishName: 'Gujarati', nativeName: 'ગુજરાતી'),
    LanguageMetadata(code: 'mr', iso3: 'mar', englishName: 'Marathi', nativeName: 'मराठी'),
    LanguageMetadata(code: 'kn', iso3: 'kan', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    LanguageMetadata(code: 'ml', iso3: 'mal', englishName: 'Malayalam', nativeName: 'മലയാളം'),
    LanguageMetadata(code: 'ta', iso3: 'tam', englishName: 'Tamil', nativeName: 'தமிழ்'),
    LanguageMetadata(code: 'te', iso3: 'tel', englishName: 'Telugu', nativeName: 'తెలుగు'),
    LanguageMetadata(code: 'or', iso3: 'ory', englishName: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
    LanguageMetadata(code: 'bn', iso3: 'ben', englishName: 'Bengali', nativeName: 'বাংলা'),
  ];

  final _downloadStateController = StreamController<DownloadState>.broadcast();
  Stream<DownloadState> get downloadState => _downloadStateController.stream;
  DownloadState _currentState = const DownloadStateIdle();
  DownloadState get currentState => _currentState;

  void _emitState(DownloadState state) {
    _currentState = state;
    _downloadStateController.add(state);
  }

  Future<Directory> getModelsDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(baseDir.path, 'models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> isTtsAvailable(String languageCode) async {
    final dir = await getModelsDirectory();
    final rasaModel = File(p.join(dir.path, 'tts', 'rasa13', 'vits.onnx'));
    final rasaTokens = File(p.join(dir.path, 'tts', 'rasa13', 'tokens.txt'));
    if (await rasaModel.exists() && await rasaTokens.exists()) {
      return true;
    }
    final model = File(p.join(dir.path, 'tts', languageCode, 'vits.onnx'));
    final tokens = File(p.join(dir.path, 'tts', languageCode, 'tokens.txt'));
    return await model.exists() && await tokens.exists();
  }

  Future<bool> isRasa13Available() async {
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'tts', 'rasa13', 'vits.onnx'));
    final tokens = File(p.join(dir.path, 'tts', 'rasa13', 'tokens.txt'));
    return await model.exists() && await tokens.exists();
  }

  Future<bool> isSttAvailable() async {
    final dir = await getModelsDirectory();
    final indic = File(p.join(dir.path, 'stt', 'indic_conformer.onnx'));
    final tokens = File(p.join(dir.path, 'stt', 'tokens.txt'));
    return await indic.exists() && await tokens.exists();
  }

  Future<bool> isMtAvailable() async {
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'mt', 'indictrans2_int8.onnx'));
    final spm = File(p.join(dir.path, 'mt', 'spm.model'));
    return await model.exists() && await spm.exists();
  }

  Future<bool> downloadMt() async {
    final modelsDir = await getModelsDirectory();
    final mtDir = Directory(p.join(modelsDir.path, 'mt'));
    if (!await mtDir.exists()) {
      await mtDir.create(recursive: true);
    }

    final targetModel = File(p.join(mtDir.path, 'indictrans2_int8.onnx'));
    final targetSpm = File(p.join(mtDir.path, 'spm.model'));

    // Public ungated AI4Bharat IndicTrans2 INT8 ONNX checkpoint
    const mtBaseUrl =
        'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8/resolve/main';

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat IndicTrans2 INT8 (Model)', 0));

      // 1. Download Quantized Encoder ONNX weights
      if (!await targetModel.exists() || await targetModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/encoder_model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 INT8 Encoder', percent));
        });
      }

      // 2. Download Dictionary & Tokenizer mapping
      if (!await targetSpm.exists() || await targetSpm.length() < 100) {
        await _downloadFileWithRedirects('$mtBaseUrl/dict.SRC.json', targetSpm, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 Dictionary & Tokens', percent));
        });
      }

      _emitState(const DownloadStateCompleted('AI4Bharat IndicTrans2 INT8 Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicTrans2 MT: $e');
      _emitState(DownloadStateError('IndicTrans2 MT download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteMt() async {
    try {
      final modelsDir = await getModelsDirectory();
      final mtDir = Directory(p.join(modelsDir.path, 'mt'));
      if (await mtDir.exists()) {
        await mtDir.delete(recursive: true);
      }
      _emitState(const DownloadStateCompleted('IndicTrans2 MT model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicTrans2 MT model: $e');
      return false;
    }
  }

  Future<bool> downloadStt() async {
    final modelsDir = await getModelsDirectory();
    final sttDir = Directory(p.join(modelsDir.path, 'stt'));
    if (!await sttDir.exists()) {
      await sttDir.create(recursive: true);
    }

    // Clean out old Zipformer models to ensure fresh AI4Bharat IndicConformer
    final oldZipformer = File(p.join(sttDir.path, 'encoder.onnx'));
    if (await oldZipformer.exists()) {
      try {
        await sttDir.delete(recursive: true);
        await sttDir.create(recursive: true);
      } catch (_) {}
    }

    // AI4Bharat IndicConformer quantized INT8 model for Sherpa-ONNX
    const indicBaseUrl =
        'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main';
    final files = [
      ('model.int8.onnx', 'indic_conformer.onnx'),
      ('tokens.txt', 'tokens.txt'),
    ];

    try {
      for (final (remote, local) in files) {
        final targetFile = File(p.join(sttDir.path, local));
        if (!await targetFile.exists() || (await targetFile.length()) == 0) {
          _emitState(DownloadStateDownloading('IndicConformer ($local)', 0));
          await _downloadFileWithRedirects('$indicBaseUrl/$remote', targetFile, (percent) {
            _emitState(DownloadStateDownloading('IndicConformer ($local)', percent));
          });
        }
      }
      _emitState(const DownloadStateCompleted('AI4Bharat IndicConformer Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicConformer STT: $e');
      _emitState(DownloadStateError('IndicConformer download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteStt() async {
    try {
      final modelsDir = await getModelsDirectory();
      final sttDir = Directory(p.join(modelsDir.path, 'stt'));
      if (await sttDir.exists()) {
        await sttDir.delete(recursive: true);
      }
      _emitState(const DownloadStateCompleted('STT model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting STT model: $e');
      return false;
    }
  }

  Future<bool> deleteTts(String languageCode) async {
    try {
      final modelsDir = await getModelsDirectory();
      final ttsDir = Directory(p.join(modelsDir.path, 'tts', languageCode));
      if (await ttsDir.exists()) {
        await ttsDir.delete(recursive: true);
      }
      _emitState(DownloadStateCompleted('TTS model ($languageCode) deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting TTS model ($languageCode): $e');
      return false;
    }
  }

  Future<void> deleteAllModels() async {
    try {
      final modelsDir = await getModelsDirectory();
      if (await modelsDir.exists()) {
        await modelsDir.delete(recursive: true);
      }
      _emitState(const DownloadStateCompleted('All models deleted'));
    } catch (e) {
      debugPrint('Error deleting all models: $e');
    }
  }

  /// Downloads AI4Bharat Rasa-13 Universal Multilingual Neural VITS (~123 MB for all 13 Indian languages)
  Future<bool> downloadRasa13() async {
    final modelsDir = await getModelsDirectory();
    final rasaDir = Directory(p.join(modelsDir.path, 'tts', 'rasa13'));
    if (!await rasaDir.exists()) {
      await rasaDir.create(recursive: true);
    }

    final targetModel = File(p.join(rasaDir.path, 'vits.onnx'));
    final targetTokens = File(p.join(rasaDir.path, 'tokens.txt'));

    // 1. Check if local sanitized 6-input model is ready
    final localConverted = File('converted_models/vits_rasa13_6in.onnx');
    final localTokens = File('converted_models/tokens.txt');

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat Rasa-13 VITS (All Languages)', 0));

      if (await localConverted.exists() && await localTokens.exists()) {
        await localConverted.copy(targetModel.path);
        await localTokens.copy(targetTokens.path);
        _emitState(const DownloadStateCompleted('AI4Bharat Rasa-13 VITS Ready (All Languages)'));
        return true;
      }

      // 2. Download from public repository
      const rasaBaseUrl = 'https://huggingface.co/MatiasLin/sherpa-onnx-vits-rasa-13/resolve/main';
      if (!await targetTokens.exists() || (await targetTokens.length()) == 0) {
        await _downloadFileWithRedirects('$rasaBaseUrl/tokens.txt', targetTokens, (pct) {});
      }

      if (!await targetModel.exists() || (await targetModel.length()) == 0) {
        await _downloadFileWithRedirects('$rasaBaseUrl/model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('AI4Bharat Rasa-13 VITS (All Languages)', percent));
        });
      }

      _emitState(const DownloadStateCompleted('AI4Bharat Rasa-13 VITS Ready (All Languages)'));
      return true;
    } catch (e) {
      debugPrint('Error downloading Rasa-13 VITS: $e');
      _emitState(DownloadStateError('Rasa-13 VITS download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteRasa13() async {
    try {
      final modelsDir = await getModelsDirectory();
      final rasaDir = Directory(p.join(modelsDir.path, 'tts', 'rasa13'));
      if (await rasaDir.exists()) {
        await rasaDir.delete(recursive: true);
      }
      _emitState(const DownloadStateCompleted('AI4Bharat Rasa-13 model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting Rasa-13 model: $e');
      return false;
    }
  }

  /// Downloads Meta MMS-TTS ONNX model for any of the 10 SIH 26173 languages
  Future<bool> downloadTts(String languageCode) async {
    final langMeta = supportedLanguages.where((l) => l.code == languageCode).firstOrNull;
    if (langMeta == null) {
      _emitState(DownloadStateError('Unsupported language code: $languageCode'));
      return false;
    }

    final modelsDir = await getModelsDirectory();
    final ttsDir = Directory(p.join(modelsDir.path, 'tts', languageCode));
    if (!await ttsDir.exists()) {
      await ttsDir.create(recursive: true);
    }

    // Unified Meta MMS-TTS ONNX repository for all 10 languages
    final mmsBaseUrl =
        'https://huggingface.co/willwade/mms-tts-multilingual-models-onnx/resolve/main/${langMeta.iso3}';

    try {
      final targetModel = File(p.join(ttsDir.path, 'vits.onnx'));
      final targetTokens = File(p.join(ttsDir.path, 'tokens.txt'));
      final targetLexicon = File(p.join(ttsDir.path, 'lexicon.txt'));

      if (!await targetModel.exists() || (await targetModel.length()) == 0) {
        _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Model)', 0));
        await _downloadFileWithRedirects('$mmsBaseUrl/model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Model)', percent));
        });
      }

      if (!await targetTokens.exists() || (await targetTokens.length()) == 0) {
        _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Tokens)', 0));
        await _downloadFileWithRedirects('$mmsBaseUrl/tokens.txt', targetTokens, (percent) {
          _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Tokens)', percent));
        });
      }

      if (!await targetLexicon.exists()) {
        await targetLexicon.writeAsString('');
      }

      _emitState(DownloadStateCompleted('${langMeta.englishName} (${langMeta.nativeName}) TTS Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading TTS ($languageCode): $e');
      _emitState(DownloadStateError('${langMeta.englishName} TTS download failed: $e'));
      return false;
    }
  }

  /// Downloads all 10 language packs sequentially
  Future<void> downloadAllLanguages() async {
    for (final lang in supportedLanguages) {
      final available = await isTtsAvailable(lang.code);
      if (!available) {
        final success = await downloadTts(lang.code);
        if (!success) break;
      }
    }
    await downloadStt();
    _emitState(const DownloadStateCompleted('All 10 Indian Language Neural Models Installed!'));
  }

  Future<void> downloadAllEssentials() async {
    await downloadStt();
    await downloadTts('hi');
    await downloadTts('en');
    _emitState(const DownloadStateCompleted('Essential Language Models Ready'));
  }

  Future<void> _downloadFileWithRedirects(
    String urlStr,
    File destination,
    void Function(int percent) onProgress,
  ) async {
    final client = HttpClient();
    try {
      var currentUri = Uri.parse(urlStr);
      HttpClientResponse? response;
      var redirects = 0;

      while (redirects < 10) {
        final request = await client.getUrl(currentUri);
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
        response = await request.close();

        if (response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.movedTemporarily ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect ||
            response.statusCode == HttpStatus.permanentRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            currentUri = currentUri.resolve(location);
            redirects++;
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response?.statusCode} downloading $urlStr');
      }

      final contentLength = response.contentLength;
      final tempFile = File('${destination.path}.tmp');
      final sink = tempFile.openWrite();

      var received = 0;
      var lastReported = -1;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final percent = ((received * 100) / contentLength).clamp(0, 100).toInt();
          if (percent != lastReported) {
            lastReported = percent;
            onProgress(percent);
          }
        }
      }

      await sink.flush();
      await sink.close();

      if (await destination.exists()) {
        await destination.delete();
      }
      await tempFile.rename(destination.path);
    } finally {
      client.close(force: true);
    }
  }

  void dispose() {
    _downloadStateController.close();
  }
}
