import SwiftUI

// MARK: - Glass Effect Modifier for iOS 26+

extension View {
    /// Applies a glass effect to the view.
    /// - Parameters:
    ///   - shape: The shape to apply the glass effect in
    ///   - interactive: Whether the glass should respond to user interactions (iOS 26+ only)
    /// - Returns: A view with the glass effect applied
    @ViewBuilder
    func glassedEffect<S: Shape>(in shape: S = Capsule(), interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background {
                shape.glassed()
            }
        }
    }
}

// MARK: - Fallback Glass Effect for older iOS versions

extension Shape {
    /// Creates a glass-like appearance for older iOS versions using materials and gradients
    func glassed() -> some View {
        self
            .fill(.ultraThinMaterial)
            .overlay {
                self.fill(
                    .linearGradient(
                        colors: [
                            .primary.opacity(0.08),
                            .primary.opacity(0.05),
                            .primary.opacity(0.01),
                            .clear,
                            .clear,
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                self.stroke(.primary.opacity(0.2), lineWidth: 0.7)
            }
    }
}

// MARK: - Script Edge Fade

extension View {
    /// Fades a scrolling script into the background at its top and bottom edges,
    /// so lines arrive and leave instead of being cut off mid-stroke.
    ///
    /// The fades are painted in the background color rather than masked, so they
    /// cover the text without touching whatever floats above them.
    func scriptEdgeFade(for colorScheme: ColorScheme, top: CGFloat, bottom: CGFloat) -> some View {
        let color = AppColors.background(for: colorScheme)

        return overlay(alignment: .top) {
            EdgeFade(color: color, height: top, isTop: true)
        }
        .overlay(alignment: .bottom) {
            EdgeFade(color: color, height: bottom, isTop: false)
        }
    }
}

/// One end of the fade: solid against its edge, gone by the far side.
private struct EdgeFade: View {
    let color: Color
    let height: CGFloat
    let isTop: Bool

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(0.9), location: 0.45),
                .init(color: color.opacity(0), location: 1)
            ],
            startPoint: isTop ? .top : .bottom,
            endPoint: isTop ? .bottom : .top
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}
