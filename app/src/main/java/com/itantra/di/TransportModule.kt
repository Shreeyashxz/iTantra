package com.itantra.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
object TransportModule {
    // TODO: Provide Wi-Fi Direct and BLE transport managers here
}
