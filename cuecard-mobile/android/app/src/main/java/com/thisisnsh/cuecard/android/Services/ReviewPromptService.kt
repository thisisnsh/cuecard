package com.thisisnsh.cuecard.android.services

import android.content.Context
import androidx.core.content.edit
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase

/**
 * Decides when to ask for a Play Store review.
 *
 * The Play In-App Review API is a request, not a command: Play shows the prompt
 * on its own quota and silently ignores the rest, so there's no harm in asking
 * more often than that. All this tracks is a local session count — we ask on the
 * 1st session and every 10th one after (1, 11, 21, …) and let the system decide
 * what actually reaches the user.
 */
class ReviewPromptService private constructor(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val analytics = Firebase.analytics

    var sessionCount: Int
        get() = prefs.getInt(SESSION_COUNT_KEY, 0)
        private set(value) = prefs.edit { putInt(SESSION_COUNT_KEY, value) }

    /** Record a finished teleprompter session. */
    fun recordCompletedSession() {
        sessionCount += 1
    }

    /** Whether the next natural moment should carry a review request. */
    val shouldRequestReview: Boolean
        get() = sessionCount % PROMPT_INTERVAL == 1

    /**
     * Call right after handing the request to Play. There's no callback telling us
     * whether the prompt actually appeared, so this only records that we asked.
     */
    fun logReviewRequested() {
        analytics.logEvent("review_prompt_requested") {
            param("session_count", sessionCount.toLong())
        }
    }

    /**
     * Start the count over. Called on sign-out, so the next person to use this
     * device gets the same run-up rather than inheriting someone else's total.
     */
    fun reset() {
        prefs.edit { remove(SESSION_COUNT_KEY) }
    }

    companion object {
        private const val PREFS_NAME = "cuecard_review_prompt"
        private const val SESSION_COUNT_KEY = "cuecard_review_session_count"
        private const val PROMPT_INTERVAL = 10

        @Volatile
        private var instance: ReviewPromptService? = null

        fun getInstance(context: Context): ReviewPromptService {
            return instance ?: synchronized(this) {
                instance ?: ReviewPromptService(context.applicationContext).also { instance = it }
            }
        }
    }
}
