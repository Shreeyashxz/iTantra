import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Language Pack Model Download URLs Verification', () {
    test('STT IndicConformer INT8 download endpoints are reachable and valid', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main/tokens.txt'),
        );
        req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
        final res = await req.close();
        // 307 redirect or 200 OK
        expect(res.statusCode == 200 || res.statusCode == 307 || res.statusCode == 302, isTrue);
      } finally {
        client.close(force: true);
      }
    });

    test('TTS MMS Hindi and English endpoints are reachable and valid', () async {
      final client = HttpClient();
      try {
        for (final iso3 in ['hin', 'eng']) {
          final req = await client.getUrl(
            Uri.parse('https://huggingface.co/willwade/mms-tts-multilingual-models-onnx/resolve/main/$iso3/tokens.txt'),
          );
          req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
          final res = await req.close();
          expect(res.statusCode == 200 || res.statusCode == 307 || res.statusCode == 302, isTrue);
        }
      } finally {
        client.close(force: true);
      }
    });

    test('MT IndicTrans2 INT8 and FP16 ONNX public endpoints are reachable and valid', () async {
      final client = HttpClient();
      try {
        final endpoints = [
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8/resolve/main/encoder_model.onnx',
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8/resolve/main/encoder_model.onnx.data',
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8/resolve/main/model.SRC',
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-fp16/resolve/main/encoder_model.onnx',
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-fp16/resolve/main/encoder_model.onnx.data',
          'https://huggingface.co/hari31416/indictrans2-indic-indic-dist-320M-ONNX-fp16/resolve/main/model.SRC',
        ];
        for (final url in endpoints) {
          final req = await client.getUrl(Uri.parse(url));
          req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
          final res = await req.close();
          expect(res.statusCode == 200 || res.statusCode == 307 || res.statusCode == 302, isTrue);
        }
      } finally {
        client.close(force: true);
      }
    });

    test('IndicLID FastText public model weights endpoint is reachable and valid', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('https://huggingface.co/ai4bharat/IndicLID-FTN/resolve/main/model_baseline_roman.bin'),
        );
        req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
        final res = await req.close();
        expect(res.statusCode == 200 || res.statusCode == 307 || res.statusCode == 302, isTrue);
      } finally {
        client.close(force: true);
      }
    });

    test('IndicXlit public model weights endpoint is reachable and valid', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('https://huggingface.co/ai4bharat/IndicXlit/resolve/main/indicxlit-en-indic-v1.0/transformer/indicxlit.pt'),
        );
        req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Mobile; Android)');
        final res = await req.close();
        expect(res.statusCode == 200 || res.statusCode == 307 || res.statusCode == 302, isTrue);
      } finally {
        client.close(force: true);
      }
    });
  });
}
