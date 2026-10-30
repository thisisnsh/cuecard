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
    static func parameters(for metrics: VoiceSessionMetrics) -> [String: Any] {
        [
            "mode": metrics.mode,
            "listened_seconds": Int(metrics.listenedSeconds),
            "words_heard": metrics.wordsHeard,
            "moves": metrics.moves,
            "progress_percent": Int((metrics.progress * 100).rounded())
        ]
    }
}

/// Asked after each Follow My Voice session while it's in beta: a rating
/// from one to five stars, and a way to report what went wrong.
struct VoiceFeedbackSheet: View {
    let metrics: VoiceSessionMetrics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var stars = 0
    /// Something was sent, so closing the sheet doesn't count as skipping it.
    @State private var didRespond = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    BetaBadge()
                    Text("How well did Follow My Voice keep up?")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Your rating helps make it better.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            stars = star
                        } label: {
                            Image(systemName: star <= stars ? "star.fill" : "star")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(star <= stars
                                                 ? AppColors.yellow(for: colorScheme)
                                                 : AppColors.textSecondary(for: colorScheme))
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) of 5 stars")
                        .accessibilityAddTraits(star == stars ? .isSelected : [])
                    }
                }

                VStack(spacing: 12) {
                    Button(action: send) {
                        Text("Send Rating")
                            .font(.headline)
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(AppColors.green(for: colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .disabled(stars == 0)
                    .opacity(stars == 0 ? 0.5 : 1)

                    Button(action: reportIssue) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear {
            guard !didRespond else { return }
            Analytics.logEvent("follow_voice_rating_skipped", parameters: VoiceFeedback.parameters(for: metrics))
        }
    }

    private func send() {
        var parameters = VoiceFeedback.parameters(for: metrics)
        parameters["stars"] = stars
        Analytics.logEvent("follow_voice_rating", parameters: parameters)
        didRespond = true
        dismiss()
    }

    private func reportIssue() {
        var parameters = VoiceFeedback.parameters(for: metrics)
        if stars > 0 { parameters["stars"] = stars }
        Analytics.logEvent("follow_voice_report", parameters: parameters)
        didRespond = true
        openURL(AppLinks.followVoiceReport(metrics: metrics, stars: stars))
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
