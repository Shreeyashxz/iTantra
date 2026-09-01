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

    init {
        initRecognizer()
        initTts()
    }

    private fun initRecognizer() {
        try {
            val modelsDir = File(context.getExternalFilesDir(null), "models").absolutePath
            val config = OnlineRecognizerConfig(
                featConfig = FeatureConfig(
                    sampleRate = 16000,
                    featureDim = 80
                ),
                modelConfig = OnlineModelConfig(
                    transducer = OnlineTransducerModelConfig(
                        encoder = "$modelsDir/stt/encoder.onnx",
                        decoder = "$modelsDir/stt/decoder.onnx",
                        joiner = "$modelsDir/stt/joiner.onnx"
                    ),
                    tokens = "$modelsDir/stt/tokens.txt",
                    modelType = "zipformer"
                ),
                endpointConfig = EndpointConfig(),
                enableEndpoint = true
            )
            // Passing null/empty for AssetManager indicates absolute paths
            recognizer = OnlineRecognizer(assetManager = null, config = config)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun initTts() {
        try {
            val modelsDir = File(context.getExternalFilesDir(null), "models").absolutePath
            // Defaulting to Hindi for initialization, would be updated dynamically based on settings
            val langCode = "hi" 
            val vitsConfig = OfflineTtsVitsModelConfig(
                model = "$modelsDir/tts/$langCode/vits.onnx",
                tokens = "$modelsDir/tts/$langCode/tokens.txt",
                lexicon = "$modelsDir/tts/$langCode/lexicon.txt"
            )
            val modelConfig = OfflineTtsModelConfig(
                vits = vitsConfig
            )
            val config = OfflineTtsConfig(
                model = modelConfig
            )
            tts = OfflineTts(assetManager = null, config = config)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun startListening(): Flow<String> {
        val flow = MutableStateFlow("")
        try {
            stream = recognizer?.createStream()
        } catch (e: Exception) {
            e.printStackTrace()
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
            e.printStackTrace()
        }
        stream = null
    }

    override suspend fun synthesizeSpeech(text: String, languageCode: String): Unit = withContext(Dispatchers.IO) {
        try {
            tts?.let { engine ->
                val audio = engine.generate(text, sid = 0, speed = 1.0f)
                val samples = audio.samples
                val sampleRate = audio.sampleRate
                if (samples.isNotEmpty()) {
                    playPcmAudio(samples, sampleRate, isAlert = false)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
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
