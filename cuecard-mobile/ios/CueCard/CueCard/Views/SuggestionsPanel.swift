import SwiftUI

/// The button that asks the on-device model for suggestions on the script.
struct SuggestionsButton: View {
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.purple(for: colorScheme))
                .frame(width: 52, height: 52)
                .glassedEffect(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Suggestions")
        .accessibilityHint("Suggests fixes, cues, line breaks and emphasis for your script, on this iPhone")
    }
}

/// A slow ring of Apple Intelligence's colors around a round button, so
/// what it does stands out from the buttons beside it. Still where motion
/// is reduced.
private struct AIGlow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    private var colors: [Color] {
        [AppColors.purple(for: colorScheme), AppColors.pink(for: colorScheme), .orange,
         AppColors.blue(for: colorScheme), AppColors.purple(for: colorScheme)]
    }

    func body(content: Content) -> some View {
        let ring = AngularGradient(colors: colors, center: .center)
        content
            .background {
                Circle()
                    .stroke(ring, lineWidth: 5)
                    .blur(radius: 7)
                    .opacity(colorScheme == .dark ? 0.8 : 0.6)
                    .rotationEffect(.degrees(isTurning ? 360 : 0))
            }
            .overlay {
                Circle()
                    .strokeBorder(ring, lineWidth: 1.5)
                    .rotationEffect(.degrees(isTurning ? 360 : 0))
                    .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    isTurning = true
                }
            }
    }
}

extension View {
    /// Mark a round button as Apple Intelligence's.
    func aiGlow() -> some View {
        modifier(AIGlow())
    }
}

/// Where the home controls were while suggestions are open: one window with
/// its title and actions at the top, and the suggestion being looked at, as
/// it would change the script, to accept or reject. Each is decided on its
/// own, like suggested edits in a shared document.
struct SuggestionsPanel: View {
    @ObservedObject var review: ScriptReview
    let colorScheme: ColorScheme
    let cueColor: CueColor
    var onAccept: (ScriptSuggestion) -> Void
    var onAcceptAll: () -> Void

    private var secondary: Color { AppColors.textSecondary(for: colorScheme) }
    private var primary: Color { AppColors.textPrimary(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .glassedEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 10)
        .animation(.easeInOut(duration: 0.2), value: review.focusedID)
        .animation(.easeInOut(duration: 0.2), value: review.isRunning)
    }

    /// The window's title, and Accept All and Done, on one line, or the
    /// actions under the title where there's no room.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 8)
                reviewActions
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                HStack { Spacer(minLength: 0); reviewActions }
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppColors.purple(for: colorScheme))
            Text("AI Suggestions")
                .foregroundStyle(primary)
            BetaBadge()
            if review.isRunning { ProgressView().controlSize(.small) }
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var reviewActions: some View {
        HStack(spacing: 8) {
            if review.suggestions.count > 1 { smallButton("Accept All", action: onAcceptAll) }
            smallButton(review.isRunning ? "Stop" : "Done") {
                AnalyticsEvents.logButtonClick(review.isRunning ? "suggestions_stop" : "suggestions_done", screen: "home",
                                               parameters: ["left": review.suggestions.count])
                review.finish()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var content: some View {
        if let suggestion = review.focused {
            HStack(spacing: 8) {
                Image(systemName: suggestion.kind.systemImage)
                    .foregroundStyle(AppColors.purple(for: colorScheme))
                Text(suggestion.kind.title)
                    .foregroundStyle(primary)
                if let index = review.focusedIndex {
                    Text("\(index + 1) of \(review.suggestions.count)")
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                }
                Spacer(minLength: 8)
                if review.suggestions.count > 1 {
                    stepButton("chevron.left", label: "Previous Suggestion") {
                        AnalyticsEvents.logButtonClick("suggestion_previous", screen: "home")
                        review.focusPrevious()
                    }
                    stepButton("chevron.right", label: "Next Suggestion") {
                        AnalyticsEvents.logButtonClick("suggestion_next", screen: "home")
                        review.focusNext()
                    }
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
                        .frame(minHeight: 44)
                        .background(Capsule().fill(secondary.opacity(0.15)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onAccept(suggestion)
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(AppColors.green(for: colorScheme)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        } else if review.isRunning {
            Text("Reading your script on this iPhone…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primary)
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
        case .cue:
            // Put in after the words.
            let tag = Text(suggestion.replacement.trimmingCharacters(in: .whitespaces))
                .foregroundColor(cueColor.color(for: colorScheme))
                .fontWeight(.semibold)
                .fontWidth(.condensed)
            return Text(suggestion.context).foregroundColor(primary) + Text(" ") + tag
        case .anchor, .lineBreak:
            // Put in ahead of the words, which start a new line where the
            // suggestion breaks one.
            var added = Text("")
            if suggestion.replacement.hasPrefix("\n") {
                added = Text(Image(systemName: "return")).foregroundColor(green).fontWeight(.semibold) + Text(" ")
            }
            if suggestion.kind == .anchor {
                added = added + Text(TeleprompterParser.anchorTag)
                    .foregroundColor(secondary)
                    .fontWeight(.semibold)
                    .fontWidth(.condensed)
                    + Text(" ")
            }
            return added + Text(suggestion.original.trimmingCharacters(in: .whitespaces)).foregroundColor(primary)
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
                .frame(minHeight: 36)
                .background(Capsule().fill(secondary.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primary)
                .frame(width: 44, height: 44)
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
        case .lineBreak: "Add Line Break"
        case .bold: "Make Bold"
        case .italic: "Make Italic"
        }
    }

    var systemImage: String {
        switch self {
        case .spelling: "textformat.abc"
        case .cue: "text.bubble"
        case .anchor: "bookmark"
        case .lineBreak: "return"
        case .bold: "bold"
        case .italic: "italic"
        }
    }
}
