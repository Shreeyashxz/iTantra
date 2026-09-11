import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/proto/transceiver_packet.dart';

void main() {
  group('TransceiverPacket Protocol Serialization Tests', () {
    test('Protobuf binary roundtrip preserves all fields', () {
      final original = TransceiverPacket(
        senderId: 'NODE_007',
        languageCode: 'hi',
        transcript: 'आपातकाल! तत्काल सहायता की आवश्यकता है।',
        timestampMs: 1725250000000,
        type: PacketType.alert,
      );

      final protoBytes = original.toProtoBytes();
      expect(protoBytes.isNotEmpty, isTrue);

      final deserialized = TransceiverPacket.fromProtoBytes(protoBytes);
      expect(deserialized.senderId, equals('NODE_007'));
      expect(deserialized.languageCode, equals('hi'));
      expect(deserialized.transcript, equals('आपातकाल! तत्काल सहायता की आवश्यकता है।'));
      expect(deserialized.timestampMs, equals(1725250000000));
      expect(deserialized.type, equals(PacketType.alert));
    });

    test('Length-delimited Protobuf streaming parses continuous stream', () {
      final packet1 = TransceiverPacket(
        senderId: 'DEV_A',
        languageCode: 'en',
        transcript: 'Testing voice link on channel 1',
        type: PacketType.voice,
      );

      final packet2 = TransceiverPacket(
        senderId: 'DEV_B',
        languageCode: 'ta',
        transcript: 'வணக்கம், இணைப்பு சரிபார்க்கப்பட்டது',
        type: PacketType.voice,
      );

      // Construct continuous delimited binary stream
      final bytes1 = packet1.toProtoBytes();
      final bytes2 = packet2.toProtoBytes();

      final streamBuilder = BytesBuilder();
      // Length varint + payload 1
      streamBuilder.addByte(bytes1.length);
      streamBuilder.add(bytes1);
      // Length varint + payload 2
      streamBuilder.addByte(bytes2.length);
      streamBuilder.add(bytes2);

      final streamData = streamBuilder.toBytes();

      // Parse first packet
      final res1 = TransceiverPacket.parseDelimited(streamData);
      expect(res1.packet, isNotNull);
      expect(res1.packet!.senderId, equals('DEV_A'));
      expect(res1.packet!.transcript, equals('Testing voice link on channel 1'));

      // Parse second packet from remaining bytes
      final remaining = streamData.sublist(res1.bytesConsumed);
      final res2 = TransceiverPacket.parseDelimited(remaining);
      expect(res2.packet, isNotNull);
      expect(res2.packet!.senderId, equals('DEV_B'));
      expect(res2.packet!.transcript, equals('வணக்கம், இணைப்பு சரிபார்க்கப்பட்டது'));
    });

    test('JSON serialization roundtrip operates correctly', () {
      final packet = TransceiverPacket(
        senderId: 'DEV_TEST',
        languageCode: 'gu',
        transcript: 'નમસ્તે, વાયરલેસ ટ્રાન્સસીવર કામ કરે છે',
        type: PacketType.voice,
      );

      final json = packet.toJson();
      final fromJson = TransceiverPacket.fromJson(json);

      expect(fromJson.senderId, equals(packet.senderId));
      expect(fromJson.languageCode, equals('gu'));
      expect(fromJson.transcript, equals(packet.transcript));
      expect(fromJson.type, equals(PacketType.voice));
    });
  });
}
