package com.itantra.di

import android.content.Context
import androidx.room.Room
import com.itantra.data.AppDatabase
import com.itantra.data.MessageLogDao
import com.itantra.data.PeerDao
import com.itantra.data.SettingsDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideAppDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "itantra_database"
        ).fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideMessageLogDao(database: AppDatabase): MessageLogDao {
        return database.messageLogDao()
    }

    @Provides
    fun providePeerDao(database: AppDatabase): PeerDao {
        return database.peerDao()
    }

    @Provides
    fun provideSettingsDao(database: AppDatabase): SettingsDao {
        return database.settingsDao()
    }
}
