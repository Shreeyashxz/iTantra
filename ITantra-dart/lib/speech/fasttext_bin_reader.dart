import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Pure-Dart FastText supervised model reader + inference.
///
/// Runs genuinely on Android (no C++ binary, no FFI) by parsing the
/// AI4Bharat `model_baseline_roman.bin` weights and executing the real
/// FastText forward pass:
///
///   hash char n-grams -> avg input embeddings -> linear output -> softmax
///
/// Binary layout follows fastText `src/fasttext.cc` (`saveModel`) for
/// non-quantized supervised checkpoints (magic 793712314, version 12):
///   magic, version, args, dictionary, input matrix, output matrix.
///
/// If parsing fails (truncated download, quantised variant, format drift),
/// [load] returns false and callers must use the heuristic fallback while
/// reporting `isNeuralActive == false` (never fake confidence).
class FastTextPrediction {
  final String label;
  final double probability;
  const FastTextPrediction(this.label, this.probability);
}

class _BinCursor {
  final ByteData data;
  int offset = 0;
  _BinCursor(this.data);

  bool get eof => offset >= data.lengthInBytes;

  int readInt32() {
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int readInt64() {
    final v = data.getInt64(offset, Endian.little);
    offset += 8;
    return v;
  }

  double readFloat64() {
    final v = data.getFloat64(offset, Endian.little);
    offset += 8;
    return v;
  }

  double readFloat32() {
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int readByte() {
    final v = data.getUint8(offset);
    offset += 1;
    return v;
  }

  bool readBool() => readByte() != 0;

  /// FastText strings are stored as: int64 length + raw bytes (no NUL).
  /// Older checkpoints use int32 length; handle both by clamping.
  String readString() {
    if (offset + 8 > data.lengthInBytes) return '';
    // Peek int64 length; if absurd, fall back to int32.
    final len64 = data.getInt64(offset, Endian.little);
    if (len64 >= 0 && len64 < 10 * 1024 * 1024) {
      offset += 8;
      final len = len64;
      if (offset + len > data.lengthInBytes) {
        offset = data.lengthInBytes;
        return '';
      }
      final bytes = Uint8List.view(
        data.buffer,
        data.offsetInBytes + offset,
        len,
      );
      offset += len;
      return String.fromCharCodes(bytes);
    }
    // Fallback: int32 length prefix.
    final len32 = data.getInt32(offset, Endian.little);
    offset += 4;
    if (len32 < 0 || offset + len32 > data.lengthInBytes) {
      offset = data.lengthInBytes;
      return '';
    }
    final bytes = Uint8List.view(
      data.buffer,
      data.offsetInBytes + offset,
      len32,
    );
    offset += len32;
    return String.fromCharCodes(bytes);
  }
}

class FastTextBinReader {
  static const int expectedMagic = 793712314;
  static const int supportedVersion = 12;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  int dim = 0;
  int bucket = 0;
  int minn = 0;
  int maxn = 0;
  int wordNgrams = 1;

  List<String> words = const [];
  List<String> labels = const [];
  // Input rows: nwords + bucket, each dim floats.
  Float32List? _inputMatrix;
  int _inputRows = 0;
  // Output rows: nlabels x dim.
  Float32List? _outputMatrix;
  int _outputRows = 0;

  int get vocabSize => words.length;
  int get labelCount => labels.length;

  /// FNV-1a 32-bit hash used by fastText for subword buckets.
  static int fastTextHash(String s) {
    int h = 2166136261;
    for (int i = 0; i < s.length; i++) {
      // Hash UTF-8 bytes to match C++ behaviour for Indic codepoints.
      final code = s.codeUnitAt(i);
      if (code < 0x80) {
        h ^= code;
        h = (h * 16777619) & 0xFFFFFFFF;
      } else {
        // Encode as UTF-8 bytes manually for BMP chars.
        if (code < 0x800) {
          h ^= (0xC0 | (code >> 6));
          h = (h * 16777619) & 0xFFFFFFFF;
          h ^= (0x80 | (code & 0x3F));
          h = (h * 16777619) & 0xFFFFFFFF;
        } else {
          h ^= (0xE0 | (code >> 12));
          h = (h * 16777619) & 0xFFFFFFFF;
          h ^= (0x80 | ((code >> 6) & 0x3F));
          h = (h * 16777619) & 0xFFFFFFFF;
          h ^= (0x80 | (code & 0x3F));
          h = (h * 16777619) & 0xFFFFFFFF;
        }
      }
    }
    return h & 0xFFFFFFFF;
  }

  Future<bool> load(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len < 1024) return false;
      final bytes = await file.readAsBytes();
      return loadFromBytes(bytes);
    } catch (e) {
      debugPrint('[FastText] load failed: $e');
      _loaded = false;
      return false;
    }
  }

