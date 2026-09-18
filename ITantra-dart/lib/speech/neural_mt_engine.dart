import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'indic_bpe_tokenizer.dart';
import 'script_normalization_engine.dart';

/// Authentic On-Device Neural Machine Translation (NMT) Engine
/// for AI4Bharat IndicTrans2 quantized models.
///
/// Features:
/// 1. Standalone ONNX Runtime inference using `flutter_onnxruntime` (single native runtime).
/// 2. Executes Seq2Seq Transformer Encoder + Decoder graphs.
/// 3. Autoregressive greedy token generation with EOS stopping.
/// 4. Ties seamlessly with [IndicBpeTokenizer] for input tensor encoding and output detokenization.
/// 5. Automatically post-processes output from unified Devanagari space into the target Indic script.
class _MtSessionBundle {
  final String name;
  final Directory directory;
  final OrtSession encoder;
  final OrtSession decoder;
  final OrtSession? decoderPast;
  final IndicBpeTokenizer tokenizer;

  _MtSessionBundle({
    required this.name,
    required this.directory,
    required this.encoder,
    required this.decoder,
    this.decoderPast,
    required this.tokenizer,
  });

  Future<void> dispose() async {
    try {
      await encoder.close();
      await decoder.close();
      if (decoderPast != null) {
        await decoderPast!.close();
      }
    } catch (e) {
      debugPrint('[_MtSessionBundle] Error during dispose: $e');
    }
  }
}

/// Authentic On-Device Neural Machine Translation (NMT) Engine
/// for AI4Bharat IndicTrans2 quantized models.
///
/// Features:
/// 1. Standalone ONNX Runtime inference using `flutter_onnxruntime` (single native runtime).
/// 2. Dual-bundle support:
///    - Indic ➔ Indic (320M INT8): `hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8`
///    - Indic ➔ English (200M INT8): `hari31416/indictrans2-indic-en-dist-200M-ONNX-int8`
/// 3. Executes Seq2Seq Transformer Encoder + Decoder graphs.
/// 4. Autoregressive greedy token generation with EOS stopping.
/// 5. Ties seamlessly with [IndicBpeTokenizer] for input tensor encoding and output detokenization.
/// 6. Automatically post-processes output from unified Devanagari space into the target Indic script.
class NeuralMtEngine {
  static final NeuralMtEngine instance = NeuralMtEngine._internal();
  NeuralMtEngine._internal();

  final OnnxRuntime _ort = OnnxRuntime();

  _MtSessionBundle? _indicIndicBundle;
  _MtSessionBundle? _indicEnBundle;

  bool get isReady => _indicIndicBundle != null || _indicEnBundle != null;
  bool get isIndicIndicReady => _indicIndicBundle != null;
  bool get isIndicEnReady => _indicEnBundle != null;

  String _loadedModelName = '';
  String get loadedModelName => _loadedModelName;

  final int _decoderStartId = 2;
  final int _eosId = IndicBpeTokenizer.eosId;

  IndicBpeTokenizer get tokenizer =>
      _indicIndicBundle?.tokenizer ?? _indicEnBundle?.tokenizer ?? IndicBpeTokenizer.instance;

  Future<_MtSessionBundle?> _loadBundleFromDir(Directory dir, String modelName) async {
    if (!await dir.exists()) return null;
    final enc = File(p.join(dir.path, 'encoder_model.onnx'));
    final dec = File(p.join(dir.path, 'decoder_model.onnx'));
    if (!await enc.exists() || !await dec.exists()) return null;

    debugPrint('[NeuralMtEngine] Loading $modelName ONNX encoder: ${enc.path}');
    final encSession = await _ort.createSession(enc.path);

    debugPrint('[NeuralMtEngine] Loading $modelName ONNX decoder: ${dec.path}');
    final decSession = await _ort.createSession(dec.path);

    OrtSession? pastSession;
    final past = File(p.join(dir.path, 'decoder_with_past_model.onnx'));
    if (await past.exists()) {
      try {
        pastSession = await _ort.createSession(past.path);
      } catch (e) {
        debugPrint('[NeuralMtEngine] Optional past decoder skipped: $e');
      }
    }

    final tokenizer = IndicBpeTokenizer();
    await tokenizer.init(dir.path);

    return _MtSessionBundle(
      name: modelName,
      directory: dir,
      encoder: encSession,
      decoder: decSession,
      decoderPast: pastSession,
      tokenizer: tokenizer,
    );
  }

