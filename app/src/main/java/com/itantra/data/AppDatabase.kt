package com.itantra.data

import androidx.room.Database
import androidx.room.RoomDatabase
import com.itantra.data.entities.MessageEntity
import com.itantra.data.entities.PeerDeviceEntity
import com.itantra.data.entities.UserSettingsEntity

@Database(
    entities = [
        MessageEntity::class,
        PeerDeviceEntity::class,
        UserSettingsEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun messageLogDao(): MessageLogDao
    abstract fun peerDao(): PeerDao
    abstract fun settingsDao(): SettingsDao
}