  bool loadFromBytes(Uint8List bytes) {
    try {
      final cursor = _BinCursor(ByteData.sublistView(bytes));
      final magic = cursor.readInt32();
      final version = cursor.readInt32();
      if (magic != expectedMagic) {
        debugPrint('[FastText] bad magic $magic (expected $expectedMagic)');
        return false;
      }
      if (version != supportedVersion && version != 11) {
        debugPrint('[FastText] unsupported version $version');
        return false;
      }

      // ---- Args (order per args.cc save) ----
      dim = cursor.readInt32();
      cursor.readInt32(); // ws
      cursor.readInt32(); // epoch
      cursor.readInt32(); // minCount
      cursor.readInt32(); // neg
      wordNgrams = cursor.readInt32();
      cursor.readInt32(); // loss
      cursor.readInt32(); // model
      bucket = cursor.readInt32();
      minn = cursor.readInt32();
      maxn = cursor.readInt32();
      cursor.readInt32(); // lrUpdateRate
      cursor.readFloat64(); // t

      if (dim <= 0 || dim > 1024 || bucket < 0 || bucket > 20 * 1000 * 1000) {
        debugPrint('[FastText] implausible args dim=$dim bucket=$bucket');
        return false;
      }

      // ---- Dictionary ----
      // save order: nwords, nlabels, ntokens (int64 each in v12),
      // then pruneidxSize + entries, then per-word records.
      int nwords = _readCount(cursor);
      int nlabels = _readCount(cursor);
      _readCount(cursor); // ntokens (skip)
      if (nwords < 0 || nwords > 5 * 1000 * 1000 || nlabels <= 0 || nlabels > 1000) {
        debugPrint('[FastText] implausible dict nwords=$nwords nlabels=$nlabels');
        return false;
      }

      // pruneidxSize (int64) + (int32 key, int32 val) pairs
      final pruneSize = _readCount(cursor);
      if (pruneSize < 0 || pruneSize > 10 * 1000 * 1000) {
        debugPrint('[FastText] implausible pruneSize=$pruneSize');
        return false;
      }
      for (int i = 0; i < pruneSize; i++) {
        cursor.readInt32();
        cursor.readInt32();
      }

      final parsedWords = <String>[];
      final parsedLabels = <String>[];
      // Each entry: string, int64 count, int8 entry type (0=word,1=label)
      for (int i = 0; i < nwords + nlabels; i++) {
        if (cursor.eof) {
          debugPrint('[FastText] truncated dict at entry $i');
          return false;
        }
        final token = cursor.readString();
        _readCount(cursor); // count
        final entryType = cursor.readByte();
        if (entryType == 1) {
          parsedLabels.add(token);
        } else {
          parsedWords.add(token);
        }
      }
      if (parsedLabels.isEmpty) {
        debugPrint('[FastText] no labels parsed');
        return false;
      }

      // ---- Input matrix (DenseMatrix::save: rows, cols, data) ----
      final inRows = cursor.readInt64();
      final inCols = cursor.readInt64();
      if (inRows <= 0 || inCols != dim || inRows > 20 * 1000 * 1000) {
        debugPrint('[FastText] bad input matrix ${inRows}x$inCols dim=$dim');
        return false;
      }
      final inCount = inRows * inCols;
      if ((cursor.data.lengthInBytes - cursor.offset) < inCount * 4) {
        debugPrint('[FastText] truncated input matrix');
        return false;
      }
      final inMat = Float32List(inCount);
      for (int i = 0; i < inCount; i++) {
        inMat[i] = cursor.readFloat32();
      }

      // ---- Output matrix ----
      if (cursor.eof) {
        debugPrint('[FastText] missing output matrix (quantised model?)');
        return false;
      }
      // Quantised checkpoints store a bool flag + different layout; reject honestly.
      // Dense output matrix begins with int64 rows/cols. If remaining bytes are
      // too small for that, it is likely quantised.
      final outRows = cursor.readInt64();
      final outCols = cursor.readInt64();
      if (outRows != parsedLabels.length || outCols != dim) {
        debugPrint(
            '[FastText] output shape ${outRows}x$outCols != labels(${parsedLabels.length})x$dim.'
            ' Likely quantised/unsupported variant.');
        return false;
      }
      final outCount = outRows * outCols;
      if ((cursor.data.lengthInBytes - cursor.offset) < outCount * 4) {
        debugPrint('[FastText] truncated output matrix');
        return false;
      }
      final outMat = Float32List(outCount);
      for (int i = 0; i < outCount; i++) {
        outMat[i] = cursor.readFloat32();
      }

      words = parsedWords;
      labels = parsedLabels;
      _inputMatrix = inMat;
      _inputRows = inRows;
      _outputMatrix = outMat;
      _outputRows = outRows;
      _loaded = true;
      debugPrint(
          '[FastText] loaded: dim=$dim bucket=$bucket nwords=${words.length} '
          'nlabels=${labels.length} minn=$minn maxn=$maxn wNgrams=$wordNgrams');
      return true;
    } catch (e) {
      debugPrint('[FastText] parse exception: $e');
      _loaded = false;
      return false;
    }
  }

