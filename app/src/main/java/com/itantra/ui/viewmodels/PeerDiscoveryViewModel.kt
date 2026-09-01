package com.itantra.ui.viewmodels

import androidx.lifecycle.ViewModel
import com.itantra.network.WifiDirectManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class PeerDiscoveryViewModel @Inject constructor(
    private val wifiDirectManager: WifiDirectManager
) : ViewModel() {

    val connectionStatus: StateFlow<String> = wifiDirectManager.connectionStatus
    
    // We can expose the device ID here as well, maybe a placeholder or from settings
    val deviceId = "ITANTRA_PEER"

    fun startPeerDiscovery() {
        wifiDirectManager.startDiscovery()
    }
}
