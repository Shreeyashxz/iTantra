package com.itantra.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import com.k2fsa.sherpa.onnx.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SherpaOnnxSpeechEngine @Inject constructor(
    private val context: Context
) : SpeechEngine {

    private var recognizer: OnlineRecognizer? = null
    private var tts: OfflineTts? = null
    private var stream: OnlineStream? = null
    private var currentAudioTrack: AudioTrack? = null

    private var currentTtsLanguage: String? = null

    init {
        reloadRecognizer()
        reloadTts("hi")
    }

    fun reloadRecognizer(): Boolean {
        return try {
            val modelsDir = File(context.getExternalFilesDir(null), "models").absolutePath
            val encFile = File("$modelsDir/stt/encoder.onnx")
            val decFile = File("$modelsDir/stt/decoder.onnx")
            val joinFile = File("$modelsDir/stt/joiner.onnx")
            val tokFile = File("$modelsDir/stt/tokens.txt")

            if (!encFile.exists() || !decFile.exists() || !joinFile.exists() || !tokFile.exists()) {
                android.util.Log.w("iTantraSpeech", "STT models not found in $modelsDir/stt - download required")
                return false
            }

            val config = OnlineRecognizerConfig(
                featConfig = FeatureConfig(
                    sampleRate = 16000,
                    featureDim = 80
                ),
                modelConfig = OnlineModelConfig(
                    transducer = OnlineTransducerModelConfig(
                        encoder = encFile.absolutePath,
                        decoder = decFile.absolutePath,
                        joiner = joinFile.absolutePath
                    ),
                    tokens = tokFile.absolutePath,
                    modelType = "zipformer"
                ),
                endpointConfig = EndpointConfig(),
                enableEndpoint = true
            )
            recognizer = OnlineRecognizer(assetManager = null, config = config)
            android.util.Log.i("iTantraSpeech", "OnlineRecognizer initialized successfully from $modelsDir")
            true
        } catch (e: Exception) {
            android.util.Log.e("iTantraSpeech", "Failed to initialize OnlineRecognizer", e)
            false
        }
    }

    fun reloadTts(languageCode: String): Boolean {
        return try {
            val modelsDir = File(context.getExternalFilesDir(null), "models").absolutePath
            val modelFile = File("$modelsDir/tts/$languageCode/vits.onnx")
            val tokensFile = File("$modelsDir/tts/$languageCode/tokens.txt")
            val lexiconFile = File("$modelsDir/tts/$languageCode/lexicon.txt")

            if (!modelFile.exists() || !tokensFile.exists()) {
                android.util.Log.w("iTantraSpeech", "TTS models not found for $languageCode in $modelsDir/tts/$languageCode")
                return false
            }

            val vitsConfig = OfflineTtsVitsModelConfig(
                model = modelFile.absolutePath,
                tokens = tokensFile.absolutePath,
                lexicon = if (lexiconFile.exists()) lexiconFile.absolutePath else ""
            )
            val modelConfig = OfflineTtsModelConfig(vits = vitsConfig)
            val config = OfflineTtsConfig(model = modelConfig)
            tts?.release()
            tts = OfflineTts(assetManager = null, config = config)
            currentTtsLanguage = languageCode
            android.util.Log.i("iTantraSpeech", "OfflineTts ($languageCode) initialized successfully")
            true
        } catch (e: Exception) {
            android.util.Log.e("iTantraSpeech", "Failed to initialize OfflineTts for $languageCode", e)
            false
        }
    }

    fun isRecognizerReady(): Boolean = recognizer != null
    fun isTtsReady(languageCode: String): Boolean = tts != null && currentTtsLanguage == languageCode

    override fun startListening(): Flow<String> {
        val flow = MutableStateFlow("")
        if (recognizer == null) {
            reloadRecognizer()
        }
        try {
            stream = recognizer?.createStream()
        } catch (e: Exception) {
            android.util.Log.e("iTantraSpeech", "Error creating stream", e)
        }
        return flow
    }

    override fun stopListening() {
        try {
            stream?.let {
                recognizer?.decode(it)
                val text = recognizer?.getResult(it)?.text
                it.release()
            }
        } catch (e: Exception) {
            android.util.Log.e("iTantraSpeech", "Error stopping stream", e)
        }
        stream = null
    }

    override suspend fun synthesizeSpeech(text: String, languageCode: String): Unit = withContext(Dispatchers.IO) {
        if (tts == null || currentTtsLanguage != languageCode) {
            reloadTts(languageCode)
        }
        try {
            tts?.let { engine ->
                val audio = engine.generate(text, sid = 0, speed = 1.0f)
                val samples = audio.samples
                val sampleRate = audio.sampleRate
                if (samples.isNotEmpty()) {
                    playPcmAudio(samples, sampleRate, isAlert = false)
                }
            } ?: run {
                android.util.Log.w("iTantraSpeech", "TTS engine unavailable for language $languageCode. Download pack via Settings.")
            }
        } catch (e: Exception) {
            android.util.Log.e("iTantraSpeech", "Error generating speech", e)
        }
        Unit
    }

    fun playPcmAudio(samples: FloatArray, sampleRate: Int, isAlert: Boolean = false) {
        stopSpeech()
        val usage = if (isAlert) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_MEDIA
        val streamType = if (isAlert) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC

        val audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(usage)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(samples.size * 4)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        audioTrack.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
        audioTrack.play()
        currentAudioTrack = audioTrack
    }

    override fun stopSpeech() {
        try {
            currentAudioTrack?.stop()
            currentAudioTrack?.release()
        } catch (e: Exception) {
            // Ignore
        }
        currentAudioTrack = null
    }

    override fun release() {
        recognizer?.release()
        recognizer = null
        tts?.release()
        tts = null
        stopSpeech()
    }
}
