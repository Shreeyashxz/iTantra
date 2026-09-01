package com.itantra.speech

import kotlinx.coroutines.flow.Flow

interface SpeechEngine {
    fun startListening(): Flow<String>
    fun stopListening()
    
    suspend fun synthesizeSpeech(text: String, languageCode: String)
    fun stopSpeech()
    
    fun release()
}
