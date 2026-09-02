package com.itantra.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.itantra.data.SettingsDao
import com.itantra.data.entities.UserSettingsEntity
import com.itantra.speech.DownloadState
import com.itantra.speech.LanguagePackManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsDao: SettingsDao,
    val languagePackManager: LanguagePackManager
) : ViewModel() {

    val userSettings: StateFlow<UserSettingsEntity?> = settingsDao.getSettings()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val downloadState: StateFlow<DownloadState> = languagePackManager.downloadState

    fun isSttAvailable(): Boolean = languagePackManager.isSttAvailable()
    fun isTtsAvailable(languageCode: String): Boolean = languagePackManager.isTtsAvailable(languageCode)

    fun downloadStt() {
        viewModelScope.launch {
            languagePackManager.downloadStt()
        }
    }

    fun downloadTts(languageCode: String) {
        viewModelScope.launch {
            languagePackManager.downloadTts(languageCode)
        }
    }

    fun downloadAllEssentials() {
        viewModelScope.launch {
            languagePackManager.downloadAllEssentials { }
        }
    }

    fun updateSettings(update: (UserSettingsEntity) -> UserSettingsEntity) {
        viewModelScope.launch {
            val current = userSettings.value ?: UserSettingsEntity()
            settingsDao.saveSettings(update(current))
        }
    }
}
