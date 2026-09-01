package com.itantra.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.itantra.alerts.AlertBroadcaster
import com.itantra.alerts.AlertEvent
import com.itantra.alerts.AlertReceiver
import com.itantra.data.MessageLogDao
import com.itantra.data.entities.MessageEntity
import com.itantra.network.TransceiverManager
import com.itantra.network.WifiDirectManager
import com.itantra.speech.CommPipeline
import com.itantra.speech.SherpaOnnxSpeechEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

@HiltViewModel
class TransceiverViewModel @Inject constructor(
    private val commPipeline: CommPipeline,
    private val transceiverManager: TransceiverManager,
    private val wifiDirectManager: WifiDirectManager,
    private val alertBroadcaster: AlertBroadcaster,
    private val alertReceiver: AlertReceiver,
    private val speechEngine: SherpaOnnxSpeechEngine,
    private val messageLogDao: MessageLogDao
) : ViewModel() {

    val deviceId: String = UUID.randomUUID().toString().take(8)

    val messageHistory: StateFlow<List<MessageEntity>> = messageLogDao.getAllMessages()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val activeAlert: StateFlow<AlertEvent?> = alertReceiver.activeAlert

    val connectionStatus: StateFlow<String> = wifiDirectManager.connectionStatus

    private val _isTransmitting = MutableStateFlow(false)
    val isTransmitting: StateFlow<Boolean> = _isTransmitting.asStateFlow()

    private val _selectedLanguage = MutableStateFlow("hi")
    val selectedLanguage: StateFlow<String> = _selectedLanguage.asStateFlow()

    init {
        // Automatically save incoming packets to Room history and synthesize voice
        viewModelScope.launch {
            transceiverManager.incomingPackets.collect { packet ->
                val entity = MessageEntity(
                    senderId = packet.senderId,
                    text = packet.transcript,
                    languageCode = packet.languageCode,
                    type = packet.type.name,
                    timestamp = packet.timestampMs,
                    isIncoming = true
                )
                messageLogDao.insertMessage(entity)

                if (packet.type == com.itantra.proto.TransceiverPacketProto.TransceiverPacket.PacketType.VOICE) {
                    speechEngine.synthesizeSpeech(packet.transcript, packet.languageCode)
                }
            }
        }
    }

    fun onPttPressed() {
        if (!_isTransmitting.value) {
            _isTransmitting.value = true
            commPipeline.startTransmission(deviceId)
        }
    }

    fun onPttReleased() {
        if (_isTransmitting.value) {
            _isTransmitting.value = false
            commPipeline.stopTransmission()
        }
    }

    fun setLanguage(code: String) {
        _selectedLanguage.value = code
    }

    fun sendEmergencyAlert(alertText: String) {
        viewModelScope.launch {
            alertBroadcaster.broadcastAlert(
                senderId = deviceId,
                languageCode = _selectedLanguage.value,
                alertText = alertText
            )
            // Log outgoing alert in local DB
            messageLogDao.insertMessage(
                MessageEntity(
                    senderId = deviceId,
                    text = alertText,
                    languageCode = _selectedLanguage.value,
                    type = "ALERT",
                    timestamp = System.currentTimeMillis(),
                    isIncoming = false
                )
            )
        }
    }

    fun dismissAlert() {
        alertReceiver.dismissAlert()
    }

    fun startPeerDiscovery() {
        wifiDirectManager.startDiscovery()
    }
}
