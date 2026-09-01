package com.itantra.alerts

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.itantra.network.TransceiverManager
import com.itantra.proto.TransceiverPacketProto.TransceiverPacket
import com.itantra.speech.SherpaOnnxSpeechEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

data class AlertEvent(
    val senderId: String,
    val text: String,
    val languageCode: String,
    val timestampMs: Long
)

@Singleton
class AlertReceiver @Inject constructor(
    private val context: Context,
    private val transceiverManager: TransceiverManager,
    private val speechEngine: SherpaOnnxSpeechEngine
) {
    private val scope = CoroutineScope(Dispatchers.IO)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val _activeAlert = MutableStateFlow<AlertEvent?>(null)
    val activeAlert: StateFlow<AlertEvent?> = _activeAlert

    init {
        startListeningForAlerts()
    }

    private fun startListeningForAlerts() {
        scope.launch {
            transceiverManager.incomingPackets.collect { packet ->
                if (packet.type == TransceiverPacket.PacketType.ALERT) {
                    handleIncomingAlert(packet)
                }
            }
        }
    }

    private suspend fun handleIncomingAlert(packet: TransceiverPacket) {
        val event = AlertEvent(
            senderId = packet.senderId,
            text = packet.transcript,
            languageCode = packet.languageCode,
            timestampMs = packet.timestampMs
        )
        _activeAlert.value = event

        // 1. Maximize STREAM_ALARM volume for non-interruptible alert
        try {
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // 2. Trigger high-intensity vibration
        triggerVibration()

        // 3. Synthesize and speak alert audio
        try {
            speechEngine.synthesizeSpeech(packet.transcript, packet.languageCode)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun triggerVibration() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, -1)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun dismissAlert() {
        _activeAlert.value = null
        speechEngine.stopSpeech()
    }
}
