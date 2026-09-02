import 'dart:math';
import '../network/transceiver_manager.dart';
import '../proto/transceiver_packet.dart';

class AlertBroadcaster {
  final TransceiverManager transceiverManager;

  AlertBroadcaster({required this.transceiverManager});

  Future<void> broadcastAlert({
    String? senderId,
    String languageCode = 'hi',
    required String alertText,
  }) async {
    final effectiveSenderId = senderId ??
        'DEV_${Random().nextInt(90000) + 10000}';

    final packet = TransceiverPacket(
      senderId: effectiveSenderId,
      languageCode: languageCode,
      transcript: alertText,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: PacketType.alert,
    );

    await transceiverManager.sendPacket(packet);
  }
}
