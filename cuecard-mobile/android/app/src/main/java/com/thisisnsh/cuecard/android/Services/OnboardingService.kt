package com.thisisnsh.cuecard.android.services

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first

/**
 * Its own store, rather than a key beside the settings, so Auto Backup can leave
 * this one flag behind while still carrying the scripts over. The file name is
 * the one the backup rules exclude: see `res/xml/data_extraction_rules.xml`.
 */
private val Context.onboardingDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "cuecard_onboarding"
)

/**
 * Whether the welcome screen has been through. Kept on the device and nowhere
 * else, so a fresh install opens on it again.
 */
class OnboardingService private constructor(private val context: Context) {

    /** Null until the flag has been read: neither screen is right to show yet. */
    private val _hasSeenWelcome = MutableStateFlow<Boolean?>(null)
    val hasSeenWelcome: StateFlow<Boolean?> = _hasSeenWelcome.asStateFlow()

    suspend fun load() {
        _hasSeenWelcome.value = context.onboardingDataStore.data.first()[HAS_SEEN_WELCOME] ?: false
    }

    suspend fun markWelcomeSeen() {
        _hasSeenWelcome.value = true
        context.onboardingDataStore.edit { prefs ->
            prefs[HAS_SEEN_WELCOME] = true
        }
    }

    companion object {
        private val HAS_SEEN_WELCOME = booleanPreferencesKey("has_seen_welcome")

        @Volatile
        private var instance: OnboardingService? = null

        fun getInstance(context: Context): OnboardingService {
            return instance ?: synchronized(this) {
                instance ?: OnboardingService(context.applicationContext).also { instance = it }
            }
        }
    }
}
