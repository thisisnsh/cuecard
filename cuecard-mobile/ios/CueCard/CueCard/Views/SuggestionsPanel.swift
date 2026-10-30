import SwiftUI

/// The button that asks the on-device model for suggestions on the script.
struct SuggestionsButton: View {
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.purple(for: colorScheme))
                .frame(width: 52, height: 52)
                .glassedEffect(in: Circle())
                .shadow(color: Color.black.opacity(0.1), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggestions")
        .accessibilityHint("Suggests fixes, cues and emphasis for your script, on this iPhone")
    }
}

/// Where the home controls were while suggestions are open: the one being
/// looked at, as it would change the script, to accept or reject. Each is
/// decided on its own, like suggested edits in a shared document.
struct SuggestionsPanel: View {
    @ObservedObject var review: ScriptReview
    let colorScheme: ColorScheme
    let cueColor: CueColor
    var onAccept: (ScriptSuggestion) -> Void
    var onAcceptAll: () -> Void

    private var secondary: Color { AppColors.textSecondary(for: colorScheme) }
    private var primary: Color { AppColors.textPrimary(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            card
        }
        .animation(.easeInOut(duration: 0.2), value: review.focusedID)
        .animation(.easeInOut(duration: 0.2), value: review.isRunning)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if review.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Group {
                if let index = review.focusedIndex {
                    Text("\(index + 1) of \(review.suggestions.count)")
                        .monospacedDigit()
                } else if review.isRunning {
                    Text("Reviewing…")
                } else {
                    Text("Suggestions")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(secondary)

            BetaBadge()

            Spacer(minLength: 8)

            if review.suggestions.count > 1 {
                smallButton("Accept All", action: onAcceptAll)
            }
            smallButton(review.isRunning ? "Stop" : "Done") {
                AnalyticsEvents.logButtonClick("suggestions_done", screen: "home",
                                               parameters: ["left": review.suggestions.count])
                review.end()
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let suggestion = review.focused {
                HStack(spacing: 8) {
                    Image(systemName: suggestion.kind.systemImage)
                        .foregroundStyle(AppColors.purple(for: colorScheme))
                    Text(suggestion.kind.title)
                        .foregroundStyle(primary)
                    Spacer(minLength: 8)
                    if review.suggestions.count > 1 {
                        stepButton("chevron.left", label: "Previous Suggestion", action: review.focusPrevious)
                        stepButton("chevron.right", label: "Next Suggestion", action: review.focusNext)
                    }
                }
                .font(.subheadline.weight(.semibold))

                preview(of: suggestion)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        review.reject(suggestion.id)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .glassedEffect(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAccept(suggestion)
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(AppColors.green(for: colorScheme)))
                    }
                    .buttonStyle(.plain)
                }
            } else if review.isRunning {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppColors.purple(for: colorScheme))
                    Text("Reading your script on this iPhone…")
                        .foregroundStyle(primary)
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(AppColors.green(for: colorScheme))
                    Text("No suggestions. Your script looks good.")
                        .foregroundStyle(primary)
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .padding(16)
        .glassedEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 10)
    }

    /// The change as it would read in the script: what goes struck through,
    /// what comes in highlighted.
    private func preview(of suggestion: ScriptSuggestion) -> Text {
        let green = AppColors.green(for: colorScheme)
        switch suggestion.kind {
        case .spelling:
            return Text(suggestion.original)
                .strikethrough()
                .foregroundColor(AppColors.red(for: colorScheme))
                + Text("  ")
                + Text(suggestion.replacement)
                .foregroundColor(green)
                .fontWeight(.semibold)
        case .cue, .anchor:
            // Only ever something put in beside the words.
            let isBefore = suggestion.kind == .anchor
            let added = isBefore
                ? String(suggestion.replacement.dropLast(suggestion.original.count))
                : String(suggestion.replacement.dropFirst(suggestion.original.count))
            let tag = Text(added.trimmingCharacters(in: .whitespaces))
                .foregroundColor(isBefore ? secondary : cueColor.color(for: colorScheme))
                .fontWeight(.semibold)
                .fontWidth(.condensed)
            let words = Text(suggestion.original).foregroundColor(primary)
            return isBefore ? tag + Text(" ") + words : words + Text(" ") + tag
        case .bold:
            return Text(suggestion.original).fontWeight(.heavy).foregroundColor(green)
        case .italic:
            return Text(suggestion.original).italic().foregroundColor(green)
        }
    }

    private func smallButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .glassedEffect(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension ScriptSuggestion.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .spelling: "Fix Spelling"
        case .cue: "Add Cue"
        case .anchor: "Add Anchor"
        case .bold: "Make Bold"
        case .italic: "Make Italic"
        }
    }

    var systemImage: String {
        switch self {
        case .spelling: "textformat.abc"
        case .cue: "text.bubble"
        case .anchor: "bookmark"
        case .bold: "bold"
        case .italic: "italic"
        }
    }
}
