package com.itantra.data.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "user_settings")
data class UserSettingsEntity(
    @PrimaryKey
    val id: Int = 1,
    val preferredLanguage: String = "hi",
    val ttsSpeed: Float = 1.0f,
    val pttMode: String = "HOLD", // HOLD or TOGGLE
    val installedLanguagePacks: String = "hi,en",
    val alertVolumeMax: Boolean = true
)
