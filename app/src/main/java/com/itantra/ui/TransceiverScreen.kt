package com.itantra.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.itantra.data.entities.MessageEntity
import com.itantra.ui.viewmodels.TransceiverViewModel
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransceiverScreen(
    onNavigateBack: () -> Unit,
    onNavigateToAlerts: () -> Unit = {},
    onNavigateToDiscovery: () -> Unit = {},
    viewModel: TransceiverViewModel = hiltViewModel()
) {
    val isTransmitting by viewModel.isTransmitting.collectAsState()
    val messages by viewModel.messageHistory.collectAsState()
    val connectionStatus by viewModel.connectionStatus.collectAsState()
    val selectedLanguage by viewModel.selectedLanguage.collectAsState()
    val activeAlert by viewModel.activeAlert.collectAsState()
    val listState = rememberLazyListState()

    val languages = listOf(
        "hi" to "हिंदी",
        "en" to "English",
        "gu" to "ગુજરાતી",
        "mr" to "मराठी",
        "kn" to "ಕನ್ನಡ",
        "ml" to "മലയാളം",
        "ta" to "தமிழ்",
        "te" to "తెలుగు",
        "or" to "ଓଡ଼ିଆ",
        "bn" to "বাংলা"
    )

    // Pulsing animation when transmitting
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = if (isTransmitting) 1.18f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("iTantra Transceiver", style = MaterialTheme.typography.titleMedium)
                        Text(
                            text = "Link: $connectionStatus",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (connectionStatus == "Connected") Color(0xFF4CAF50) else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onNavigateToAlerts) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = "Emergency Alert",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background)
        ) {
            // Incoming Alert Banner
            AnimatedVisibility(visible = activeAlert != null) {
                activeAlert?.let { alert ->
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Warning, contentDescription = "Alert", tint = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.width(8.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text("EMERGENCY ALERT", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onErrorContainer)
                                Text(alert.text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer)
                            }
                            TextButton(onClick = { viewModel.dismissAlert() }) {
                                Text("DISMISS")
                            }
                        }
                    }
                }
            }

            // Language Selector Chips
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                languages.forEach { (code, name) ->
                    FilterChip(
                        selected = selectedLanguage == code,
                        onClick = { viewModel.setLanguage(code) },
                        label = { Text(name) }
                    )
                }
            }

            Divider()

            // Chat & Transcript Stream
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (messages.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                "No transmissions yet.\nHold Push-To-Talk to speak.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                } else {
                    items(messages) { message ->
                        MessageBubble(message = message)
                    }
                }
            }

            // Status indicator
            if (isTransmitting) {
                Text(
                    text = "Transmitting voice payload (160 bps)...",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )
            }

            // Push-To-Talk Button Area
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .size(130.dp)
                        .scale(pulseScale)
                        .clip(CircleShape)
                        .background(
                            if (isTransmitting) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.primary
                        )
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onPress = {
                                    viewModel.onPttPressed()
                                    tryAwaitRelease()
                                    viewModel.onPttReleased()
                                }
                            )
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = Icons.Default.Mic,
                            contentDescription = "Push to Talk",
                            tint = Color.White,
                            modifier = Modifier.size(52.dp)
                        )
                        Text(
                            text = if (isTransmitting) "RECORDING" else "HOLD PTT",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun MessageBubble(message: MessageEntity) {
    val isIncoming = message.isIncoming
    val isAlert = message.type == "ALERT"
    val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isIncoming) Arrangement.Start else Arrangement.End
    ) {
        Card(
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(
                containerColor = when {
                    isAlert -> MaterialTheme.colorScheme.errorContainer
                    isIncoming -> MaterialTheme.colorScheme.surfaceVariant
                    else -> MaterialTheme.colorScheme.primaryContainer
                }
            ),
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            Column(modifier = Modifier.padding(10.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = if (isIncoming) "From: ${message.senderId}" else "You",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline
                    )
                    Text(
                        text = timeFormat.format(Date(message.timestamp)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = message.text,
                    style = MaterialTheme.typography.bodyMedium
                )
                if (isAlert) {
                    Text(
                        text = "🚨 PRIORITY DISTRESS ALERT",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}