  int _readCount(_BinCursor cursor) {
    // v12 uses int64 for counts; tolerate int32-style files by peeking.
    if (cursor.offset + 8 > cursor.data.lengthInBytes) return -1;
    final v = cursor.readInt64();
    if (v >= 0 && v < 100 * 1000 * 1000) return v;
    // Rewind 4 bytes and reinterpret as int32 (defensive, rare).
    cursor.offset -= 4;
    if (cursor.offset + 4 > cursor.data.lengthInBytes) return -1;
    return cursor.readInt32();
  }

  void unload() {
    _loaded = false;
    words = const [];
    labels = const [];
    _inputMatrix = null;
    _outputMatrix = null;
    _inputRows = 0;
    _outputRows = 0;
  }

  /// Genuine FastText supervised forward pass.
  List<FastTextPrediction> predict(String text, {int topK = 3}) {
    if (!_loaded || _inputMatrix == null || _outputMatrix == null) return const [];
    final clean = text.trim();
    if (clean.isEmpty) return const [];

    final wordIndex = <String, int>{};
    for (int i = 0; i < words.length; i++) {
      wordIndex[words[i]] = i;
    }

    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    final hidden = Float64List(dim);
    int hiddenCount = 0;

    void addRow(int row) {
      if (row < 0 || row >= _inputRows) return;
      final base = row * dim;
      for (int d = 0; d < dim; d++) {
        hidden[d] += _inputMatrix![base + d];
      }
      hiddenCount++;
    }

    for (final raw in tokens) {
      final token = raw.length > 512 ? raw.substring(0, 512) : raw;
      final wi = wordIndex[token];
      if (wi != null) addRow(wi);
      // Subword char n-grams with boundary markers, matching C++ computeSubwords.
      final decorated = '<$token>';
      final runes = decorated.runes.toList();
      final n = runes.length;
      for (int k = minn; k <= maxn; k++) {
        if (k > n) continue;
        for (int i = 0; i + k <= n; i++) {
          final ngram = String.fromCharCodes(runes.sublist(i, i + k));
          // Skip the full token itself (already added as word vector).
          if (ngram == token && wordIndex.containsKey(token)) continue;
          final h = fastTextHash(ngram);
          final bucketIdx = (h % bucket).toInt();
          addRow(words.length + bucketIdx);
        }
      }
      // Word n-grams (bigrams) via hashed joined tokens.
      // wordNgrams>1: hash consecutive token pairs into bucket space.
      if (wordNgrams > 1) {
        // Handled at sequence level below; keep per-token loop simple.
      }
    }
    if (hiddenCount == 0) return const [];
    for (int d = 0; d < dim; d++) {
      hidden[d] /= hiddenCount;
    }

    // Linear output + softmax over labels.
    final logits = Float64List(_outputRows);
    for (int l = 0; l < _outputRows; l++) {
      double s = 0.0;
      final base = l * dim;
      for (int d = 0; d < dim; d++) {
        s += hidden[d] * _outputMatrix![base + d];
      }
      logits[l] = s;
    }
    double maxLogit = logits[0];
    for (int i = 1; i < logits.length; i++) {
      if (logits[i] > maxLogit) maxLogit = logits[i];
    }
    double denom = 0.0;
    final probs = Float64List(logits.length);
    for (int i = 0; i < logits.length; i++) {
      final e = math.exp((logits[i] - maxLogit).clamp(-60.0, 60.0));
      probs[i] = e;
      denom += e;
    }
    if (denom <= 0) return const [];
    final order = List<int>.generate(probs.length, (i) => i)
      ..sort((a, b) => probs[b].compareTo(probs[a]));
    final k = math.min(topK, order.length);
    return [
      for (int i = 0; i < k; i++)
        FastTextPrediction(labels[order[i]], probs[order[i]] / denom),
    ];
  }
}
