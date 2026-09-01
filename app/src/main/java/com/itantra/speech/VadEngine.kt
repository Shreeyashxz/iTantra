package com.itantra.speech

import kotlinx.coroutines.flow.Flow

interface VadEngine {
    fun startVad(audioData: Flow<ShortArray>): Flow<Boolean>
    fun stopVad()
    fun release()
}
