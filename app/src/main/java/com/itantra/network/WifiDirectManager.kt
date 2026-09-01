package com.itantra.network

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WifiDirectManager @Inject constructor(
    private val context: Context,
    private val transceiverManager: TransceiverManager
) {
    private val wifiP2pManager: WifiP2pManager? by lazy {
        context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    }
    private var channel: WifiP2pManager.Channel? = null
    
    private val _peers = MutableStateFlow<List<WifiP2pDevice>>(emptyList())
    val peers: StateFlow<List<WifiP2pDevice>> = _peers
    
    private val _connectionStatus = MutableStateFlow("Disconnected")
    val connectionStatus: StateFlow<String> = _connectionStatus

    private val receiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    wifiP2pManager?.requestPeers(channel) { peerList ->
                        _peers.value = peerList.deviceList.toList()
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    wifiP2pManager?.requestConnectionInfo(channel) { info ->
                        if (info.groupFormed) {
                            _connectionStatus.value = "Connected"
                            if (info.isGroupOwner) {
                                // Start server socket
                            } else {
                                // Connect as client to info.groupOwnerAddress.hostAddress
                            }
                        } else {
                            _connectionStatus.value = "Disconnected"
                        }
                    }
                }
            }
        }
    }

    init {
        channel = wifiP2pManager?.initialize(context, context.mainLooper, null)
    }

    fun startDiscovery() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(receiver, intentFilter)

        @SuppressLint("MissingPermission")
        wifiP2pManager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                _connectionStatus.value = "Discovering..."
            }
            override fun onFailure(reason: Int) {
                _connectionStatus.value = "Discovery Failed"
            }
        })
    }

    fun stopDiscovery() {
        try {
            context.unregisterReceiver(receiver)
            wifiP2pManager?.stopPeerDiscovery(channel, null)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
