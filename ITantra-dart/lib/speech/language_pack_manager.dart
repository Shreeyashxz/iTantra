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

class LanguagePackManager {
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
      _emitState(const DownloadStateCompleted('STT Model Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading STT: $e');
      _emitState(DownloadStateError('STT Download failed: $e'));
      return false;
    }
  }

  Future<bool> downloadTts(String languageCode) async {
    final modelsDir = await getModelsDirectory();
    final ttsDir = Directory(p.join(modelsDir.path, 'tts', languageCode));
    if (!await ttsDir.exists()) {
      await ttsDir.create(recursive: true);
    }

    final (baseUrl, modelFile) = languageCode == 'hi'
        ? (
            'https://huggingface.co/csukuangfj/vits-piper-hi_IN-pratham-medium/resolve/main',
            'hi_IN-pratham-medium.onnx',
          )
        : (
            'https://huggingface.co/csukuangfj/vits-piper-en_US-amy-low/resolve/main',
            'en_US-amy-low.onnx',
          );

    try {
      final targetModel = File(p.join(ttsDir.path, 'vits.onnx'));
      final targetTokens = File(p.join(ttsDir.path, 'tokens.txt'));
      final targetLexicon = File(p.join(ttsDir.path, 'lexicon.txt'));

      if (!await targetModel.exists() || (await targetModel.length()) == 0) {
        _emitState(DownloadStateDownloading('TTS $languageCode (voice)', 0));
        await _downloadFileWithRedirects('$baseUrl/$modelFile', targetModel, (percent) {
          _emitState(DownloadStateDownloading('TTS $languageCode (voice)', percent));
        });
      }

      if (!await targetTokens.exists() || (await targetTokens.length()) == 0) {
        _emitState(DownloadStateDownloading('TTS $languageCode (tokens)', 0));
        await _downloadFileWithRedirects('$baseUrl/tokens.txt', targetTokens, (percent) {
          _emitState(DownloadStateDownloading('TTS $languageCode (tokens)', percent));
        });
      }

      if (!await targetLexicon.exists()) {
        await targetLexicon.writeAsString('');
      }

      _emitState(DownloadStateCompleted('TTS for $languageCode Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading TTS: $e');
      _emitState(DownloadStateError('TTS Download failed: $e'));
      return false;
    }
  }

  Future<bool> downloadAllEssentials() async {
    final sttOk = await downloadStt();
    final ttsHiOk = await downloadTts('hi');
    final ttsEnOk = await downloadTts('en');
    return sttOk && ttsHiOk && ttsEnOk;
  }

  Future<void> _downloadFileWithRedirects(
    String urlStr,
    File destination,
    void Function(int percent) onProgress,
  ) async {
    final client = HttpClient();
    client.autoUncompress = true;
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      var currentUri = Uri.parse(urlStr);
      var redirects = 0;
      const maxRedirects = 10;
      HttpClientResponse? response;

      while (redirects < maxRedirects) {
        final request = await client.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (compatible; iTantra/1.0)');
        request.followRedirects = false; // Manually handle to properly resolve relative and cross-domain locations
        response = await request.close();

        if (response.isRedirect ||
            response.statusCode == HttpStatus.movedPermanently ||
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
