import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

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
  static const int maxPacketBytes = 256 * 1024;
  static const int maxTextChars = 2000;
  static const int maxIdChars = 128;
  static const String pingMagic = '__ITANTRA_PING__';

  final String senderId;
  final String languageCode;
  final String transcript;
  final int timestampMs;
  final PacketType type;
  /// Unique per-packet id for dedup/ordering across Wi-Fi + BLE dual delivery.
  /// Missing (old peers) falls back to senderId|timestampMs.
  final String packetId;

  TransceiverPacket({
    required this.senderId,
    this.languageCode = 'hi',
    required this.transcript,
    int? timestampMs,
    this.type = PacketType.voice,
    String? packetId,
  })  : timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch,
        packetId = (packetId != null && packetId.isNotEmpty)
            ? packetId
            : const Uuid().v4();

  /// Dedup key stable across retransmits and dual transports.
  String get dedupKey => packetId.isNotEmpty ? 'id:$packetId' : 'st:$senderId|$timestampMs';

  /// Serializes packet to standard Protobuf wire format (binary)
  Uint8List toProtoBytes() {
    // Bound outgoing size — prevents accidental OOM on huge transcripts.
    final safeSender = senderId.length > maxIdChars ? senderId.substring(0, maxIdChars) : senderId;
    final safeTranscript = transcript.length > maxTextChars ? transcript.substring(0, maxTextChars) : transcript;
    final BytesBuilder builder = BytesBuilder();

    // Field 1: sender_id (string, tag = (1 << 3) | 2 = 10)
    if (safeSender.isNotEmpty) {
      final bytes = utf8.encode(safeSender);
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
    if (safeTranscript.isNotEmpty) {
      final bytes = utf8.encode(safeTranscript);
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

    // Field 6: packet_id (string, tag = (6 << 3) | 2 = 50) — dedup across transports
    if (packetId.isNotEmpty) {
      final bytes = utf8.encode(packetId.length > maxIdChars ? packetId.substring(0, maxIdChars) : packetId);
      _writeVarint(builder, (6 << 3) | 2);
      _writeVarint(builder, bytes.length);
      builder.add(bytes);
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
    if (bytes.length > maxPacketBytes) {
      throw FormatException('packet exceeds ${maxPacketBytes}B cap (${bytes.length}B)');
    }
    String senderId = '';
    String languageCode = 'hi';
    String transcript = '';
    int timestampMs = 0;
    PacketType type = PacketType.voice;
    String packetId = '';

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
            if (length < 0 || length > maxPacketBytes || offset + length > bytes.length) {
              throw FormatException('bad senderId length $length');
            }
            senderId = utf8.decode(bytes.sublist(offset, offset + length), allowMalformed: true);
            if (senderId.length > maxIdChars) senderId = senderId.substring(0, maxIdChars);
            offset += length;
          }
          break;
        case 2: // language_code
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            if (length < 0 || length > 16 || offset + length > bytes.length) {
              throw FormatException('bad lang length $length');
            }
            languageCode = utf8.decode(bytes.sublist(offset, offset + length), allowMalformed: true);
            offset += length;
          }
          break;
        case 3: // transcript
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            if (length < 0 || length > maxPacketBytes || offset + length > bytes.length) {
              throw FormatException('bad transcript length $length');
            }
            transcript = utf8.decode(bytes.sublist(offset, offset + length), allowMalformed: true);
            if (transcript.length > maxTextChars) transcript = transcript.substring(0, maxTextChars);
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
        case 6: // packet_id
          if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            final length = lenRes.value;
            offset = lenRes.newOffset;
            if (length < 0 || length > maxIdChars + 16 || offset + length > bytes.length) {
              throw FormatException('bad packetId length $length');
            }
            packetId = utf8.decode(bytes.sublist(offset, offset + length), allowMalformed: true);
            offset += length;
          }
          break;
        default:
          // Skip unknown field according to wire type (with bounds checks)
          if (wireType == 0) {
            final skipRes = _readVarint(bytes, offset);
            offset = skipRes.newOffset;
          } else if (wireType == 2) {
            final lenRes = _readVarint(bytes, offset);
            if (lenRes.value < 0 || lenRes.value > maxPacketBytes || lenRes.newOffset + lenRes.value > bytes.length) {
              throw FormatException('bad skip length ${lenRes.value}');
            }
            offset = lenRes.newOffset + lenRes.value;
          } else if (wireType == 1) {
            if (offset + 8 > bytes.length) throw const FormatException('truncated fixed64');
            offset += 8;
          } else if (wireType == 5) {
            if (offset + 4 > bytes.length) throw const FormatException('truncated fixed32');
            offset += 4;
          } else {
            throw FormatException('unsupported wire type $wireType');
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
      packetId: packetId.isEmpty ? null : packetId,
    );
  }

  /// Parses a length-delimited protobuf chunk from a buffer.
  /// Returns bytesConsumed=-1 on corrupt framing so callers can drop the buffer
  /// instead of wedging forever on unconsumed bytes.
  static ({TransceiverPacket? packet, int bytesConsumed}) parseDelimited(Uint8List buffer) {
    if (buffer.isEmpty) return (packet: null, bytesConsumed: 0);

    try {
      final lenRes = _readVarint(buffer, 0);
      final payloadLen = lenRes.value;
      final headerLen = lenRes.newOffset;

      if (payloadLen < 0 || payloadLen > maxPacketBytes) {
        return (packet: null, bytesConsumed: -1); // corrupt length — drop buffer
      }

      if (buffer.length < headerLen + payloadLen) {
        return (packet: null, bytesConsumed: 0); // Need more data
      }

      final payload = buffer.sublist(headerLen, headerLen + payloadLen);
      final packet = fromProtoBytes(payload);
      return (packet: packet, bytesConsumed: headerLen + payloadLen);
    } catch (_) {
      return (packet: null, bytesConsumed: -1);
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
    int count = 0;
    while (cur < bytes.length) {
      if (count++ >= 10) throw const FormatException('varint too long');
      final byte = bytes[cur++];
      if (shift >= 64) throw const FormatException('varint overflow');
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        return (value: result, newOffset: cur);
      }
      shift += 7;
    }
    throw const FormatException('truncated varint');
  }

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'languageCode': languageCode,
    'transcript': transcript,
    'timestampMs': timestampMs,
    'type': type.name.toUpperCase(),
    'packetId': packetId,
  };

  factory TransceiverPacket.fromJson(Map<String, dynamic> json) => TransceiverPacket(
    senderId: json['senderId'] as String? ?? '',
    languageCode: json['languageCode'] as String? ?? 'hi',
    transcript: json['transcript'] as String? ?? '',
    timestampMs: json['timestampMs'] as int?,
    type: PacketType.fromString(json['type'] as String? ?? 'VOICE'),
    packetId: json['packetId'] as String?,
  );

  @override
  String toString() =>
      'TransceiverPacket(senderId: $senderId, lang: $languageCode, text: "$transcript", type: $type, time: $timestampMs, id: $packetId)';
}
