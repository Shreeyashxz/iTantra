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

  Future<bool> isSttAvailable() async {
    final dir = await getModelsDirectory();
    final enc = File(p.join(dir.path, 'stt', 'encoder.onnx'));
    final dec = File(p.join(dir.path, 'stt', 'decoder.onnx'));
    final join = File(p.join(dir.path, 'stt', 'joiner.onnx'));
    final tokens = File(p.join(dir.path, 'stt', 'tokens.txt'));
    return await enc.exists() && await dec.exists() && await join.exists() && await tokens.exists();
  }

  Future<bool> isTtsAvailable(String languageCode) async {
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'tts', languageCode, 'vits.onnx'));
    final tokens = File(p.join(dir.path, 'tts', languageCode, 'tokens.txt'));
    return await model.exists() && await tokens.exists();
  }

  Future<bool> downloadStt() async {
    final modelsDir = await getModelsDirectory();
    final sttDir = Directory(p.join(modelsDir.path, 'stt'));
    if (!await sttDir.exists()) {
      await sttDir.create(recursive: true);
    }

    const baseUrl =
        'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/main';
    final files = [
      ('encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx', 'encoder.onnx'),
      ('decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx', 'decoder.onnx'),
      ('joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx', 'joiner.onnx'),
      ('tokens.txt', 'tokens.txt'),
    ];

    try {
      for (final (remote, local) in files) {
        final targetFile = File(p.join(sttDir.path, local));
        if (!await targetFile.exists() || (await targetFile.length()) == 0) {
          _emitState(DownloadStateDownloading('STT ($local)', 0));
          await _downloadFileWithRedirects('$baseUrl/$remote', targetFile, (percent) {
            _emitState(DownloadStateDownloading('STT ($local)', percent));
          });
        }
      }
      _emitState(const DownloadStateCompleted('STT Neural Engine Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading STT: $e');
      _emitState(DownloadStateError('STT Download failed: $e'));
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
        request.headers.set(HttpHeaders.userAgentHeader, 'iTantra/1.0.0 (Windows)');
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
