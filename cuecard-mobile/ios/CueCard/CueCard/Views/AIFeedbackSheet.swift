import SwiftUI
import FirebaseAnalytics

/// A Follow My Voice session that has just ended, waiting on the reader to
/// say how it went.
@MainActor
final class VoiceFeedback: ObservableObject {
    static let shared = VoiceFeedback()

    /// Long enough a session to be worth asking about.
    static let minimumSeconds: Double = 5

    @Published var pending: VoiceSessionMetrics?

    private init() {}

    /// The session as numbers, sent with every rating and report.
    nonisolated static func parameters(for metrics: VoiceSessionMetrics) -> [String: Any] {
        [
            "mode": "teleprompter",
            "listened_seconds": Int(metrics.listenedSeconds),
            "words_heard": metrics.wordsHeard,
            "moves": metrics.moves,
            "progress_percent": Int((metrics.progress * 100).rounded())
        ]
    }
}

/// A beta AI feature that has just been used, waiting on the reader to say
/// how it went. Each place it's used reports as its own metric.
enum AIExperience {
    /// Suggestions in the editor, on a script or a deck.
    case suggestions(SuggestionsMetrics)
    /// Follow My Voice in the teleprompter.
    case voice(VoiceSessionMetrics)

    /// What this experience's events start with.
    var metric: String {
        switch self {
        case .suggestions(let metrics): metrics.isDeck ? "suggestions_cards" : "suggestions_teleprompter"
        case .voice: "follow_voice"
        }
    }

    var question: LocalizedStringKey {
        switch self {
        case .suggestions: "How useful were these suggestions?"
        case .voice: "How well did Follow My Voice keep up?"
        }
    }

    /// The session as numbers, sent with every rating and report.
    var parameters: [String: Any] {
        switch self {
        case .suggestions(let metrics):
            [
                "mode": metrics.isDeck ? "cards" : "teleprompter",
                "found": metrics.found,
                "accepted": metrics.accepted,
                "rejected": metrics.rejected
            ]
        case .voice(let metrics):
            VoiceFeedback.parameters(for: metrics)
        }
    }

    func reportURL(stars: Int) -> URL {
        switch self {
        case .suggestions(let metrics): AppLinks.suggestionsReport(metrics: metrics, stars: stars)
        case .voice(let metrics): AppLinks.followVoiceReport(metrics: metrics, stars: stars)
        }
    }
}

/// Asked after each use of a beta AI feature: a rating from one to five
/// stars, and a way to report what went wrong. Only as tall as what's in it.
struct AIFeedbackSheet: View {
    let experience: AIExperience
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var stars = 0
    /// Something was sent, so closing the sheet doesn't count as skipping it.
    @State private var didRespond = false
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                BetaBadge()
                Spacer(minLength: 8)
                Button {
                    AnalyticsEvents.logButtonClick("\(experience.metric)_rating_not_now", screen: "ai_feedback")
                    dismiss()
                } label: {
                    Text("Not Now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(experience.question)
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        AnalyticsEvents.logButtonClick("\(experience.metric)_rating_star", screen: "ai_feedback", parameters: ["stars": star])
                        stars = star
                    } label: {
                        Image(systemName: star <= stars ? "star.fill" : "star")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(star <= stars
                                             ? AppColors.yellow(for: colorScheme)
                                             : AppColors.textSecondary(for: colorScheme))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) of 5 stars")
                    .accessibilityAddTraits(star == stars ? .isSelected : [])
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    reportButton
                    sendButton
                }
                VStack(spacing: 8) {
                    sendButton
                    reportButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .onDisappear {
            guard !didRespond else { return }
            Analytics.logEvent("\(experience.metric)_rating_skipped", parameters: experience.parameters)
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            Text("Send Rating")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(AppColors.green(for: colorScheme)))
        }
        .buttonStyle(.plain)
        .disabled(stars == 0)
        .opacity(stars == 0 ? 0.5 : 1)
    }

    private var reportButton: some View {
        Button(action: reportIssue) {
            Text("Report an Issue")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func send() {
        AnalyticsEvents.logButtonClick("\(experience.metric)_rating_send", screen: "ai_feedback", parameters: ["stars": stars])
        var parameters = experience.parameters
        parameters["stars"] = stars
        Analytics.logEvent("\(experience.metric)_rating", parameters: parameters)
        didRespond = true
        dismiss()
    }

    private func reportIssue() {
        AnalyticsEvents.logButtonClick("\(experience.metric)_rating_report", screen: "ai_feedback")
        var parameters = experience.parameters
        if stars > 0 { parameters["stars"] = stars }
        Analytics.logEvent("\(experience.metric)_report", parameters: parameters)
        didRespond = true
        openURL(experience.reportURL(stars: stars))
        dismiss()
    }
}

/// Marks a feature still being tried out.
struct BetaBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Beta")
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(AppColors.purple(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppColors.purple(for: colorScheme).opacity(0.15)))
    }
}
