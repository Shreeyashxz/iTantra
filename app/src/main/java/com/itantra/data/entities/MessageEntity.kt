package com.itantra.data.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val senderId: String,
    val text: String,
    val languageCode: String = "hi",
    val type: String = "VOICE", // VOICE, ALERT, ACK
    val timestamp: Long = System.currentTimeMillis(),
    val isIncoming: Boolean = false
)
