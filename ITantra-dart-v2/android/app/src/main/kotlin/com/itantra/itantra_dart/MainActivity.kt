package com.itantra.itantra_dart

import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        init {
            try {
                System.loadLibrary("onnxruntime")
            } catch (_: UnsatisfiedLinkError) {
            }
            try {
                System.loadLibrary("sherpa-onnx-c-api")
            } catch (_: UnsatisfiedLinkError) {
            }
        }
    }

    private val ALERT_CHANNEL = "com.itantra/hardware_alert"
    private val WIFI_DIRECT_CHANNEL = "com.itantra/wifi_direct"
    private val WIFI_DIRECT_EVENT_CHANNEL = "com.itantra/wifi_direct_events"

    // Wi-Fi Direct references
    private var wifiP2pManager: WifiP2pManager? = null
    private var wifiP2pChannel: WifiP2pManager.Channel? = null
    private var p2pEventSink: EventChannel.EventSink? = null
    private var isReceiverRegistered = false

    private val p2pReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val isEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    sendP2pEvent("STATE_CHANGED", mapOf("enabled" to isEnabled))
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    wifiP2pManager?.requestPeers(wifiP2pChannel) { peerList: WifiP2pDeviceList ->
                        val peers = peerList.deviceList.map { device: WifiP2pDevice ->
                            mapOf(
                                "deviceName" to (device.deviceName ?: "Unknown Device"),
                                "deviceAddress" to device.deviceAddress,
                                "primaryDeviceType" to (device.primaryDeviceType ?: ""),
                                "status" to device.status,
                                "isGroupOwner" to device.isGroupOwner
                            )
                        }
                        sendP2pEvent("PEERS_CHANGED", mapOf("peers" to peers))
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    wifiP2pManager?.requestConnectionInfo(wifiP2pChannel) { info: WifiP2pInfo? ->
                        if (info != null) {
                            val hostAddress = info.groupOwnerAddress?.hostAddress ?: ""
                            sendP2pEvent(
                                "CONNECTION_CHANGED",
                                mapOf(
                                    "groupFormed" to info.groupFormed,
                                    "isGroupOwner" to info.isGroupOwner,
                                    "groupOwnerAddress" to hostAddress
                                )
                            )
                        }
                    }
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE, WifiP2pDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    }
                    if (device != null) {
                        sendP2pEvent(
                            "THIS_DEVICE_CHANGED",
                            mapOf(
                                "deviceName" to (device.deviceName ?: ""),
                                "deviceAddress" to device.deviceAddress
                            )
                        )
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Hardware Emergency Alert Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALERT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerHardwareAlert" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, AudioManager.FLAG_PLAY_SOUND)

                        triggerTactileVibration()
                        result.success(mapOf("status" to "triggered", "volume" to maxVol))
                    } catch (e: Exception) {
                        result.error("ALERT_FAIL", e.localizedMessage, null)
                    }
                }
                "checkDndPermission" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.isNotificationPolicyAccessGranted)
                }
                "requestDndPermission" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Wi-Fi Direct Native Channel
        wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
        wifiP2pChannel = wifiP2pManager?.initialize(this, mainLooper, null)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_DIRECT_CHANNEL).setMethodCallHandler { call, result ->
            handleWifiDirectCall(call, result)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_DIRECT_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    p2pEventSink = events
                    registerP2pReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    p2pEventSink = null
                    unregisterP2pReceiver()
                }
            }
        )
    }

    private fun handleWifiDirectCall(call: MethodCall, result: MethodChannel.Result) {
        if (wifiP2pManager == null || wifiP2pChannel == null) {
            result.error("P2P_UNAVAILABLE", "Wi-Fi P2P manager is not supported on this device", null)
            return
        }

        when (call.method) {
            "startDiscovery" -> {
                registerP2pReceiver()
                try {
                    wifiP2pManager?.discoverPeers(wifiP2pChannel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }
                        override fun onFailure(reasonCode: Int) {
                            result.error("DISCOVERY_FAILED", "Reason: $reasonCode", null)
                        }
                    })
                } catch (e: SecurityException) {
                    result.error("PERMISSION_DENIED", e.localizedMessage, null)
                }
            }
            "stopDiscovery" -> {
                try {
                    wifiP2pManager?.stopPeerDiscovery(wifiP2pChannel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }
                        override fun onFailure(reasonCode: Int) {
                            result.error("STOP_FAILED", "Reason: $reasonCode", null)
                        }
                    })
                } catch (e: Exception) {
                    result.error("EXCEPTION", e.localizedMessage, null)
                }
            }
            "connect" -> {
                val address = call.argument<String>("deviceAddress")
                if (address.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "Missing deviceAddress", null)
                    return
                }

                val config = WifiP2pConfig().apply {
                    deviceAddress = address
                    wps.setup = WpsInfo.PBC
                }

                try {
                    wifiP2pManager?.connect(wifiP2pChannel, config, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }
                        override fun onFailure(reasonCode: Int) {
                            result.error("CONNECT_FAILED", "Reason: $reasonCode", null)
                        }
                    })
                } catch (e: SecurityException) {
                    result.error("PERMISSION_DENIED", e.localizedMessage, null)
                }
            }
            "disconnect" -> {
                try {
                    wifiP2pManager?.removeGroup(wifiP2pChannel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }
                        override fun onFailure(reasonCode: Int) {
                            result.error("DISCONNECT_FAILED", "Reason: $reasonCode", null)
                        }
                    })
                } catch (e: Exception) {
                    result.error("EXCEPTION", e.localizedMessage, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun registerP2pReceiver() {
        if (!isReceiverRegistered) {
            val intentFilter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }
            registerReceiver(p2pReceiver, intentFilter)
            isReceiverRegistered = true
        }
    }

    private fun unregisterP2pReceiver() {
        if (isReceiverRegistered) {
            try {
                unregisterReceiver(p2pReceiver)
            } catch (_: Exception) {}
            isReceiverRegistered = false
        }
    }

    private fun sendP2pEvent(eventType: String, data: Map<String, Any>) {
        val payload = HashMap<String, Any>(data)
        payload["eventType"] = eventType
        runOnUiThread {
            p2pEventSink?.success(payload)
        }
    }

    private fun triggerTactileVibration() {
        try {
            val pattern = longArrayOf(0, 400, 150, 400, 150, 600)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(pattern, -1)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        unregisterP2pReceiver()
        super.onDestroy()
    }
}
