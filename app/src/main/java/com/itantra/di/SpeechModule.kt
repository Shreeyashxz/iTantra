package com.itantra.di

import com.itantra.speech.SherpaOnnxSpeechEngine
import com.itantra.speech.SileroVadEngine
import com.itantra.speech.SpeechEngine
import com.itantra.speech.VadEngine
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class SpeechModule {

    @Binds
    @Singleton
    abstract fun bindSpeechEngine(engine: SherpaOnnxSpeechEngine): SpeechEngine

    @Binds
    @Singleton
    abstract fun bindVadEngine(engine: SileroVadEngine): VadEngine
}
