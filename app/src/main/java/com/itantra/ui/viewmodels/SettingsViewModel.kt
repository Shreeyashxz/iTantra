package com.itantra.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.itantra.data.SettingsDao
import com.itantra.data.entities.UserSettingsEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsDao: SettingsDao
) : ViewModel() {

    val userSettings: StateFlow<UserSettingsEntity?> = settingsDao.getSettings()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    fun updateSettings(update: (UserSettingsEntity) -> UserSettingsEntity) {
        viewModelScope.launch {
            val current = userSettings.value ?: UserSettingsEntity()
            settingsDao.saveSettings(update(current))
        }
    }
}
