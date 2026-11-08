import SwiftUI

/// The button that asks the on-device model for suggestions on the script,
/// filled while they're showing. Tapped again, it puts them away.
struct SuggestionsButton: View {
    let colorScheme: ColorScheme
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? (colorScheme == .dark ? Color.black : Color.white)
                                      : AppColors.purple(for: colorScheme))
                .frame(width: 52, height: 52)
                .background { if isOn { Circle().fill(AppColors.purple(for: colorScheme)) } }
                .glassedEffect(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Turn Off Suggestions AI" : "Suggestions AI")
        .accessibilityHint(isOn ? "" : "Suggests fixes, cues, line breaks and emphasis for your script, on this iPhone")
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

/// What Suggestions AI is doing, floating centered over the home controls
/// like Follow Me AI's over the teleprompter's: reading the script, then
/// what to do with what it found. The suggestions themselves are in the script, each
/// accepted or rejected with a tap on it.
struct SuggestionsStatus: View {
    @ObservedObject var review: ScriptReview
    let colorScheme: ColorScheme

    var body: some View {
        // One line, however long it runs in a language: it shrinks a
        // little, then trails off, rather than wrapping.
        HStack(spacing: 8) {
            Image(systemName: icon)
                .symbolEffect(.variableColor.iterative, isActive: review.isRunning)
            label
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassedEffect(in: Capsule())
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.2), value: review.isRunning)
        .animation(.easeInOut(duration: 0.2), value: review.suggestions.count)
    }

    private var icon: String {
        if review.isRunning { return "sparkles" }
        return review.suggestions.isEmpty ? "checkmark.circle" : "hand.tap"
    }

    @ViewBuilder
    private var label: some View {
        if review.isRunning {
            Text("Reading your script")
        } else if !review.suggestions.isEmpty {
            Text("Tap to accept/reject suggestions")
        } else {
            Text("No suggestions")
        }
    }
}
