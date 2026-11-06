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

// MARK: - Scroll Edge Fades

extension View {
    /// Apply to the scrolling view, before its fixed header or footer. SwiftUI
    /// sizes the mask to the visible area between the bars and keyboard.
    /// Without `fadesEnd`, only the start fades, and the content runs on
    /// under whatever floats over the end.
    @ViewBuilder
    func scrollEdgeFade(axis: Axis = .vertical, length: CGFloat = 24,
                        insetContent: Bool = true, fadesEnd: Bool = true, enabled: Bool = true) -> some View {
        if enabled {
            modifier(ScrollEdgeFade(axis: axis, length: length, insetContent: insetContent, fadesEnd: fadesEnd))
        } else {
            self
        }
    }
}

private struct ScrollEdgeFade: ViewModifier {
    let axis: Axis
    let length: CGFloat
    let insetContent: Bool
    let fadesEnd: Bool

    private var edges: Edge.Set { axis == .vertical ? .vertical : .horizontal }
    private var fadedEdges: Edge.Set {
        fadesEnd ? edges : (axis == .vertical ? .top : .leading)
    }

    func body(content: Content) -> some View {
        padded(content)
            .systemScrollEdgesHidden(edges)
            .mask {
                GeometryReader { geometry in
                    let size = axis == .vertical ? geometry.size.height : geometry.size.width
                    // The mask is already inside the safe area. Padding by the
                    // inherited safe-area insets here would subtract it twice.
                    let fraction = min(max(length, 0) / max(size, 1), 0.5)
                    let end = fadesEnd ? fraction : 0

                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.1), location: fraction * 0.45),
                        .init(color: .black, location: fraction),
                        .init(color: .black, location: 1 - end),
                        .init(color: .black.opacity(fadesEnd ? 0.1 : 1), location: 1 - end * 0.45),
                        .init(color: fadesEnd ? .clear : .black, location: 1)
                    ], startPoint: axis == .vertical ? .top : .leading,
                       endPoint: axis == .vertical ? .bottom : .trailing)
                }
                // Without a fade at the end, the content stays in view under
                // the bar there too, rather than being cut off at its edge.
                .ignoresSafeArea(.container, edges: fadesEnd ? [] : (axis == .vertical ? .bottom : .trailing))
            }
    }

    @ViewBuilder
    private func padded(_ content: Content) -> some View {
        if insetContent {
            // First and last items can scroll completely clear of the fades.
            content.contentMargins(fadedEdges, length, for: .scrollContent)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func systemScrollEdgesHidden(_ edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }
}

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

extension View {
    /// `scriptEdgeFade` as a mask: the script itself fades out at its edges,
    /// so whatever is drawn behind it, such as the camera, stays clear.
    func scriptEdgeMask(top: CGFloat, bottom: CGFloat) -> some View {
        mask {
            Rectangle()
                .overlay(alignment: .top) {
                    EdgeFade(color: .black, height: top, isTop: true).blendMode(.destinationOut)
                }
                .overlay(alignment: .bottom) {
                    EdgeFade(color: .black, height: bottom, isTop: false).blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

extension View {
    /// Leaves the top of a scroll view to `scriptEdgeFade`, without the bar's
    /// own edge effect drawn over it on iOS 26.
    @ViewBuilder
    func topScrollEdgeEffectHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
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

extension ToolbarContent {
    /// On iOS 26, leave the item out of the bar's glass, as for a title.
    @ToolbarContentBuilder
    func sharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
