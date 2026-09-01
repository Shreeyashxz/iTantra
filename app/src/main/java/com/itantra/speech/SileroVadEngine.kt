package com.itantra.speech

import android.content.Context
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SileroVadEngine @Inject constructor(
    private val context: Context
) : VadEngine {

    private var vad: Vad? = null
    private val scope = CoroutineScope(Dispatchers.Default)

    init {
        initVad()
    }

    private fun initVad() {
        try {
            val sileroConfig = SileroVadModelConfig(
                model = "models/silero_vad.onnx",
                threshold = 0.5f,
                minSilenceDuration = 0.5f,
                minSpeechDuration = 0.25f,
                windowSize = 512,
                maxSpeechDuration = 30.0f
            )
            val config = VadModelConfig().apply {
                this.sileroVadModelConfig = sileroConfig
                this.sampleRate = 16000
                this.numThreads = 1
                this.provider = "cpu"
            }
            vad = Vad(context.assets, config)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun startVad(audioData: Flow<ShortArray>): Flow<Boolean> {
        val isSpeechFlow = MutableStateFlow(false)
        scope.launch {
            audioData.collect { shortChunk ->
                vad?.let { v ->
                    val floatChunk = FloatArray(shortChunk.size) { shortChunk[it] / 32768.0f }
                    v.acceptWaveform(floatChunk)
                    isSpeechFlow.value = v.isSpeechDetected()
                }
            }
        }
        return isSpeechFlow
    }

    override fun stopVad() {
        vad?.reset()
    }

    override fun release() {
        vad?.release()
        vad = null
    }
}
