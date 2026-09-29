import 'dart:async';
import 'package:flutter/foundation.dart';

// NOTE: flutter_onnxruntime has been commented out to eliminate binary collisions
// with sherpa_onnx (which powers STT, TTS, and VAD). Neural Xlit defaults to
// offline high-speed phonological rule-based transliteration.

class NeuralXlitEngine {
  static final NeuralXlitEngine instance = NeuralXlitEngine._internal();
  NeuralXlitEngine._internal();

  bool get isReady => false;
  bool get smokeOk => false;
  String get smokeDetail => 'Neural Xlit commented out (rule-based phonological engine active)';
  String get bundleDir => '';

  Future<bool> init([String? baseDir]) async {
    debugPrint('[NeuralXlit] Neural Xlit commented out — using rule-based phonological engine');
    return false;
  }

  Future<String?> transliterate({required String text}) async {
    // Return null to allow IndicXlitEngine to fall back to rule-based phonological engine
    return null;
  }

  Future<void> unload() async {}
}

/*
class _NeuralXlitEngineOriginalOnnx {


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
  /// Single-flight: concurrent toggles share one load. On success a smoke
  /// transliteration (`namaste`) is run immediately so a first run with a real
  /// bundle is verified, not assumed — failures unload and report fallback.
  Future<bool> init([String? baseDir]) async {
    final completer = Completer<bool>();
    final prev = _initLock;
    _initLock = completer.future.then((_) {}, onError: (_) {});
    await prev;
    try {
      final ok = await _initInner(baseDir);
      completer.complete(ok);
      return ok;
    } catch (e) {
      debugPrint('[NeuralXlit] init failed (neural OFF): $e');
      await unload();
      completer.complete(false);
      return false;
    }
  }

  Future<bool> _initInner([String? baseDir]) async {
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
      try {
        _decoder = await _ort.createSession(decPath);
      } catch (e) {
        // Don't leak the encoder session when the decoder fails.
        try {
          await _encoder?.close();
        } catch (_) {}
        _encoder = null;
        rethrow;
      }
      final vocabOk = await _loadVocab(dir);
      if (!vocabOk) {
        debugPrint('[NeuralXlit] vocab missing/invalid; neural OFF (4-token fallback would blank output)');
        await unload();
        return false;
      }
      _bundleDir = dir.path;
      // Smoke test: first run with a real bundle must prove inference works.
      final smoke = await _transliterateInner(text: 'namaste', maxNewTokens: 8);
      if (smoke == null || smoke.trim().isEmpty) {
        _smokeDetail = 'sessions created but smoke transliteration returned empty';
        debugPrint('[NeuralXlit] smoke test FAILED; unloading (fallback active)');
        await unload();
        return false;
      }
      _smokeOk = true;
      _smokeDetail = 'smoke: namaste -> $smoke';
      debugPrint('[NeuralXlit] neural READY (${dir.path}); $_smokeDetail');
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
    final completer = Completer<String?>();
    final prev = _lock;
    _lock = completer.future.then((_) {}, onError: (_) {});
    await prev;
    try {
      final res = await _transliterateInner(text: text, maxNewTokens: maxNewTokens);
      completer.complete(res);
      return res;
    } catch (_) {
      completer.complete(null);
      return null;
    }
  }

  Future<String?> _transliterateInner({
    required String text,
    int maxNewTokens = 32,
  }) async {
    if (!isReady) return null;
    final clean = text.trim();
    if (clean.isEmpty) return '';
    // Bound input — encoder is O(n²).
    final bounded = clean.length > 128 ? clean.substring(0, 128) : clean;
    // Feed contract MUST match scripts/export_indicxlit_onnx.py:
    //   encoder: input_ids[int64](1, seq) + src_lengths[int64](1) -> last_hidden_state
    //   decoder: input_ids(1, tgt) + encoder_hidden_states -> logits
    // (No attention_mask anywhere — the script never exports one; sending
    // undeclared inputs makes ORT throw on first run.)
    OrtValue? inputTensor;
    OrtValue? lengthsTensor;
    OrtValue? hidden;
    try {
      final inputIds = encodeChars(bounded);
      final seqLen = inputIds.length;
      inputTensor = await OrtValue.fromList(inputIds, [1, seqLen]);
      lengthsTensor = await OrtValue.fromList([seqLen], [1]);

      final encOut = await _encoder!.run({
        'input_ids': inputTensor,
        'src_lengths': lengthsTensor,
      });
      hidden = encOut['last_hidden_state'] ?? encOut.values.first;
      // Dispose encoder aux outputs (keep hidden).
      for (final entry in encOut.entries) {
        if (entry.key == 'last_hidden_state') continue;
        try {
          await entry.value.dispose();
        } catch (_) {}
      }

      final generated = <int>[bosId];
      for (int step = 0; step < maxNewTokens; step++) {
        final decIn = await OrtValue.fromList(generated, [1, generated.length]);
        final decOut = await _decoder!.run({
          'input_ids': decIn,
          'encoder_hidden_states': hidden,
        });
        final logits = decOut['logits'] ?? decOut.values.first;
        final flat = await logits.asFlattenedList();
        await decIn.dispose();
        for (final v in decOut.values) {
          try {
            await v.dispose();
          } catch (_) {}
        }
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

      return decodeIds(generated);
    } catch (e) {
      debugPrint('[NeuralXlit] inference failed: $e');
      return null;
    } finally {
      try {
        await inputTensor?.dispose();
      } catch (_) {}
      try {
        await lengthsTensor?.dispose();
      } catch (_) {}
      // hidden is an OrtValue from encOut — dispose after decode.
      try {
        await hidden?.dispose();
      } catch (_) {}
    }
  }

  Future<void> unload() async {
    _smokeOk = false;
    _smokeDetail = '';
    try {
      await _encoder?.close();
      await _decoder?.close();
    } catch (_) {}
    _encoder = null;
    _decoder = null;
    _bundleDir = '';
  }
}
*/