  /// Initializes ONNX Runtime sessions from local storage if model files exist.
  Future<bool> init([String? baseDir]) async {
    try {
      final String modelsDirPath;
      if (baseDir != null) {
        modelsDirPath = baseDir;
      } else {
        final docDir = await getApplicationSupportDirectory();
        modelsDirPath = docDir.path;
      }

      await unload();

      // 1. Check Indic-to-Indic (320M INT8)
      final indicIndicDir = Directory(p.join(modelsDirPath, 'models', 'mt', 'indic_indic', 'int8'));
      final legacyInt8Dir = Directory(p.join(modelsDirPath, 'models', 'mt', 'int8'));
      final legacyMtDir = Directory(p.join(modelsDirPath, 'models', 'mt'));

      if (await indicIndicDir.exists()) {
        _indicIndicBundle = await _loadBundleFromDir(indicIndicDir, 'indictrans2-indic-indic-dist-320M-ONNX-int8');
      } else if (await legacyInt8Dir.exists()) {
        _indicIndicBundle = await _loadBundleFromDir(legacyInt8Dir, 'indictrans2-int8-legacy');
      } else if (await legacyMtDir.exists()) {
        _indicIndicBundle = await _loadBundleFromDir(legacyMtDir, 'indictrans2-legacy');
      }

      // 2. Check Indic-to-English (200M INT8)
      final indicEnDir = Directory(p.join(modelsDirPath, 'models', 'mt', 'indic_en', 'int8'));
      if (await indicEnDir.exists()) {
        _indicEnBundle = await _loadBundleFromDir(indicEnDir, 'indictrans2-indic-en-dist-200M-ONNX-int8');
      }

      final ready = isReady;
      if (ready) {
        final active = [
          if (_indicIndicBundle != null) 'Indic-Indic (320M)',
          if (_indicEnBundle != null) 'Indic-En (200M)',
        ];
        _loadedModelName = active.join(' + ');
        debugPrint('[NeuralMtEngine] Neural Seq2Seq MT engine successfully initialized: $_loadedModelName');
      } else {
        debugPrint('[NeuralMtEngine] No complete Encoder+Decoder ONNX bundle found in $modelsDirPath');
      }
      return ready;
    } catch (e) {
      debugPrint('[NeuralMtEngine] Failed to initialize neural MT engine: $e');
      return false;
    }
  }

