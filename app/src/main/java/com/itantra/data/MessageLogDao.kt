package com.itantra.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.itantra.data.entities.MessageEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MessageLogDao {
    @Insert
    suspend fun insertMessage(message: MessageEntity)

    @Query("SELECT * FROM messages ORDER BY timestamp DESC")
    fun getAllMessages(): Flow<List<MessageEntity>>
}
