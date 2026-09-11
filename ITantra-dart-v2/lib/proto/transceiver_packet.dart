import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum PacketType {
  voice(0),
  alert(1),
  ack(2);

  final int value;
  const PacketType(this.value);

  static PacketType fromValue(int value) {
    switch (value) {
      case 0:
        return PacketType.voice;
      case 1:
        return PacketType.alert;
      case 2:
        return PacketType.ack;
      default:
        return PacketType.voice;
    }
  }

  static PacketType fromString(String name) {
    switch (name.toUpperCase()) {
      case 'VOICE':
        return PacketType.voice;
      case 'ALERT':
        return PacketType.alert;
      case 'ACK':
        return PacketType.ack;
      default:
        return PacketType.voice;
    }
  }
}

/// Strongly typed TransceiverPacket conforming to transceiver_packet.proto
class TransceiverPacket {
  final String senderId;
  final String languageCode;
  final String transcript;
  final int timestampMs;
  final PacketType type;

  TransceiverPacket({
    required this.senderId,
    this.languageCode = 'hi',
    required this.transcript,
    int? timestampMs,
    this.type = PacketType.voice,
  }) : timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Serializes packet to standard Protobuf wire format (binary)
  Uint8List toProtoBytes() {
    final BytesBuilder builder = BytesBuilder();

    // Field 1: sender_id (string, tag = (1 << 3) | 2 = 10)
    if (senderId.isNotEmpty) {
      final bytes = utf8.encode(senderId);
      _writeVarint(builder, (1 << 3) | 2);
      _writeVarint(builder, bytes.length);
      builder.add(bytes);
    }

    // Field 2: language_code (string, tag = (2 << 3) | 2 = 18)
    if (languageCode.isNotEmpty) {
      final bytes = utf8.encode(languageCode);
      _writeVarint(builder, (2 << 3) | 2);
      _writeVarint(builder, bytes.length);
      builder.add(bytes);
    }

    // Field 3: transcript (string, tag = (3 << 3) | 2 = 26)
    if (transcript.isNotEmpty) {
      final bytes = utf8.encode(transcript);
      _writeVarint(builder, (3 << 3) | 2);
      _writeVarint(builder, bytes.length);
      builder.add(bytes);
    }

    // Field 4: timestamp_ms (int64, tag = (4 << 3) | 0 = 32)
    if (timestampMs != 0) {
      _writeVarint(builder, (4 << 3) | 0);
      _writeVarint(builder, timestampMs);
    }

    // Field 5: type (enum, tag = (5 << 3) | 0 = 40)
    if (type.value != 0) {
      _writeVarint(builder, (5 << 3) | 0);
      _writeVarint(builder, type.value);
    }

    return builder.toBytes();
  }

  /// Writes length-delimited protobuf bytes to a stream sink (equivalent to Java writeDelimitedTo)
  void writeDelimitedTo(IOSink sink) {
    final payload = toProtoBytes();
    final headerBuilder = BytesBuilder();
    _writeVarint(headerBuilder, payload.length);
    sink.add(headerBuilder.toBytes());
    sink.add(payload);
  }

  /// Parses a TransceiverPacket from raw Protobuf binary bytes
  static TransceiverPacket fromProtoBytes(Uint8List bytes) {
    String senderId = '';
    String languageCode = 'hi';
    String transcript = '';
    int timestampMs = 0;
    PacketType type = PacketType.voice;

    int offset = 0;
    while (offset < bytes.length) {
      final tagResult = _readVarint(bytes, offset);
      final tag = tagResult.value;
      offset = tagResult.newOffset;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // sender_id
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            senderId = utf8.decode(bytes.sublist(offset, offset + length));
            offset += length;
          }
          break;
        case 2: // language_code
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            languageCode = utf8.decode(bytes.sublist(offset, offset + length));
            offset += length;
          }
          break;
        case 3: // transcript
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            transcript = utf8.decode(bytes.sublist(offset, offset + length));
            offset += length;
          }
          break;
        case 4: // timestamp_ms
          if (wireType == 0) {
            final valRes = _readVarint(bytes, offset);
            timestampMs = valRes.value;
            offset = valRes.newOffset;
          }
          break;
        case 5: // type
          if (wireType == 0) {
            final valRes = _readVarint(bytes, offset);
            type = PacketType.fromValue(valRes.value);
            offset = valRes.newOffset;
          }
          break;
        default:
          // Skip unknown field according to wire type
          if (wireType == 0) {
            final skipRes = _readVarint(bytes, offset);
            offset = skipRes.newOffset;
          } else if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            offset = lenRes.newOffset + lenRes.value;
          } else if (wireType == 1) {
            offset += 8;
          } else if (wireType == 5) {
            offset += 4;
          }
          break;
      }
    }

    return TransceiverPacket(
      senderId: senderId,
      languageCode: languageCode,
      transcript: transcript,
      timestampMs: timestampMs == 0 ? DateTime.now().millisecondsSinceEpoch : timestampMs,
      type: type,
    );
  }

  /// Parses a length-delimited protobuf chunk from a buffer
  static ({TransceiverPacket? packet, int bytesConsumed}) parseDelimited(Uint8List buffer) {
    if (buffer.isEmpty) return (packet: null, bytesConsumed: 0);

    try {
      final lenRes = _readVarint(buffer, 0);
      final payloadLen = lenRes.value;
      final headerLen = lenRes.newOffset;

      if (buffer.length < headerLen + payloadLen) {
        return (packet: null, bytesConsumed: 0); // Need more data
      }

      final payload = buffer.sublist(headerLen, headerLen + payloadLen);
      final packet = fromProtoBytes(payload);
      return (packet: packet, bytesConsumed: headerLen + payloadLen);
    } catch (_) {
      return (packet: null, bytesConsumed: 0);
    }
  }

  static void _writeVarint(BytesBuilder builder, int value) {
    var v = value;
    while ((v & ~0x7F) != 0) {
      builder.addByte((v & 0x7F) | 0x80);
      v = (v >> 7) & 0x01FFFFFFFFFFFFFF; // unsigned shift
    }
    builder.addByte(v & 0x7F);
  }

  static ({int value, int newOffset}) _readVarint(Uint8List bytes, int offset) {
    int result = 0;
    int shift = 0;
    int cur = offset;
    while (cur < bytes.length) {
      final byte = bytes[cur++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        return (value: result, newOffset: cur);
      }
      shift += 7;
    }
    return (value: result, newOffset: cur);
  }

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'languageCode': languageCode,
    'transcript': transcript,
    'timestampMs': timestampMs,
    'type': type.name.toUpperCase(),
  };

  factory TransceiverPacket.fromJson(Map<String, dynamic> json) => TransceiverPacket(
    senderId: json['senderId'] as String? ?? '',
    languageCode: json['languageCode'] as String? ?? 'hi',
    transcript: json['transcript'] as String? ?? '',
    timestampMs: json['timestampMs'] as int?,
    type: PacketType.fromString(json['type'] as String? ?? 'VOICE'),
  );

  @override
  String toString() =>
      'TransceiverPacket(senderId: $senderId, lang: $languageCode, text: "$transcript", type: $type, time: $timestampMs)';
}
