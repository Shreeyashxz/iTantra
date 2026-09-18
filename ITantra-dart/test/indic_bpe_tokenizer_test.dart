import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/speech/indic_bpe_tokenizer.dart';
import 'package:itantra_dart/speech/indic_trans_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pure Dart IndicBpeTokenizer Tests', () {
    late IndicBpeTokenizer tokenizer;

    setUp(() async {
      tokenizer = IndicBpeTokenizer.instance;
      await tokenizer.init(Directory.systemTemp.path);
    });

    test('Tokenizer initializes with special tokens and all 10 Flores language tags', () {
      expect(tokenizer.isLoaded, isTrue);
      expect(tokenizer.vocabSize, greaterThan(20));

      // Special Token IDs
      expect(IndicBpeTokenizer.bosId, equals(0));
      expect(IndicBpeTokenizer.padId, equals(1));
      expect(IndicBpeTokenizer.eosId, equals(2));
      expect(IndicBpeTokenizer.unkId, equals(3));

      // Flores codes for all 10 languages
      expect(IndicBpeTokenizer.floresCodes['hi'], equals('hin_Deva'));
      expect(IndicBpeTokenizer.floresCodes['en'], equals('eng_Latn'));
      expect(IndicBpeTokenizer.floresCodes['ta'], equals('tam_Taml'));
      expect(IndicBpeTokenizer.floresCodes['te'], equals('tel_Telu'));
      expect(IndicBpeTokenizer.floresCodes['kn'], equals('kan_Knda'));
      expect(IndicBpeTokenizer.floresCodes['ml'], equals('mal_Mlym'));
      expect(IndicBpeTokenizer.floresCodes['mr'], equals('mar_Deva'));
      expect(IndicBpeTokenizer.floresCodes['gu'], equals('guj_Gujr'));
      expect(IndicBpeTokenizer.floresCodes['bn'], equals('ben_Beng'));
      expect(IndicBpeTokenizer.floresCodes['or'], equals('ory_Orya'));
    });

    test('Encodes text by injecting target language tag at start and EOS at end', () {
      final tokens = tokenizer.encode(
        text: 'Emergency evacuation required',
        sourceLang: 'en',
        targetLang: 'hi',
      );

      expect(tokens, isNotEmpty);
      // Target tag at index 0 (should be the ID for <2hin_Deva>)
      expect(tokens.first, isNot(equals(IndicBpeTokenizer.eosId)));
      // Ends with EOS (id 2)
      expect(tokens.last, equals(IndicBpeTokenizer.eosId));
      expect(tokens.length, greaterThan(2));
    });

    test('Decodes token IDs into human-readable text stripping special tokens and language tags', () {
      final encoded = tokenizer.encode(
        text: 'Hello world',
        sourceLang: 'en',
        targetLang: 'hi',
      );

      final decoded = tokenizer.decode(encoded, targetLang: 'hi');
      expect(decoded.toLowerCase(), contains('hello world'));
      // Must not leak special tokens or language tags
      expect(decoded.contains('<2'), isFalse);
      expect(decoded.contains('</s>'), isFalse);
      expect(decoded.contains('\u2581'), isFalse);
    });

    test('Handles empty text gracefully', () {
      final emptyEncoded = tokenizer.encode(
        text: '   ',
        sourceLang: 'hi',
        targetLang: 'en',
      );
      expect(emptyEncoded, equals([IndicBpeTokenizer.eosId]));

      final emptyDecoded = tokenizer.decode([]);
      expect(emptyDecoded, equals(''));
    });

    test('IndicTransEngine integration exposes tokenize and detokenize methods', () {
      final mt = IndicTransEngine();
      final tokenIds = mt.tokenize('Safe zone reached', 'en', 'ta');
      expect(tokenIds, isNotEmpty);
      expect(tokenIds.last, equals(IndicBpeTokenizer.eosId));

      final text = mt.detokenize(tokenIds, 'ta');
      expect(text.toLowerCase(), contains('safe zone reached'));
    });
  });
}
