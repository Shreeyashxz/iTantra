package com.itantra.speech

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

sealed class DownloadState {
    object Idle : DownloadState()
    data class Downloading(val item: String, val progressPercent: Int) : DownloadState()
    data class Completed(val message: String) : DownloadState()
    data class Error(val message: String) : DownloadState()
}

@Singleton
class LanguagePackManager @Inject constructor(
    private val context: Context
) {
    private val _downloadState = MutableStateFlow<DownloadState>(DownloadState.Idle)
    val downloadState: StateFlow<DownloadState> = _downloadState.asStateFlow()

    fun getModelsDirectory(): File {
        val dir = File(context.getExternalFilesDir(null), "models")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    fun isSttAvailable(): Boolean {
        val dir = getModelsDirectory()
        val enc = File(dir, "stt/encoder.onnx")
        val dec = File(dir, "stt/decoder.onnx")
        val join = File(dir, "stt/joiner.onnx")
        val tokens = File(dir, "stt/tokens.txt")
        return enc.exists() && dec.exists() && join.exists() && tokens.exists()
    }

    fun isTtsAvailable(languageCode: String): Boolean {
        val dir = getModelsDirectory()
        val model = File(dir, "tts/$languageCode/vits.onnx")
        val tokens = File(dir, "tts/$languageCode/tokens.txt")
        return model.exists() && tokens.exists()
    }

    suspend fun downloadStt(): Boolean = withContext(Dispatchers.IO) {
        val modelsDir = getModelsDirectory()
        val sttDir = File(modelsDir, "stt").apply { mkdirs() }

        val baseUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/main"
        val files = listOf(
            "encoder-epoch-99-avg-1.int8.onnx" to "encoder.onnx",
            "decoder-epoch-99-avg-1.int8.onnx" to "decoder.onnx",
            "joiner-epoch-99-avg-1.int8.onnx" to "joiner.onnx",
            "tokens.txt" to "tokens.txt"
        )

        try {
            for ((remote, local) in files) {
                val targetFile = File(sttDir, local)
                if (!targetFile.exists() || targetFile.length() == 0L) {
                    _downloadState.value = DownloadState.Downloading("STT ($local)", 0)
                    downloadFileWithRedirects("$baseUrl/$remote", targetFile) { percent ->
                        _downloadState.value = DownloadState.Downloading("STT ($local)", percent)
                    }
                }
            }
            _downloadState.value = DownloadState.Completed("STT Model Downloaded Successfully")
            true
        } catch (e: Exception) {
            e.printStackTrace()
            _downloadState.value = DownloadState.Error("STT Download failed: ${e.localizedMessage}")
            false
        }
    }

    suspend fun downloadTts(languageCode: String): Boolean = withContext(Dispatchers.IO) {
        val modelsDir = getModelsDirectory()
        val ttsDir = File(modelsDir, "tts/$languageCode").apply { mkdirs() }

        val (baseUrl, modelFile) = when (languageCode) {
            "hi" -> Pair(
                "https://huggingface.co/csukuangfj/vits-piper-hi_IN-pratham-medium/resolve/main",
                "hi_IN-pratham-medium.onnx"
            )
            else -> Pair(
                "https://huggingface.co/csukuangfj/vits-piper-en_US-amy-low/resolve/main",
                "en_US-amy-low.onnx"
            )
        }

        try {
            val targetModel = File(ttsDir, "vits.onnx")
            val targetTokens = File(ttsDir, "tokens.txt")
            val targetLexicon = File(ttsDir, "lexicon.txt")

            if (!targetModel.exists() || targetModel.length() == 0L) {
                _downloadState.value = DownloadState.Downloading("TTS $languageCode (voice)", 0)
                downloadFileWithRedirects("$baseUrl/$modelFile", targetModel) { percent ->
                    _downloadState.value = DownloadState.Downloading("TTS $languageCode (voice)", percent)
                }
            }

            if (!targetTokens.exists() || targetTokens.length() == 0L) {
                _downloadState.value = DownloadState.Downloading("TTS $languageCode (tokens)", 0)
                downloadFileWithRedirects("$baseUrl/tokens.txt", targetTokens) { percent ->
                    _downloadState.value = DownloadState.Downloading("TTS $languageCode (tokens)", percent)
                }
            }

            // Create empty lexicon if none is needed by Piper
            if (!targetLexicon.exists()) {
                targetLexicon.writeText("")
            }

            _downloadState.value = DownloadState.Completed("TTS for $languageCode Ready")
            true
        } catch (e: Exception) {
            e.printStackTrace()
            _downloadState.value = DownloadState.Error("TTS Download failed: ${e.localizedMessage}")
            false
        }
    }

    suspend fun downloadAllEssentials(onComplete: (Boolean) -> Unit) {
        val sttOk = downloadStt()
        val ttsHiOk = downloadTts("hi")
        val ttsEnOk = downloadTts("en")
        onComplete(sttOk && ttsHiOk && ttsEnOk)
    }

    private fun downloadFileWithRedirects(
        urlStr: String,
        destination: File,
        onProgress: (Int) -> Unit
    ) {
        var currentUrl = urlStr
        var connection: HttpURLConnection? = null
        var redirects = 0
        val maxRedirects = 8

        while (redirects < maxRedirects) {
            val url = URL(currentUrl)
            connection = url.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.setRequestProperty("User-Agent", "iTantra-Android/1.0")

            val status = connection.responseCode
            if (status == HttpURLConnection.HTTP_MOVED_TEMP ||
                status == HttpURLConnection.HTTP_MOVED_PERM ||
                status == 307 || status == 308 || status == 303
            ) {
                val newUrl = connection.getHeaderField("Location")
                currentUrl = if (newUrl.startsWith("http")) newUrl else URL(url, newUrl).toString()
                redirects++
                connection.disconnect()
                continue
            }

            if (status != HttpURLConnection.HTTP_OK) {
                throw Exception("Server returned HTTP $status for $currentUrl")
            }
            break
        }

        val conn = connection ?: throw Exception("Failed to establish connection")
        val fileLength = conn.contentLength
        val tempFile = File(destination.parentFile, "${destination.name}.tmp")

        conn.inputStream.use { input ->
            FileOutputStream(tempFile).use { output ->
                val data = ByteArray(8192)
                var total: Long = 0
                var count: Int
                var lastReported = -1

                while (input.read(data).also { count = it } != -1) {
                    total += count.toLong()
                    if (fileLength > 0) {
                        val percent = ((total * 100) / fileLength).toInt()
                        if (percent != lastReported) {
                            lastReported = percent
                            onProgress(percent)
                        }
                    }
                    output.write(data, 0, count)
                }
                output.flush()
            }
        }
        conn.disconnect()

        if (tempFile.exists()) {
            if (destination.exists()) destination.delete()
            tempFile.renameTo(destination)
        }
    }
}
