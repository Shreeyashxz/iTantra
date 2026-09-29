import 'package:uuid/uuid.dart';
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
    final trimmed = alertText.trim();
    if (trimmed.isEmpty || trimmed.length > TransceiverPacket.maxTextChars) return;
    // Stable IDs come from TransceiverController.deviceId (persisted).
    // Fallback uses UUID to avoid 90k-space collisions of Random().nextInt.
    final effectiveSenderId = (senderId != null && senderId.trim().isNotEmpty)
        ? senderId.trim()
        : 'DEV_${const Uuid().v4().substring(0, 8).toUpperCase()}';

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
