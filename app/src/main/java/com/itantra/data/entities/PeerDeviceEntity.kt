package com.itantra.data.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "peers")
data class PeerDeviceEntity(
    @PrimaryKey
    val deviceId: String,
    val displayName: String,
    val lastConnected: Long = System.currentTimeMillis(),
    val transportType: String = "WIFI_DIRECT",
    val isConnected: Boolean = false
)
