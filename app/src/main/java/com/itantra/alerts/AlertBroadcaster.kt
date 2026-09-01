package com.itantra.alerts

import com.itantra.network.TransceiverManager
import com.itantra.proto.TransceiverPacketProto.TransceiverPacket
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AlertBroadcaster @Inject constructor(
    private val transceiverManager: TransceiverManager
) {
    suspend fun broadcastAlert(
        senderId: String = UUID.randomUUID().toString().take(8),
        languageCode: String = "hi",
        alertText: String
    ) = withContext(Dispatchers.IO) {
        val packet = TransceiverPacket.newBuilder()
            .setSenderId(senderId)
            .setLanguageCode(languageCode)
            .setTranscript(alertText)
            .setTimestampMs(System.currentTimeMillis())
            .setType(TransceiverPacket.PacketType.ALERT)
            .build()

        transceiverManager.sendPacket(packet)
    }
}