  /// Translates [text] from [sourceLang] to [targetLang] using on-device ONNX inference.
  ///
  /// Routes requests to Indic-to-English model when `targetLang == 'en'`,
  /// and to Indic-to-Indic model for cross-Indic translations.
  ///
  /// Returns `null` if the neural model is not loaded, allowing caller to fall back
  /// to tactical lexicon or phonological transliteration.
  Future<String?> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
    int maxNewTokens = 64,
  }) async {
    if (!isReady) {
      return null;
    }

    final clean = text.trim();
    if (clean.isEmpty) return '';

    try {
      final src = sourceLang.toLowerCase();
      final tgt = targetLang.toLowerCase();

      // Select optimal model bundle based on target language
      final _MtSessionBundle? bundle;
      if (tgt == 'en') {
        bundle = _indicEnBundle ?? _indicIndicBundle;
      } else {
        bundle = _indicIndicBundle ?? _indicEnBundle;
      }

      if (bundle == null) return null;

      // 1. Preprocess source text into normalized Devanagari representation for IndicTrans2
      final preprocessed = ScriptNormalizationEngine.prepareTextForMt(clean, src);

      // 2. Tokenize with target language tag prefix at position 0
      final tokenIds = bundle.tokenizer.encode(
        text: preprocessed,
        sourceLang: src,
        targetLang: tgt,
      );

      if (tokenIds.isEmpty) return clean;

      // 3. Prepare Encoder Tensors
      final seqLen = tokenIds.length;
      final inputIdsTensor = await OrtValue.fromList(tokenIds, [1, seqLen]);
      final attentionMask = List<int>.filled(seqLen, 1);
      final attnMaskTensor = await OrtValue.fromList(attentionMask, [1, seqLen]);

      // 4. Run Encoder Graph
      final encOutputs = await bundle.encoder.run({
        'input_ids': inputIdsTensor,
        'attention_mask': attnMaskTensor,
      });

      final lastHiddenState = encOutputs['last_hidden_state'];
      if (lastHiddenState == null) {
        throw StateError('Encoder did not return last_hidden_state');
      }

      // 5. Autoregressive Greedy Decoder Generation Loop
      final generatedTokenIds = <int>[_decoderStartId];
      final targetScript = ScriptNormalizationEngine.expectedScriptForLanguage(tgt);

      for (int step = 0; step < maxNewTokens; step++) {
        final decInputTensor = await OrtValue.fromList(
          generatedTokenIds,
          [1, generatedTokenIds.length],
        );

        final decOutputs = await bundle.decoder.run({
          'input_ids': decInputTensor,
          'encoder_hidden_states': lastHiddenState,
          'encoder_attention_mask': attnMaskTensor,
        });

        // The first output is logits: shape [batch=1, seq_len, vocab_size]
        final logitsValue = decOutputs['logits'] ?? decOutputs.values.first;
        final logitsFlat = await logitsValue.asFlattenedList();

        await decInputTensor.dispose();

        // Extract argmax over the vocabulary for the last token position
        final vocabSize = logitsFlat.length ~/ generatedTokenIds.length;
        if (vocabSize <= 0) break;

        final lastTokenOffset = (generatedTokenIds.length - 1) * vocabSize;
        int bestId = 0;
        double bestLogit = -double.infinity;

        for (int v = 0; v < vocabSize; v++) {
          final val = (logitsFlat[lastTokenOffset + v] as num).toDouble();
          if (val > bestLogit) {
            bestLogit = val;
            bestId = v;
          }
        }

        generatedTokenIds.add(bestId);

        // Stop generation on EOS
        if (bestId == _eosId || bestId == IndicBpeTokenizer.eosId) {
          break;
        }
      }

      // Cleanup encoder tensors
      await inputIdsTensor.dispose();
      await attnMaskTensor.dispose();
      await lastHiddenState.dispose();

      // 6. Detokenize generated token sequence
      final rawDecoded = bundle.tokenizer.decode(generatedTokenIds, targetLang: tgt);

      // 7. Post-process from unified Devanagari space back into the target Indic script
      if (tgt != 'hi' && tgt != 'mr' && tgt != 'en') {
        final finalScriptText = ScriptNormalizationEngine.fromDevanagariToIndic(
          rawDecoded,
          targetScript,
        );
        return finalScriptText;
      }

      return rawDecoded;
    } catch (e) {
      debugPrint('[NeuralMtEngine] Inference exception: $e');
      return null;
    }
  }

  /// Closes all active ONNX Runtime inference sessions and reclaims native memory
  Future<void> unload() async {
    try {
      if (_indicIndicBundle != null) {
        await _indicIndicBundle!.dispose();
        _indicIndicBundle = null;
      }
      if (_indicEnBundle != null) {
        await _indicEnBundle!.dispose();
        _indicEnBundle = null;
      }
    } catch (e) {
      debugPrint('[NeuralMtEngine] Error during session unload: $e');
    } finally {
      _loadedModelName = '';
    }
  }
}
