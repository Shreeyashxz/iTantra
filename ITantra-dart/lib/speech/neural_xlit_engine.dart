import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Genuine on-device neural transliteration runtime for AI4Bharat IndicXlit.
///
/// Unlike the previous placeholder (which downloaded Fairseq `indicxlit.pt`
/// and renamed it to `.onnx` without inference), this engine:
///
/// 1. Loads a real encoder+decoder ONNX bundle from
///    `<models>/xlit/int8/` (produced by `scripts/export_indicxlit_onnx.py`).
/// 2. Runs autoregressive Transformer inference via `flutter_onnxruntime`
///    (Android `.so`, no Windows binaries).
/// 3. Reports [isReady]==true ONLY when OrtSessions actually exist.
///    Callers must use the rule-based fallback otherwise and say so in UI.
///
/// Bundle layout expected:
///   models/xlit/int8/encoder_model.onnx
///   models/xlit/int8/decoder_model.onnx
///   models/xlit/int8/vocab.json (char vocab: {"token": id})
class NeuralXlitEngine {
  static final NeuralXlitEngine instance = NeuralXlitEngine._internal();
  NeuralXlitEngine._internal();

  final OnnxRuntime _ort = OnnxRuntime();

  OrtSession? _encoder;
  OrtSession? _decoder;
  String _bundleDir = '';
  String get bundleDir => _bundleDir;

  Map<String, int> _vocabToId = {};
  Map<int, String> _idToVocab = {};

  bool get isReady => _encoder != null && _decoder != null;

  static const int bosId = 0;
  static const int eosId = 2;
  static const int unkId = 3;

  Future<Directory?> _resolveBundleDir([String? baseDir]) async {
    final String root;
    if (baseDir != null) {
      root = baseDir;
    } else {
      root = (await getApplicationSupportDirectory()).path;
    }
    final candidates = [
      Directory(p.join(root, 'models', 'xlit', 'int8')),
      Directory(p.join(root, 'models', 'xlit')),
    ];
    for (final d in candidates) {
      final enc = File(p.join(d.path, 'encoder_model.onnx'));
      final dec = File(p.join(d.path, 'decoder_model.onnx'));
      if (await enc.exists() && await dec.exists()) return d;
    }
    return null;
  }

  Future<bool> _loadVocab(Directory dir) async {
    try {
      final candidates = [
        File(p.join(dir.path, 'vocab.json')),
        File(p.join(dir.path, 'dict.json')),
        File(p.join(dir.path, 'tokenizer.json')),
      ];
      for (final f in candidates) {
        if (await f.exists() && (await f.length()) > 10) {
          final text = await f.readAsString();
          // Minimal JSON parse without dart:convert dependency issues: use manual?
          // dart:convert is available transitively; import locally to avoid header change.
          final decoded = _decodeJsonMap(text);
          if (decoded.length > 20) {
            _vocabToId = decoded;
            _idToVocab = {for (final e in decoded.entries) e.value: e.key};
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[NeuralXlit] vocab load failed: $e');
    }
    // Fallback: byte-level vocab so encode/decode never crashes;
    // inference still requires real ONNX sessions to be meaningful.
    _vocabToId = {'<s>': 0, '<pad>': 1, '</s>': 2, '<unk>': 3};
    _idToVocab = {0: '<s>', 1: '<pad>', 2: '</s>', 3: '<unk>'};
    return false;
  }

  Map<String, int> _decodeJsonMap(String text) {
    final out = <String, int>{};
    // Very small tolerant parser for {"tok": id} flat maps.
    final tokenReg = RegExp(r'"((?:[^"\\]|\\.)*)"\s*:\s*(\d+)');
    for (final m in tokenReg.allMatches(text)) {
      final key = m.group(1)!;
      final val = int.tryParse(m.group(2)!);
      if (val != null) out[key] = val;
    }
    return out;
  }

  /// Creates real OrtSessions. Returns true only when inference can run.
  Future<bool> init([String? baseDir]) async {
    try {
      await unload();
      final dir = await _resolveBundleDir(baseDir);
      if (dir == null) {
        debugPrint('[NeuralXlit] no ONNX bundle found; neural OFF, fallback active');
        return false;
      }
      final encPath = p.join(dir.path, 'encoder_model.onnx');
      final decPath = p.join(dir.path, 'decoder_model.onnx');
      debugPrint('[NeuralXlit] loading encoder: $encPath');
      _encoder = await _ort.createSession(encPath);
      debugPrint('[NeuralXlit] loading decoder: $decPath');
      _decoder = await _ort.createSession(decPath);
      await _loadVocab(dir);
      _bundleDir = dir.path;
      debugPrint('[NeuralXlit] neural READY (${dir.path})');
      return true;
    } catch (e) {
      debugPrint('[NeuralXlit] init failed (neural OFF): $e');
      await unload();
      return false;
    }
  }

  List<int> encodeChars(String text) {
    final ids = <int>[];
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      ids.add(_vocabToId[ch] ?? _vocabToId['<unk>'] ?? unkId);
    }
    return ids.isEmpty ? [eosId] : ids;
  }

  String decodeIds(List<int> ids) {
    final sb = StringBuffer();
    for (final id in ids) {
      if (id == bosId || id == eosId || id == 1) continue;
      final tok = _idToVocab[id];
      if (tok == null || tok == '<unk>') continue;
      if (tok.startsWith('<') && tok.endsWith('>')) continue;
      sb.write(tok);
    }
    return sb.toString();
  }

  /// Runs encoder-decoder transliteration. Returns null when neural is
  /// unavailable so callers fall back honestly.
  Future<String?> transliterate({
    required String text,
    int maxNewTokens = 32,
  }) async {
    if (!isReady) return null;
    final clean = text.trim();
    if (clean.isEmpty) return '';
    try {
      final inputIds = encodeChars(clean);
      final seqLen = inputIds.length;
      final inputTensor = await OrtValue.fromList(inputIds, [1, seqLen]);
      final mask = List<int>.filled(seqLen, 1);
      final maskTensor = await OrtValue.fromList(mask, [1, seqLen]);

      final encOut = await _encoder!.run({
        'input_ids': inputTensor,
        'attention_mask': maskTensor,
      });
      final hidden = encOut['last_hidden_state'] ?? encOut.values.first;

      final generated = <int>[bosId];
      for (int step = 0; step < maxNewTokens; step++) {
        final decIn = await OrtValue.fromList(generated, [1, generated.length]);
        final decOut = await _decoder!.run({
          'input_ids': decIn,
          'encoder_hidden_states': hidden,
          'encoder_attention_mask': maskTensor,
        });
        final logits = decOut['logits'] ?? decOut.values.first;
        final flat = await logits.asFlattenedList();
        await decIn.dispose();
        final vocabSize = flat.length ~/ generated.length;
        if (vocabSize <= 0) break;
        final off = (generated.length - 1) * vocabSize;
        int best = 0;
        double bestV = -double.infinity;
        for (int v = 0; v < vocabSize; v++) {
          final val = (flat[off + v] as num).toDouble();
          if (val > bestV) {
            bestV = val;
            best = v;
          }
        }
        generated.add(best);
        if (best == eosId) break;
      }

      await inputTensor.dispose();
      await maskTensor.dispose();
      await hidden.dispose();
      return decodeIds(generated);
    } catch (e) {
      debugPrint('[NeuralXlit] inference failed: $e');
      return null;
    }
  }

  Future<void> unload() async {
    try {
      await _encoder?.close();
      await _decoder?.close();
    } catch (_) {}
    _encoder = null;
    _decoder = null;
    _bundleDir = '';
  }
}
