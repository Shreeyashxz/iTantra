package com.itantra.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToTransceiver: () -> Unit,
    onNavigateToDiscovery: () -> Unit,
    onNavigateToAlerts: () -> Unit,
    onNavigateToHistory: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("iTantra Dashboard") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("ISRO • SIH 26173", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text("Neural Transceiver for Low-Bitrate Links", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Multilingual voice compression (160 bps) via local on-device VAD, STT, and TTS across 10 Indian languages.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Quick Action Grid
            ActionTile(
                title = "Push-To-Talk Transceiver",
                subtitle = "Hold-to-talk semantic voice streaming",
                icon = Icons.Default.Mic,
                color = MaterialTheme.colorScheme.primary,
                onClick = onNavigateToTransceiver
            )

            ActionTile(
                title = "Emergency Distress Alert",
                subtitle = "Max volume, non-interruptible alert broadcast",
                icon = Icons.Default.Warning,
                color = MaterialTheme.colorScheme.error,
                onClick = onNavigateToAlerts
            )

            ActionTile(
                title = "Peer Discovery & Mesh",
                subtitle = "Connect devices over Wi-Fi Direct P2P",
                icon = Icons.Default.Wifi,
                color = MaterialTheme.colorScheme.secondary,
                onClick = onNavigateToDiscovery
            )

            ActionTile(
                title = "Transmission History",
                subtitle = "View and search offline message logs",
                icon = Icons.Default.History,
                color = MaterialTheme.colorScheme.tertiary,
                onClick = onNavigateToHistory
            )

            ActionTile(
                title = "Settings & Calibration",
                subtitle = "Language selection, TTS speed & models",
                icon = Icons.Default.Settings,
                color = MaterialTheme.colorScheme.outline,
                onClick = onNavigateToSettings
            )
        }
    }
}

@Composable
fun ActionTile(
    title: String,
    subtitle: String,
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .background(color.copy(alpha = 0.15f), shape = RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(imageVector = icon, contentDescription = title, tint = color)
            }
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = title, style = MaterialTheme.typography.titleSmall)
                Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
            Icon(Icons.Default.ArrowForward, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
        }
    }
}
