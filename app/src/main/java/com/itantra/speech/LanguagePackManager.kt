package com.itantra.speech

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LanguagePackManager @Inject constructor(
    private val context: Context
) {
    private val _downloadProgress = MutableStateFlow<Map<String, Float>>(emptyMap())
    val downloadProgress: Flow<Map<String, Float>> = _downloadProgress

    fun getModelsDirectory(): File {
        val dir = File(context.getExternalFilesDir(null), "models")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    suspend fun downloadLanguagePack(languageCode: String, onComplete: (Boolean) -> Unit) = withContext(Dispatchers.IO) {
        // Placeholder URLs for the actual STT and TTS models
        // In a real scenario, these would point to HuggingFace or your backend CDN
        val sttUrl = "https://example.com/models/stt_indicconformer.onnx"
        val ttsUrl = "https://example.com/models/tts_vits_$languageCode.onnx"
        
        val modelsDir = getModelsDirectory()
        
        try {
            val sttFile = File(modelsDir, "stt/encoder.onnx")
            if (!sttFile.exists()) {
                sttFile.parentFile?.mkdirs()
                downloadFile(sttUrl, sttFile) { progress ->
                    updateProgress("STT", progress)
                }
            }

            val ttsFile = File(modelsDir, "tts/$languageCode/vits.onnx")
            if (!ttsFile.exists()) {
                ttsFile.parentFile?.mkdirs()
                downloadFile(ttsUrl, ttsFile) { progress ->
                    updateProgress("TTS_$languageCode", progress)
                }
            }
            onComplete(true)
        } catch (e: Exception) {
            e.printStackTrace()
            onComplete(false)
        }
    }

    private fun updateProgress(key: String, progress: Float) {
        val current = _downloadProgress.value.toMutableMap()
        current[key] = progress
        _downloadProgress.value = current
    }

    private fun downloadFile(urlStr: String, destination: File, onProgress: (Float) -> Unit) {
        val url = URL(urlStr)
        val connection = url.openConnection() as HttpURLConnection
        connection.connect()

        if (connection.responseCode != HttpURLConnection.HTTP_OK) {
            throw Exception("Server returned HTTP ${connection.responseCode}")
        }

        val fileLength = connection.contentLength
        val input = connection.inputStream
        val output = FileOutputStream(destination)

        val data = ByteArray(4096)
        var total: Long = 0
        var count: Int
        while (input.read(data).also { count = it } != -1) {
            total += count.toLong()
            if (fileLength > 0) {
                onProgress((total * 100 / fileLength).toFloat())
            }
            output.write(data, 0, count)
        }
        output.flush()
        output.close()
        input.close()
    }
}
