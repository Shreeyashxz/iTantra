package com.itantra.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.itantra.data.entities.PeerDeviceEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PeerDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrUpdatePeer(peer: PeerDeviceEntity)

    @Query("SELECT * FROM peers ORDER BY lastConnected DESC")
    fun getAllPeers(): Flow<List<PeerDeviceEntity>>

    @Query("DELETE FROM peers WHERE deviceId = :deviceId")
    suspend fun deletePeer(deviceId: String)
}
