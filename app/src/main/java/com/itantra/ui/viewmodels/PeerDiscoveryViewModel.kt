package com.itantra.ui.viewmodels

import android.net.wifi.p2p.WifiP2pDevice
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
    val peers: StateFlow<List<WifiP2pDevice>> = wifiDirectManager.peers
    
    val deviceId = "ITANTRA_${android.os.Build.MODEL.replace(" ", "_")}"

    fun startPeerDiscovery() {
        wifiDirectManager.startDiscovery()
    }

    fun connectToPeer(device: WifiP2pDevice) {
        wifiDirectManager.connect(device)
    }

    fun disconnect() {
        wifiDirectManager.disconnect()
    }
}
