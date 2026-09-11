class MessageEntity {
  final int? id;
  final String senderId;
  final String text;
  final String languageCode;
  final String type; // VOICE, ALERT, ACK
  final int timestamp;
  final bool isIncoming;

  MessageEntity({
    this.id,
    required this.senderId,
    required this.text,
    this.languageCode = 'hi',
    this.type = 'VOICE',
    int? timestamp,
    this.isIncoming = false,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'senderId': senderId,
    'text': text,
    'languageCode': languageCode,
    'type': type,
    'timestamp': timestamp,
    'isIncoming': isIncoming ? 1 : 0,
  };

  factory MessageEntity.fromMap(Map<String, dynamic> map) => MessageEntity(
    id: map['id'] as int?,
    senderId: map['senderId'] as String? ?? '',
    text: map['text'] as String? ?? '',
    languageCode: map['languageCode'] as String? ?? 'hi',
    type: map['type'] as String? ?? 'VOICE',
    timestamp: map['timestamp'] as int? ?? 0,
    isIncoming: (map['isIncoming'] as int? ?? 0) == 1,
  );

  MessageEntity copyWith({
    int? id,
    String? senderId,
    String? text,
    String? languageCode,
    String? type,
    int? timestamp,
    bool? isIncoming,
  }) => MessageEntity(
    id: id ?? this.id,
    senderId: senderId ?? this.senderId,
    text: text ?? this.text,
    languageCode: languageCode ?? this.languageCode,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    isIncoming: isIncoming ?? this.isIncoming,
  );
}
