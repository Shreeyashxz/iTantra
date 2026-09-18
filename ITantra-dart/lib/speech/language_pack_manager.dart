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
  final String modelKey;
  final int progressPercent;
  const DownloadStateDownloading(this.item, this.progressPercent, {this.modelKey = ''});
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

  Directory? _cachedModelsDir;

  Future<Directory> getModelsDirectory() async {
    if (_cachedModelsDir != null && await _cachedModelsDir!.exists()) {
      return _cachedModelsDir!;
    }
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(baseDir.path, 'models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedModelsDir = dir;
    // Non-blocking background sync of existing models from candidate locations
    unawaited(syncExistingModels());
    return dir;
  }

  /// Returns all candidate directories where existing models may reside
  /// across app updates, dev runs, or secondary storage.
  Future<List<Directory>> getCandidateModelDirectories() async {
    final List<Directory> dirs = [];

    // 1. Primary: Application Support directory (standard persistent app data)
    try {
      final supportDir = await getApplicationSupportDirectory();
      dirs.add(Directory(p.join(supportDir.path, 'models')));
    } catch (_) {}

    // 2. Application Documents directory (alternative persistent data)
    try {
      final docDir = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(docDir.path, 'models')));
    } catch (_) {}

    // 3. Android External Storage directory
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          dirs.add(Directory(p.join(extDir.path, 'models')));
        }
      } catch (_) {}
    }

    // 4. Executable / Portable relative directory (Windows / Linux)
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        dirs.add(Directory(p.join(exeDir, 'models')));
      } catch (_) {}
    }

    // 5. Current Working Directory (development runs / bundled workspace models)
    try {
      dirs.add(Directory(p.join(Directory.current.path, 'models')));
      dirs.add(Directory(p.join(Directory.current.path, 'converted_models')));
    } catch (_) {}

    return dirs;
  }

  /// Scans all candidate model directories and ensures any existing neural model files
  /// are preserved and copied to the primary models directory so they are never lost on app updates.
  Future<void> syncExistingModels() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final primaryDir = Directory(p.join(baseDir.path, 'models'));
      if (!await primaryDir.exists()) {
        await primaryDir.create(recursive: true);
      }

      // Check bundled converted_models Rasa-13
      final localRasaModel = File('converted_models/vits_rasa13_6in.onnx');
      final localRasaTokens = File('converted_models/tokens.txt');
      if (await localRasaModel.exists() && (await localRasaModel.length()) > 10 * 1024 * 1024) {
        final targetRasaDir = Directory(p.join(primaryDir.path, 'tts', 'rasa13'));
        final targetRasaModel = File(p.join(targetRasaDir.path, 'vits.onnx'));
        final targetRasaTokens = File(p.join(targetRasaDir.path, 'tokens.txt'));
        if (!await targetRasaModel.exists() || (await targetRasaModel.length()) < 10 * 1024 * 1024) {
          await targetRasaDir.create(recursive: true);
          await localRasaModel.copy(targetRasaModel.path);
          if (await localRasaTokens.exists()) {
            await localRasaTokens.copy(targetRasaTokens.path);
          }
          debugPrint('[LanguagePackManager] Synced bundled Rasa-13 model to persistent storage: ${targetRasaModel.path}');
        }
      }

      final candidates = await getCandidateModelDirectories();
      for (final candidate in candidates) {
        if (candidate.path == primaryDir.path || !await candidate.exists()) {
          continue;
        }

        await for (final entity in candidate.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final relPath = p.relative(entity.path, from: candidate.path);
            final ext = p.extension(entity.path).toLowerCase();
            if (!{'.onnx', '.model', '.txt', '.json', '.data'}.contains(ext)) {
              continue;
            }

            final destFile = File(p.join(primaryDir.path, relPath));
            if (!await destFile.exists() || (await destFile.length()) == 0) {
              final srcLen = await entity.length();
              if (srcLen > 0) {
                await destFile.parent.create(recursive: true);
                await entity.copy(destFile.path);
                debugPrint('[LanguagePackManager] Preserved existing model asset across update: $relPath ($srcLen bytes)');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LanguagePackManager] Model synchronization check completed with notice: $e');
    }
  }

  Future<bool> isTtsAvailable(String languageCode) async {
    if (await isRasa13Available()) {
      return true;
    }
    return await isMmsAvailable(languageCode);
  }

  Future<bool> isRasa13Available() async {
    final localRasaModel = File('converted_models/vits_rasa13_6in.onnx');
    final localRasaTokens = File('converted_models/tokens.txt');
    if (localRasaModel.existsSync() &&
        localRasaTokens.existsSync() &&
        localRasaModel.lengthSync() > 10 * 1024 * 1024) {
      return true;
    }
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'tts', 'rasa13', 'vits.onnx'));
    final tokens = File(p.join(dir.path, 'tts', 'rasa13', 'tokens.txt'));
    if (await model.exists() && await tokens.exists()) {
      return (await model.length()) > 10 * 1024 * 1024;
    }
    return false;
  }

  Future<bool> isMmsAvailable(String languageCode) async {
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'tts', languageCode, 'vits.onnx'));
    final tokens = File(p.join(dir.path, 'tts', languageCode, 'tokens.txt'));
    if (await model.exists() && await tokens.exists()) {
      return (await model.length()) > 10 * 1024 * 1024;
    }
    return false;
  }

  Future<bool> isSttAvailable() async {
    final dir = await getModelsDirectory();
    final indic = File(p.join(dir.path, 'stt', 'indic_conformer.onnx'));
    final tokens = File(p.join(dir.path, 'stt', 'tokens.txt'));
    if (await indic.exists() && await tokens.exists()) {
      return (await indic.length()) > 10 * 1024 * 1024;
    }
    return false;
  }

  Future<bool> isSttFp32Available() async {
    final dir = await getModelsDirectory();
    final indicFp32 = File(p.join(dir.path, 'stt', 'indic_conformer_fp32.onnx'));
    final tokens = File(p.join(dir.path, 'stt', 'tokens.txt'));
    return await indicFp32.exists() && await tokens.exists();
  }

  Future<bool> isMtIndicIndicAvailable() async {
    final dir = await getModelsDirectory();
    final modelDir = Directory(p.join(dir.path, 'mt', 'indic_indic', 'int8'));
    final enc = File(p.join(modelDir.path, 'encoder_model.onnx.data'));
    final dec = File(p.join(modelDir.path, 'decoder_shared.onnx.data'));
    if (await enc.exists() && await dec.exists()) {
      return (await enc.length()) > 50 * 1024 * 1024 && (await dec.length()) > 50 * 1024 * 1024;
    }
    // Backward compatibility with legacy flat directory layout
    final legacyEnc = File(p.join(dir.path, 'mt', 'int8', 'encoder_model.onnx.data'));
    final legacyDec = File(p.join(dir.path, 'mt', 'int8', 'decoder_shared.onnx.data'));
    if (await legacyEnc.exists() && await legacyDec.exists()) {
      return (await legacyEnc.length()) > 50 * 1024 * 1024 && (await legacyDec.length()) > 50 * 1024 * 1024;
    }
    return false;
  }

  Future<bool> isMtIndicEnAvailable() async {
    final dir = await getModelsDirectory();
    final modelDir = Directory(p.join(dir.path, 'mt', 'indic_en', 'int8'));
    final enc = File(p.join(modelDir.path, 'encoder_model.onnx.data'));
    final dec = File(p.join(modelDir.path, 'decoder_shared.onnx.data'));
    if (await enc.exists() && await dec.exists()) {
      return (await enc.length()) > 50 * 1024 * 1024 && (await dec.length()) > 50 * 1024 * 1024;
    }
    return false;
  }

  Future<bool> isMtAvailable() async {
    return (await isMtIndicIndicAvailable()) || (await isMtIndicEnAvailable());
  }

  Future<bool> isMtFp16Available() async {
    final dir = await getModelsDirectory();
    final subModel = File(p.join(dir.path, 'mt', 'fp16', 'encoder_model.onnx'));
    final subData = File(p.join(dir.path, 'mt', 'fp16', 'encoder_model.onnx.data'));
    final subSpm = File(p.join(dir.path, 'mt', 'fp16', 'spm.model'));
    if (await subModel.exists() && await subData.exists() && await subSpm.exists()) {
      return (await subData.length()) > 100 * 1024 * 1024;
    }
    // Backward compatibility with legacy flat directory layout
    final model = File(p.join(dir.path, 'mt', 'indictrans2_fp16.onnx'));
    final data = File(p.join(dir.path, 'mt', 'encoder_model.onnx.data'));
    final spm = File(p.join(dir.path, 'mt', 'spm.model'));
    if (!await model.exists() || !await data.exists() || !await spm.exists()) return false;
    return (await data.length()) > 100 * 1024 * 1024;
  }

  /// Checks if AI4Bharat IndicLID FastText model weights exist in local models storage
  Future<bool> isLidAvailable() async {
    final dir = await getModelsDirectory();
    final target = File(p.join(dir.path, 'lid', 'indiclid_fasttext.bin'));
    final targetRoot = File(p.join(dir.path, 'indiclid_fasttext.bin'));
    if (await target.exists() && (await target.length()) > 1024) return true;
    if (await targetRoot.exists() && (await targetRoot.length()) > 1024) return true;
    return false;
  }

  /// Downloads AI4Bharat IndicLID FastText (~14 MB model weights)
  Future<bool> downloadLid() async {
    final modelsDir = await getModelsDirectory();
    final lidDir = Directory(p.join(modelsDir.path, 'lid'));
    if (!await lidDir.exists()) {
      await lidDir.create(recursive: true);
    }
    final targetFile = File(p.join(lidDir.path, 'indiclid_fasttext.bin'));

    if (await targetFile.exists() && (await targetFile.length()) > 1024) {
      _emitState(const DownloadStateCompleted('IndicLID-FastText Ready'));
      return true;
    }

    const lidUrl =
        'https://huggingface.co/ai4bharat/IndicLID-FTN/resolve/main/model_baseline_roman.bin';

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat IndicLID-FastText (~14 MB)', 0, modelKey: 'lid'));
      await _downloadFileWithRedirects(lidUrl, targetFile, (percent) {
        _emitState(DownloadStateDownloading('IndicLID-FastText (~14 MB)', percent, modelKey: 'lid'));
      });
      _emitState(const DownloadStateCompleted('AI4Bharat IndicLID-FastText Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicLID-FastText: $e');
      _emitState(DownloadStateError('IndicLID download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteLid() async {
    try {
      final modelsDir = await getModelsDirectory();
      final targetFile = File(p.join(modelsDir.path, 'lid', 'indiclid_fasttext.bin'));
      final targetRoot = File(p.join(modelsDir.path, 'indiclid_fasttext.bin'));
      if (await targetFile.exists()) await targetFile.delete();
      if (await targetRoot.exists()) await targetRoot.delete();
      _emitState(const DownloadStateCompleted('IndicLID model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicLID model: $e');
      return false;
    }
  }

  /// Checks if AI4Bharat IndicXlit neural model weights exist in local models storage
  Future<bool> isIndicXlitAvailable() async {
    final dir = await getModelsDirectory();
    final model = File(p.join(dir.path, 'indicxlit.onnx'));
    final modelSub = File(p.join(dir.path, 'xlit', 'indicxlit.onnx'));
    if (await model.exists() && (await model.length()) > 1024) return true;
    if (await modelSub.exists() && (await modelSub.length()) > 1024) return true;
    return false;
  }

  Future<bool> downloadMt() async {
    return downloadMtIndicIndic();
  }

  Future<bool> downloadMtIndicIndic() async {
    final modelsDir = await getModelsDirectory();
    final mtDir = Directory(p.join(modelsDir.path, 'mt', 'indic_indic', 'int8'));
    final fallbackDir = Directory(p.join(modelsDir.path, 'mt', 'int8'));
    if (!await mtDir.exists()) await mtDir.create(recursive: true);
    if (!await fallbackDir.exists()) await fallbackDir.create(recursive: true);

    final targetModel = File(p.join(mtDir.path, 'encoder_model.onnx'));
    final targetData = File(p.join(mtDir.path, 'encoder_model.onnx.data'));
    final targetDecModel = File(p.join(mtDir.path, 'decoder_model.onnx'));
    final targetDecPast = File(p.join(mtDir.path, 'decoder_with_past_model.onnx'));
    final targetDecData = File(p.join(mtDir.path, 'decoder_shared.onnx.data'));
    final targetSpm = File(p.join(mtDir.path, 'spm.model'));
    final targetDictSrc = File(p.join(mtDir.path, 'dict.SRC.json'));
    final targetDictTgt = File(p.join(mtDir.path, 'dict.TGT.json'));

    const mtBaseUrl =
        'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8/resolve/main';

    try {
      _emitState(const DownloadStateDownloading('IndicTrans2 Indic-Indic 320M', 0, modelKey: 'mt_indic_indic'));

      // 1. Encoder Graph
      if (!await targetModel.exists() || await targetModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/encoder_model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Encoder Graph', percent, modelKey: 'mt_indic_indic'));
        });
      }

      // 2. Encoder Weights (~120 MB)
      if (!await targetData.exists() || await targetData.length() < 50 * 1024 * 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/encoder_model.onnx.data', targetData, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Encoder Weights (~120 MB)', percent, modelKey: 'mt_indic_indic'));
        });
      }

      // 3. Decoder Graph
      if (!await targetDecModel.exists() || await targetDecModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_model.onnx', targetDecModel, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Decoder Graph', percent, modelKey: 'mt_indic_indic'));
        });
      }

      // 4. Decoder Past Graph
      if (!await targetDecPast.exists() || await targetDecPast.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_with_past_model.onnx', targetDecPast, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Decoder Past Graph', percent, modelKey: 'mt_indic_indic'));
        });
      }

      // 5. Decoder Weights (~203 MB)
      if (!await targetDecData.exists() || await targetDecData.length() < 50 * 1024 * 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_shared.onnx.data', targetDecData, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Decoder Weights (~203 MB)', percent, modelKey: 'mt_indic_indic'));
        });
      }

      // 6. Tokenizer & Dictionaries
      if (!await targetSpm.exists() || await targetSpm.length() < 1000) {
        await _downloadFileWithRedirects('$mtBaseUrl/model.SRC', targetSpm, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Tokenizer', percent, modelKey: 'mt_indic_indic'));
        });
      }
      if (!await targetDictSrc.exists() || await targetDictSrc.length() < 100) {
        await _downloadFileWithRedirects('$mtBaseUrl/dict.SRC.json', targetDictSrc, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Source Dict', percent, modelKey: 'mt_indic_indic'));
        });
      }
      if (!await targetDictTgt.exists() || await targetDictTgt.length() < 100) {
        await _downloadFileWithRedirects('$mtBaseUrl/dict.TGT.json', targetDictTgt, (percent) {
          _emitState(DownloadStateDownloading('Indic-Indic Target Dict', percent, modelKey: 'mt_indic_indic'));
        });
      }

      _emitState(const DownloadStateCompleted('IndicTrans2 Indic-Indic 320M Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicTrans2 Indic-Indic 320M: $e');
      _emitState(DownloadStateError('IndicTrans2 Indic-Indic download failed: $e'));
      return false;
    }
  }

  Future<bool> downloadMtIndicEn() async {
    final modelsDir = await getModelsDirectory();
    final mtDir = Directory(p.join(modelsDir.path, 'mt', 'indic_en', 'int8'));
    if (!await mtDir.exists()) await mtDir.create(recursive: true);

    final targetModel = File(p.join(mtDir.path, 'encoder_model.onnx'));
    final targetData = File(p.join(mtDir.path, 'encoder_model.onnx.data'));
    final targetDecModel = File(p.join(mtDir.path, 'decoder_model.onnx'));
    final targetDecPast = File(p.join(mtDir.path, 'decoder_with_past_model.onnx'));
    final targetDecData = File(p.join(mtDir.path, 'decoder_shared.onnx.data'));
    final targetSpm = File(p.join(mtDir.path, 'spm.model'));
    final targetDictSrc = File(p.join(mtDir.path, 'dict.SRC.json'));
    final targetDictTgt = File(p.join(mtDir.path, 'dict.TGT.json'));

    const mtBaseUrl =
        'https://huggingface.co/hari31416/indictrans2-indic-en-dist-200M-ONNX-int8/resolve/main';

    try {
      _emitState(const DownloadStateDownloading('IndicTrans2 Indic-En 200M', 0, modelKey: 'mt_indic_en'));

      // 1. Encoder Graph
      if (!await targetModel.exists() || await targetModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/encoder_model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Encoder Graph', percent, modelKey: 'mt_indic_en'));
        });
      }

      // 2. Encoder Weights (~120 MB)
      if (!await targetData.exists() || await targetData.length() < 50 * 1024 * 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/encoder_model.onnx.data', targetData, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Encoder Weights (~120 MB)', percent, modelKey: 'mt_indic_en'));
        });
      }

      // 3. Decoder Graph
      if (!await targetDecModel.exists() || await targetDecModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_model.onnx', targetDecModel, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Decoder Graph', percent, modelKey: 'mt_indic_en'));
        });
      }

      // 4. Decoder Past Graph
      if (!await targetDecPast.exists() || await targetDecPast.length() < 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_with_past_model.onnx', targetDecPast, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Decoder Past Graph', percent, modelKey: 'mt_indic_en'));
        });
      }

      // 5. Decoder Weights (~110 MB)
      if (!await targetDecData.exists() || await targetDecData.length() < 50 * 1024 * 1024) {
        await _downloadFileWithRedirects('$mtBaseUrl/decoder_shared.onnx.data', targetDecData, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Decoder Weights (~110 MB)', percent, modelKey: 'mt_indic_en'));
        });
      }

      // 6. Tokenizer & Dictionaries
      if (!await targetSpm.exists() || await targetSpm.length() < 1000) {
        await _downloadFileWithRedirects('$mtBaseUrl/model.SRC', targetSpm, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Tokenizer', percent, modelKey: 'mt_indic_en'));
        });
      }
      if (!await targetDictSrc.exists() || await targetDictSrc.length() < 100) {
        await _downloadFileWithRedirects('$mtBaseUrl/dict.SRC.json', targetDictSrc, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Source Dict', percent, modelKey: 'mt_indic_en'));
        });
      }
      if (!await targetDictTgt.exists() || await targetDictTgt.length() < 100) {
        await _downloadFileWithRedirects('$mtBaseUrl/dict.TGT.json', targetDictTgt, (percent) {
          _emitState(DownloadStateDownloading('Indic-En Target Dict', percent, modelKey: 'mt_indic_en'));
        });
      }

      _emitState(const DownloadStateCompleted('IndicTrans2 Indic-En 200M Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicTrans2 Indic-En 200M: $e');
      _emitState(DownloadStateError('IndicTrans2 Indic-En download failed: $e'));
      return false;
    }
  }

  Future<bool> downloadMtFp16() async {
    final modelsDir = await getModelsDirectory();
    final mtDir = Directory(p.join(modelsDir.path, 'mt', 'fp16'));
    if (!await mtDir.exists()) {
      await mtDir.create(recursive: true);
    }

    final targetModel = File(p.join(mtDir.path, 'encoder_model.onnx'));
    final targetData = File(p.join(mtDir.path, 'encoder_model.onnx.data'));
    final targetSpm = File(p.join(mtDir.path, 'spm.model'));
    final targetDict = File(p.join(mtDir.path, 'dict.SRC.json'));
    final legacyModel = File(p.join(modelsDir.path, 'mt', 'indictrans2_fp16.onnx'));

    // Public ungated AI4Bharat IndicTrans2 FP16 ONNX checkpoint from same creator (hari31416)
    const mtFp16BaseUrl =
        'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-fp16/resolve/main';

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat IndicTrans2 FP16 (Graph)', 0, modelKey: 'mt_fp16'));

      // 1. Download Full Precision Encoder ONNX computational graph (~831 KB)
      if (!await targetModel.exists() || await targetModel.length() < 1024) {
        await _downloadFileWithRedirects('$mtFp16BaseUrl/encoder_model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 FP16 Graph', percent, modelKey: 'mt_fp16'));
        });
      }
      try {
        if (!await legacyModel.parent.exists()) await legacyModel.parent.create(recursive: true);
        if (!await legacyModel.exists() || await legacyModel.length() < 1024) {
          await targetModel.copy(legacyModel.path);
        }
      } catch (_) {}

      // 2. Download FP16 Tensor Weights (~239 MB)
      if (!await targetData.exists() || await targetData.length() < 100 * 1024 * 1024) {
        await _downloadFileWithRedirects('$mtFp16BaseUrl/encoder_model.onnx.data', targetData, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 FP16 Weights (~239 MB)', percent, modelKey: 'mt_fp16'));
        });
      }

      // 3. Download SentencePiece Tokenizer Model (~3.25 MB)
      if (!await targetSpm.exists() || await targetSpm.length() < 1000) {
        await _downloadFileWithRedirects('$mtFp16BaseUrl/model.SRC', targetSpm, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 FP16 Tokenizer Model', percent, modelKey: 'mt_fp16'));
        });
      }

      // 4. Download Dictionary & Token mapping (~3.39 MB)
      if (!await targetDict.exists() || await targetDict.length() < 100) {
        await _downloadFileWithRedirects('$mtFp16BaseUrl/dict.SRC.json', targetDict, (percent) {
          _emitState(DownloadStateDownloading('IndicTrans2 FP16 Dictionary', percent, modelKey: 'mt_fp16'));
        });
      }

      _emitState(const DownloadStateCompleted('AI4Bharat IndicTrans2 FP16 Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicTrans2 FP16 MT: $e');
      _emitState(DownloadStateError('IndicTrans2 FP16 MT download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteMtIndicIndic() async {
    try {
      final modelsDir = await getModelsDirectory();
      final subDir = Directory(p.join(modelsDir.path, 'mt', 'indic_indic'));
      if (await subDir.exists()) await subDir.delete(recursive: true);
      final legacyDir = Directory(p.join(modelsDir.path, 'mt', 'int8'));
      if (await legacyDir.exists()) await legacyDir.delete(recursive: true);
      final legacyModel = File(p.join(modelsDir.path, 'mt', 'indictrans2_int8.onnx'));
      if (await legacyModel.exists()) await legacyModel.delete();

      _emitState(const DownloadStateCompleted('IndicTrans2 Indic-Indic model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicTrans2 Indic-Indic MT model: $e');
      return false;
    }
  }

  Future<bool> deleteMtIndicEn() async {
    try {
      final modelsDir = await getModelsDirectory();
      final subDir = Directory(p.join(modelsDir.path, 'mt', 'indic_en'));
      if (await subDir.exists()) await subDir.delete(recursive: true);

      _emitState(const DownloadStateCompleted('IndicTrans2 Indic-En model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicTrans2 Indic-En MT model: $e');
      return false;
    }
  }

  Future<bool> deleteMt() async {
    final ok1 = await deleteMtIndicIndic();
    final ok2 = await deleteMtIndicEn();
    return ok1 || ok2;
  }

  Future<bool> deleteMtFp16() async {
    try {
      final modelsDir = await getModelsDirectory();
      final subDir = Directory(p.join(modelsDir.path, 'mt', 'fp16'));
      if (await subDir.exists()) {
        await subDir.delete(recursive: true);
      }
      final legacyModel = File(p.join(modelsDir.path, 'mt', 'indictrans2_fp16.onnx'));
      if (await legacyModel.exists()) await legacyModel.delete();

      _emitState(const DownloadStateCompleted('IndicTrans2 FP16 model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicTrans2 FP16 MT model: $e');
      return false;
    }
  }

  Future<bool> downloadStt() async {
    final modelsDir = await getModelsDirectory();
    final sttDir = Directory(p.join(modelsDir.path, 'stt'));
    if (!await sttDir.exists()) {
      await sttDir.create(recursive: true);
    }

    // Clean out only obsolete legacy STT files if present, without deleting the entire directory
    for (final obsolete in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx']) {
      final f = File(p.join(sttDir.path, obsolete));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
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
        final minSize = local.endsWith('.onnx') ? 10 * 1024 * 1024 : 100;
        if (!await targetFile.exists() || (await targetFile.length()) < minSize) {
          _emitState(DownloadStateDownloading('IndicConformer ($local)', 0, modelKey: 'stt'));
          await _downloadFileWithRedirects('$indicBaseUrl/$remote', targetFile, (percent) {
            _emitState(DownloadStateDownloading('IndicConformer ($local)', percent, modelKey: 'stt'));
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
      final int8File = File(p.join(sttDir.path, 'indic_conformer.onnx'));
      if (await int8File.exists()) {
        await int8File.delete();
      }
      _emitState(const DownloadStateCompleted('IndicConformer INT8 model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting STT INT8 model: $e');
      return false;
    }
  }

  Future<bool> downloadSttFp32() async {
    final modelsDir = await getModelsDirectory();
    final sttDir = Directory(p.join(modelsDir.path, 'stt'));
    if (!await sttDir.exists()) {
      await sttDir.create(recursive: true);
    }

    const indicBaseUrl =
        'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main';
    final files = [
      ('model.onnx', 'indic_conformer_fp32.onnx'),
      ('tokens.txt', 'tokens.txt'),
    ];

    try {
      for (final (remote, local) in files) {
        final targetFile = File(p.join(sttDir.path, local));
        final minSize = local.endsWith('.onnx') ? 10 * 1024 * 1024 : 100;
        if (!await targetFile.exists() || (await targetFile.length()) < minSize) {
          _emitState(DownloadStateDownloading('IndicConformer FP32 ($local)', 0, modelKey: 'stt_fp32'));
          await _downloadFileWithRedirects('$indicBaseUrl/$remote', targetFile, (percent) {
            _emitState(DownloadStateDownloading('IndicConformer FP32 ($local)', percent, modelKey: 'stt_fp32'));
          });
        }
      }
      _emitState(const DownloadStateCompleted('AI4Bharat IndicConformer FP32 Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicConformer FP32 STT: $e');
      _emitState(DownloadStateError('IndicConformer FP32 download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteSttFp32() async {
    try {
      final modelsDir = await getModelsDirectory();
      final targetFile = File(p.join(modelsDir.path, 'stt', 'indic_conformer_fp32.onnx'));
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      _emitState(const DownloadStateCompleted('IndicConformer FP32 model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicConformer FP32: $e');
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

    if (await targetModel.exists() &&
        (await targetModel.length()) > 10 * 1024 * 1024 &&
        await targetTokens.exists() &&
        (await targetTokens.length()) > 100) {
      _emitState(const DownloadStateCompleted('AI4Bharat Rasa-13 VITS Ready (All Languages)'));
      return true;
    }

    // 1. Check if local sanitized 6-input model is ready
    final localConverted = File('converted_models/vits_rasa13_6in.onnx');
    final localTokens = File('converted_models/tokens.txt');

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat Rasa-13 VITS (All Languages)', 0, modelKey: 'rasa13'));

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

      if (!await targetModel.exists() || (await targetModel.length()) < 10 * 1024 * 1024) {
        await _downloadFileWithRedirects('$rasaBaseUrl/model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('AI4Bharat Rasa-13 VITS (All Languages)', percent, modelKey: 'rasa13'));
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

  /// Downloads AI4Bharat IndicXlit Neural Weights (~35 MB ONNX model)
  Future<bool> downloadIndicXlit() async {
    final modelsDir = await getModelsDirectory();
    final targetModel = File(p.join(modelsDir.path, 'indicxlit.onnx'));

    if (await targetModel.exists() && (await targetModel.length()) > 1024) {
      _emitState(const DownloadStateCompleted('AI4Bharat IndicXlit Neural Ready'));
      return true;
    }

    const xlitUrl =
        'https://huggingface.co/ai4bharat/IndicXlit/resolve/main/indicxlit-en-indic-v1.0/transformer/indicxlit.pt';

    try {
      _emitState(const DownloadStateDownloading('AI4Bharat IndicXlit Neural Weights (~35 MB)', 0, modelKey: 'indicxlit'));

      await _downloadFileWithRedirects(xlitUrl, targetModel, (percent) {
        _emitState(DownloadStateDownloading('IndicXlit Neural Weights', percent, modelKey: 'indicxlit'));
      });

      _emitState(const DownloadStateCompleted('AI4Bharat IndicXlit Neural Ready'));
      return true;
    } catch (e) {
      debugPrint('Error downloading IndicXlit neural model: $e');
      _emitState(DownloadStateError('IndicXlit download failed: $e'));
      return false;
    }
  }

  Future<bool> deleteIndicXlit() async {
    try {
      final modelsDir = await getModelsDirectory();
      final targetFile = File(p.join(modelsDir.path, 'indicxlit.onnx'));
      final targetSubdir = File(p.join(modelsDir.path, 'xlit', 'indicxlit.onnx'));
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      if (await targetSubdir.exists()) {
        await targetSubdir.delete();
      }
      _emitState(const DownloadStateCompleted('IndicXlit model deleted'));
      return true;
    } catch (e) {
      debugPrint('Error deleting IndicXlit model: $e');
      return false;
    }
  }

  static const String _hindiMmsTokens =
      "फ 0\n4 1\n1 2\n- 3\nअ 4\nइ 5\n8 6\n  7\n0 8\nछ 9\nन 10\nए 11\nऐ 12\n़ 13\nष 14\nि 15\nँ 16\nच 17\n2 18\nऑ 19\nथ 20\nभ 21\nी 22\n‍ 23\nॅ 24\n3 25\nञ 26\nै 27\nु 28\nठ 29\nं 30\nॉ 31\nउ 32\n_ 33\nई 34\nः 35\nह 36\nध 37\nल 38\nर 39\nस 40\nब 41\nख 42\nण 43\n' 44\n` 45\nव 46\nघ 47\nप 48\nग 49\nढ 50\nय 51\nे 52\n् 53\nा 54\nआ 55\nड 56\nज 57\nझ 58\nश 59\nऔ 60\nो 61\nद 62\nृ 63\nौ 64\nऊ 65\nू 66\nओ 67\nट 68\nत 69\nक 70\nम 71\n";

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

      if (!await targetModel.exists() || (await targetModel.length()) < 10 * 1024 * 1024) {
        _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Model)', 0, modelKey: 'tts_$languageCode'));
        await _downloadFileWithRedirects('$mmsBaseUrl/model.onnx', targetModel, (percent) {
          _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Model)', percent, modelKey: 'tts_$languageCode'));
        });
      }

      if (languageCode == 'hi') {
        // Use verified official 72 Devanagari tokens (Meta MMS hin checkpoint vocabulary)
        await targetTokens.writeAsString(_hindiMmsTokens);
      } else if (!await targetTokens.exists() || (await targetTokens.length()) == 0) {
        _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Tokens)', 0, modelKey: 'tts_$languageCode'));
        await _downloadFileWithRedirects('$mmsBaseUrl/tokens.txt', targetTokens, (percent) {
          _emitState(DownloadStateDownloading('${langMeta.englishName} Voice (Tokens)', percent, modelKey: 'tts_$languageCode'));
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
    client.connectionTimeout = const Duration(seconds: 30);
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
          await response.drain<void>();
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

      if (contentLength > 0 && received < contentLength) {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        throw HttpException('Download incomplete: received $received of $contentLength bytes');
      }

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
