package com.thisisnsh.cuecard.android.services

import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.ktx.Firebase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

class AuthenticationService(private val context: Context) {

    private val auth = FirebaseAuth.getInstance()
    private val analytics = Firebase.analytics
    private val credentialManager = CredentialManager.create(context)

    // Read the current user synchronously, so the login screen never flashes.
    private val _currentUser = MutableStateFlow<FirebaseUser?>(auth.currentUser)
    val currentUser: StateFlow<FirebaseUser?> = _currentUser.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(auth.currentUser != null)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    /** Tracks the current sign-in provider for account operations */
    var currentSignInProvider: String? = null
        private set

    init {
        auth.addAuthStateListener { firebaseAuth ->
            val user = firebaseAuth.currentUser
            _currentUser.value = user
            _isAuthenticated.value = user != null

            if (user != null) {
                analytics.setUserId(user.uid)
                analytics.logEvent(FirebaseAnalytics.Event.LOGIN) {
                    param(FirebaseAnalytics.Param.METHOD, PROVIDER_GOOGLE)
                }
            }
        }
    }

    suspend fun signInWithGoogle(webClientId: String) {
        _isLoading.value = true
        _error.value = null

        try {
            val googleIdOption = GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(false)
                .setServerClientId(webClientId)
                .build()

            val request = GetCredentialRequest.Builder()
                .addCredentialOption(googleIdOption)
                .build()

            val result = credentialManager.getCredential(context, request)
            handleSignIn(result)

            currentSignInProvider = PROVIDER_GOOGLE
            analytics.logEvent("sign_in_success") {
                param("method", PROVIDER_GOOGLE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Google Sign-In failed", e)
            _error.value = e.message ?: "Sign-in failed"
            analytics.logEvent("sign_in_error") {
                param("error", e.message ?: "unknown")
                param("method", PROVIDER_GOOGLE)
            }
        } finally {
            _isLoading.value = false
        }
    }

    private suspend fun handleSignIn(result: GetCredentialResponse) {
        when (val credential = result.credential) {
            is CustomCredential -> {
                if (credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                    try {
                        val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                        val firebaseCredential = GoogleAuthProvider.getCredential(
                            googleIdTokenCredential.idToken,
                            null
                        )
                        auth.signInWithCredential(firebaseCredential).await()
                    } catch (e: GoogleIdTokenParsingException) {
                        Log.e(TAG, "Invalid Google ID token", e)
                        _error.value = "Invalid credentials"
                    }
                } else {
                    Log.e(TAG, "Unexpected credential type")
                    _error.value = "Unexpected credential type"
                }
            }
            else -> {
                Log.e(TAG, "Unexpected credential type")
                _error.value = "Unexpected credential type"
            }
        }
    }

    fun signOut() {
        auth.signOut()
        currentSignInProvider = null
        ReviewPromptService.getInstance(context).reset()
        analytics.logEvent("sign_out", null)
    }

    suspend fun deleteAccount(): Result<Unit> {
        val user = auth.currentUser ?: return Result.failure(Exception(NO_USER_MESSAGE))

        return try {
            user.delete().await()

            // Clear all local data
            SettingsService.getInstance(context).clearAllData()

            currentSignInProvider = null
            analytics.logEvent("account_deleted", null)
            _currentUser.value = null
            _isAuthenticated.value = false
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete account", e)
            analytics.logEvent("account_delete_error") {
                param("error", e.message ?: "unknown")
            }

            // Re-authentication required: the same wording iOS shows.
            if (e is FirebaseAuthRecentLoginRequiredException) {
                Result.failure(Exception(REQUIRES_RECENT_LOGIN_MESSAGE))
            } else {
                Result.failure(e)
            }
        }
    }

    fun clearError() {
        _error.value = null
    }

    companion object {
        private const val TAG = "AuthenticationService"
        private const val PROVIDER_GOOGLE = "google"
        private const val NO_USER_MESSAGE = "No user is currently signed in."
        private const val REQUIRES_RECENT_LOGIN_MESSAGE =
            "Please sign out and sign in again before deleting your account."
    }
}
