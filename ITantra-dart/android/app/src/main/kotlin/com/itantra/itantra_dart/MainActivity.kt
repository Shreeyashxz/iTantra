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

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
import java.util.UUID
import java.util.HashSet

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
    private val BLE_CHANNEL = "com.itantra/ble"
    private val BLE_EVENT_CHANNEL = "com.itantra/ble_events"

    private val BLE_SERVICE_UUID = UUID.fromString("0000FE60-0000-1000-8000-00805F9B34FB")
    private val BLE_CHAR_TX_UUID = UUID.fromString("0000FE61-0000-1000-8000-00805F9B34FB")
    private val BLE_CHAR_RX_UUID = UUID.fromString("0000FE62-0000-1000-8000-00805F9B34FB")

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

        // 3. BLE Fallback Platform Channel
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
        bluetoothAdapter = bluetoothManager?.adapter

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL).setMethodCallHandler { call, result ->
            handleBleCall(call, result)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bleEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    bleEventSink = null
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

    // =========================================================================
    // Bluetooth Low Energy (BLE) Fallback Transport Implementation
    // =========================================================================
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleGattServer: BluetoothGattServer? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var connectedGattClient: BluetoothGatt? = null
    private var bleEventSink: EventChannel.EventSink? = null
    private var isBleAdvertising = false
    private var isBleScanning = false
    private var isBleConnected = false
    private val connectedGattDevices = HashSet<BluetoothDevice>()

    private val bleScanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val device = result?.device ?: return
            val name = device.name ?: result.scanRecord?.deviceName ?: "iTantra-Node-${device.address.takeLast(4)}"
            sendBleEvent("PEER_DISCOVERED", mapOf(
                "name" to name,
                "address" to device.address,
                "rssi" to result.rssi
            ))
        }

        override fun onScanFailed(errorCode: Int) {
            sendBleEvent("SCAN_STATE", mapOf("scanning" to false, "error" to "Scan failed with code: $errorCode"))
        }
    }

    private val bleAdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isBleAdvertising = true
            sendBleEvent("ADVERTISING_STATE", mapOf("advertising" to true))
        }

        override fun onStartFailure(errorCode: Int) {
            isBleAdvertising = false
            sendBleEvent("ADVERTISING_STATE", mapOf("advertising" to false, "error" to "Advertise failed with code: $errorCode"))
        }
    }

    private val bleGattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            if (device == null) return
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedGattDevices.add(device)
                isBleConnected = true
                sendBleEvent("CONNECTION_STATE", mapOf(
                    "connected" to true,
                    "address" to device.address,
                    "name" to (device.name ?: "iTantra Remote Node"),
                    "role" to "SERVER"
                ))
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedGattDevices.remove(device)
                if (connectedGattDevices.isEmpty() && connectedGattClient == null) {
                    isBleConnected = false
                    sendBleEvent("CONNECTION_STATE", mapOf(
                        "connected" to false,
                        "address" to device.address,
                        "role" to "SERVER"
                    ))
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (responseNeeded && device != null) {
                bleGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
            if (value != null && value.isNotEmpty()) {
                sendBleEvent("GATT_CHUNK_RECEIVED", mapOf(
                    "chunk" to value,
                    "from" to (device?.address ?: "UNKNOWN")
                ))
            }
        }
    }

    private val bleGattClientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (gatt == null) return
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedGattClient?.close()
                connectedGattClient = null
                isBleConnected = false
                sendBleEvent("CONNECTION_STATE", mapOf(
                    "connected" to false,
                    "address" to gatt.device.address,
                    "role" to "CLIENT"
                ))
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && gatt != null) {
                val service = gatt.getService(BLE_SERVICE_UUID)
                val txChar = service?.getCharacteristic(BLE_CHAR_TX_UUID)
                if (txChar != null) {
                    gatt.setCharacteristicNotification(txChar, true)
                }
                isBleConnected = true
                sendBleEvent("CONNECTION_STATE", mapOf(
                    "connected" to true,
                    "address" to gatt.device.address,
                    "name" to (gatt.device.name ?: "iTantra Remote Peer"),
                    "role" to "CLIENT"
                ))
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?) {
            @Suppress("DEPRECATION")
            val value = characteristic?.value
            if (value != null && value.isNotEmpty()) {
                sendBleEvent("GATT_CHUNK_RECEIVED", mapOf(
                    "chunk" to value,
                    "from" to (gatt?.device?.address ?: "UNKNOWN")
                ))
            }
        }
    }

    private fun handleBleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(bluetoothAdapter != null)
            }
            "startAdvertising" -> {
                val name = call.argument<String>("name") ?: "iTantra-Node"
                val ok = startBleAdvertising(name)
                result.success(ok)
            }
            "stopAdvertising" -> {
                stopBleAdvertising()
                result.success(true)
            }
            "startScanning" -> {
                val ok = startBleScanning()
                result.success(ok)
            }
            "stopScanning" -> {
                stopBleScanning()
                result.success(true)
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrEmpty()) {
                    result.error("INVALID_ARG", "Address cannot be empty", null)
                    return
                }
                val ok = connectBleGatt(address)
                result.success(ok)
            }
            "disconnect" -> {
                disconnectBleGatt()
                result.success(true)
            }
            "sendChunk" -> {
                val chunk = call.argument<ByteArray>("chunk")
                if (chunk == null || chunk.isEmpty()) {
                    result.error("INVALID_ARG", "Chunk cannot be empty", null)
                    return
                }
                val ok = sendBleChunk(chunk)
                result.success(ok)
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun startBleAdvertising(nodeName: String): Boolean {
        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) return false
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser ?: return false

        try {
            if (bleGattServer == null) {
                bleGattServer = bluetoothManager?.openGattServer(this, bleGattServerCallback)
                val service = BluetoothGattService(BLE_SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

                val txChar = BluetoothGattCharacteristic(
                    BLE_CHAR_TX_UUID,
                    BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                    BluetoothGattCharacteristic.PERMISSION_READ
                )
                val rxChar = BluetoothGattCharacteristic(
                    BLE_CHAR_RX_UUID,
                    BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                    BluetoothGattCharacteristic.PERMISSION_WRITE
                )
                service.addCharacteristic(txChar)
                service.addCharacteristic(rxChar)
                bleGattServer?.addService(service)
            }

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(BLE_SERVICE_UUID))
                .build()

            bleAdvertiser?.startAdvertising(settings, data, bleAdvertiseCallback)
            return true
        } catch (e: Exception) {
            sendBleEvent("ADVERTISING_STATE", mapOf("advertising" to false, "error" to (e.localizedMessage ?: "Failed to start advertiser")))
            return false
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBleAdvertising() {
        try {
            bleAdvertiser?.stopAdvertising(bleAdvertiseCallback)
        } catch (_: Exception) {}
        isBleAdvertising = false
        sendBleEvent("ADVERTISING_STATE", mapOf("advertising" to false))
    }

    @SuppressLint("MissingPermission")
    private fun startBleScanning(): Boolean {
        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) return false
        bleScanner = bluetoothAdapter?.bluetoothLeScanner ?: return false

        try {
            val filter = ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(BLE_SERVICE_UUID))
                .build()

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

            isBleScanning = true
            bleScanner?.startScan(listOf(filter), settings, bleScanCallback)
            sendBleEvent("SCAN_STATE", mapOf("scanning" to true))
            return true
        } catch (e: Exception) {
            isBleScanning = false
            sendBleEvent("SCAN_STATE", mapOf("scanning" to false, "error" to (e.localizedMessage ?: "Failed to start scanner")))
            return false
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBleScanning() {
        try {
            bleScanner?.stopScan(bleScanCallback)
        } catch (_: Exception) {}
        isBleScanning = false
        sendBleEvent("SCAN_STATE", mapOf("scanning" to false))
    }

    @SuppressLint("MissingPermission")
    private fun connectBleGatt(address: String): Boolean {
        if (bluetoothAdapter == null) return false
        try {
            val device = bluetoothAdapter?.getRemoteDevice(address) ?: return false
            connectedGattClient?.close()
            connectedGattClient = device.connectGatt(this, false, bleGattClientCallback)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    @SuppressLint("MissingPermission")
    private fun disconnectBleGatt() {
        try {
            connectedGattClient?.disconnect()
            connectedGattClient?.close()
            connectedGattClient = null
            connectedGattDevices.clear()
            isBleConnected = false
            sendBleEvent("CONNECTION_STATE", mapOf("connected" to false))
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun sendBleChunk(chunk: ByteArray): Boolean {
        var sent = false
        val client = connectedGattClient
        if (client != null && isBleConnected) {
            val service = client.getService(BLE_SERVICE_UUID)
            val rxChar = service?.getCharacteristic(BLE_CHAR_RX_UUID)
            if (rxChar != null) {
                rxChar.value = chunk
                rxChar.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                client.writeCharacteristic(rxChar)
                sent = true
            }
        }
        val server = bleGattServer
        if (server != null && connectedGattDevices.isNotEmpty()) {
            val service = server.getService(BLE_SERVICE_UUID)
            val txChar = service?.getCharacteristic(BLE_CHAR_TX_UUID)
            if (txChar != null) {
                txChar.value = chunk
                for (device in connectedGattDevices) {
                    server.notifyCharacteristicChanged(device, txChar, false)
                    sent = true
                }
            }
        }
        return sent
    }

    private fun sendBleEvent(eventType: String, data: Map<String, Any>) {
        val payload = HashMap<String, Any>(data)
        payload["eventType"] = eventType
        runOnUiThread {
            bleEventSink?.success(payload)
        }
    }

    override fun onDestroy() {
        unregisterP2pReceiver()
        stopBleAdvertising()
        stopBleScanning()
        disconnectBleGatt()
        try {
            bleGattServer?.close()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
