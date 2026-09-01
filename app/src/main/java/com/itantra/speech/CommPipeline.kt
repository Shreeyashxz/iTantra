package com.itantra.speech

import com.itantra.audio.AudioRecorder
import com.itantra.network.TransceiverManager
import com.itantra.proto.TransceiverPacketProto.TransceiverPacket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CommPipeline @Inject constructor(
    private val audioRecorder: AudioRecorder,
    private val vadEngine: VadEngine,
    private val speechEngine: SpeechEngine,
    private val transceiverManager: TransceiverManager
) {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var recordingJob: Job? = null

    fun startTransmission(senderId: String) {
        recordingJob?.cancel()
        recordingJob = scope.launch {
            val audioStream = audioRecorder.startRecording()
            // In a real implementation, audioStream feeds into vadEngine and speechEngine
            // Here we mock the pipeline for STT text generation
            val textStream = speechEngine.startListening()

            textStream.collectLatest { text ->
                if (text.isNotBlank()) {
                    val packet = TransceiverPacket.newBuilder()
                        .setSenderId(senderId)
                        .setTranscript(text)
                        .setTimestampMs(System.currentTimeMillis())
                        .setType(TransceiverPacket.PacketType.VOICE)
                        .build()

                    transceiverManager.sendPacket(packet)
                }
            }
        }
    }

    fun stopTransmission() {
        recordingJob?.cancel()
        audioRecorder.stopRecording()
        speechEngine.stopListening()
    }
}
