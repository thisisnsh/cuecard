import Foundation
import FirebaseAnalytics

/// Decides when to ask for an App Store review.
///
/// StoreKit's `requestReview` is a request, not a command: iOS shows the prompt at
/// most three times a year per user and silently ignores the rest, so there's no
/// harm in asking more often than that. All this tracks is a local session count —
/// we ask on the 1st session and every 10th one after (1, 11, 21, …) and let the
/// system decide what actually reaches the user.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Direct link to the App Store review composer, for the "Rate CueCard" row in
    /// Settings. Unlike `requestReview` this always works, so it stays user-initiated.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6757321325?action=write-review")!

    private static let promptInterval = 10

    private let userDefaults = UserDefaults.standard
    private let sessionCountKey = "cuecard_review_session_count"

    private init() {}

    private(set) var sessionCount: Int {
        get { userDefaults.integer(forKey: sessionCountKey) }
        set { userDefaults.set(newValue, forKey: sessionCountKey) }
    }

    /// Record a finished teleprompter session.
    func recordCompletedSession() {
        sessionCount += 1
    }

    /// Whether the next natural moment should carry a review request.
    var shouldRequestReview: Bool {
        sessionCount % Self.promptInterval == 1
    }

    /// Call right after handing the request to StoreKit. There's no callback telling
    /// us whether the prompt actually appeared, so this only records that we asked.
    func logReviewRequested() {
        Analytics.logEvent("review_prompt_requested", parameters: [
            "session_count": sessionCount
        ])
    }

    /// Start the count over. Called on sign-out, so the next person to use this
    /// device gets the same run-up rather than inheriting someone else's total.
    func reset() {
        userDefaults.removeObject(forKey: sessionCountKey)
    }
}
