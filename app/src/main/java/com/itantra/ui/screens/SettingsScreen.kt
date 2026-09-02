package com.itantra.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.itantra.ui.viewmodels.TransceiverViewModel
import com.itantra.ui.viewmodels.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit,
    transceiverViewModel: TransceiverViewModel = hiltViewModel(),
    settingsViewModel: SettingsViewModel = hiltViewModel()
) {
    var ttsSpeed by remember { mutableStateOf(1.0f) }
    var pttHoldMode by remember { mutableStateOf(true) }
    var autoPlayAudio by remember { mutableStateOf(true) }
    val selectedLanguage by transceiverViewModel.selectedLanguage.collectAsState()

    val languages = listOf(
        "hi" to "Hindi (हिंदी)",
        "en" to "English",
        "gu" to "Gujarati (ગુજરાતી)",
        "mr" to "Marathi (मराठी)",
        "kn" to "Kannada (ಕನ್ನಡ)",
        "ml" to "Malayalam (മലയാളം)",
        "ta" to "Tamil (தமிழ்)",
        "te" to "Telugu (తెలుగు)",
        "or" to "Odia (ଓଡ଼ିଆ)",
        "bn" to "Bengali (বাংলা)"
    )

    val downloadState by settingsViewModel.downloadState.collectAsState()
    var refreshTrigger by remember { mutableStateOf(0) }
    val isSttReady = remember(refreshTrigger, downloadState) { settingsViewModel.isSttAvailable() }
    val isHiTtsReady = remember(refreshTrigger, downloadState) { settingsViewModel.isTtsAvailable("hi") }
    val isEnTtsReady = remember(refreshTrigger, downloadState) { settingsViewModel.isTtsAvailable("en") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings & Calibration") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            Text("Neural Models (On-Demand Download)", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "On-device models are downloaded once and cached in private storage (<45MB APK constraint).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(12.dp))

                    // STT Status
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("STT Engine (Zipformer INT8)", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                if (isSttReady) "✅ Installed & Ready" else "⚠️ Not Installed",
                                style = MaterialTheme.typography.bodySmall,
                                color = if (isSttReady) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                            )
                        }
                        if (!isSttReady) {
                            Button(onClick = { settingsViewModel.downloadStt() }) {
                                Text("Download")
                            }
                        }
                    }

                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                    // Hindi TTS Status
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("TTS Voice — Hindi (VITS)", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                if (isHiTtsReady) "✅ Installed & Ready" else "⚠️ Not Installed",
                                style = MaterialTheme.typography.bodySmall,
                                color = if (isHiTtsReady) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                            )
                        }
                        if (!isHiTtsReady) {
                            Button(onClick = { settingsViewModel.downloadTts("hi") }) {
                                Text("Download")
                            }
                        }
                    }

                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                    // English TTS Status
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("TTS Voice — English (VITS)", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                if (isEnTtsReady) "✅ Installed & Ready" else "⚠️ Not Installed",
                                style = MaterialTheme.typography.bodySmall,
                                color = if (isEnTtsReady) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                            )
                        }
                        if (!isEnTtsReady) {
                            Button(onClick = { settingsViewModel.downloadTts("en") }) {
                                Text("Download")
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    when (val state = downloadState) {
                        is com.itantra.speech.DownloadState.Downloading -> {
                            Column(modifier = Modifier.fillMaxWidth()) {
                                Text(
                                    "Downloading ${state.item}: ${state.progressPercent}%",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                LinearProgressIndicator(
                                    progress = { state.progressPercent / 100f },
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                        }
                        is com.itantra.speech.DownloadState.Completed -> {
                            Text(
                                "🎉 ${state.message}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        is com.itantra.speech.DownloadState.Error -> {
                            Text(
                                "❌ ${state.message}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                        is com.itantra.speech.DownloadState.Idle -> {
                            if (!isSttReady || !isHiTtsReady || !isEnTtsReady) {
                                OutlinedButton(
                                    onClick = { settingsViewModel.downloadAllEssentials() },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text("Download All Essential Models")
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text("Speech Engine Calibration", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Primary Language: $selectedLanguage", style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    languages.forEach { (code, name) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(name, style = MaterialTheme.typography.bodySmall)
                            RadioButton(
                                selected = selectedLanguage == code,
                                onClick = { transceiverViewModel.setLanguage(code) }
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text("Audio & Transceiver", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("TTS Playback Speed: ${String.format("%.1f", ttsSpeed)}x")
                    Slider(
                        value = ttsSpeed,
                        onValueChange = { ttsSpeed = it },
                        valueRange = 0.5f..2.0f,
                        steps = 5
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Auto-Play Received Voice")
                        Switch(
                            checked = autoPlayAudio,
                            onCheckedChange = { autoPlayAudio = it }
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Hold-to-Talk Mode")
                        Switch(
                            checked = pttHoldMode,
                            onCheckedChange = { pttHoldMode = it }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text("On-Device Footprint", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("• VAD Engine: Silero VAD (2.3 MB on disk)", style = MaterialTheme.typography.bodySmall)
                    Text("• STT Engine: Sherpa-ONNX Zipformer (INT8)", style = MaterialTheme.typography.bodySmall)
                    Text("• TTS Engine: Piper / VITS Multilingual", style = MaterialTheme.typography.bodySmall)
                    Text("• Max Target RAM: < 420 MB (ISRO Spec)", style = MaterialTheme.typography.bodySmall)
                    Text("• Bitrate Target: ~160 bps Semantic Compression", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
