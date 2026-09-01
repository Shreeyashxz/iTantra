package com.itantra.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.itantra.ui.viewmodels.TransceiverViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlertScreen(
    onNavigateBack: () -> Unit,
    viewModel: TransceiverViewModel = hiltViewModel()
) {
    var customAlertText by remember { mutableStateOf("") }
    var sentMessage by remember { mutableStateOf<String?>(null) }

    val presetAlerts = listOf(
        "Emergency! Immediate assistance required.",
        "Medical emergency! Send doctor or ambulance.",
        "Distress alert! Lost signal / navigation failure.",
        "Severe weather alert! Evacuate immediately.",
        "Fire hazard detected! Need urgent backup."
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Emergency Distress Broadcast", color = MaterialTheme.colorScheme.onError) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.onError)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.error
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background)
                .padding(16.dp)
        ) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = "Warning",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(36.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        "Alerts transmit with maximum priority and play on receiver devices at non-interruptible volume.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text("Quick Distress Templates", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(presetAlerts) { alert ->
                    OutlinedCard(
                        onClick = {
                            viewModel.sendEmergencyAlert(alert)
                            sentMessage = alert
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(alert, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                            Icon(Icons.Default.Send, contentDescription = "Send", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }

            if (sentMessage != null) {
                Text(
                    text = "Broadcast dispatched: \"$sentMessage\"",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Custom alert input
            OutlinedTextField(
                value = customAlertText,
                onValueChange = { customAlertText = it },
                label = { Text("Custom Emergency Message") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = {
                    if (customAlertText.isNotBlank()) {
                        viewModel.sendEmergencyAlert(customAlertText)
                        sentMessage = customAlertText
                        customAlertText = ""
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Warning, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("BROADCAST CUSTOM ALERT")
            }
        }
    }
}
