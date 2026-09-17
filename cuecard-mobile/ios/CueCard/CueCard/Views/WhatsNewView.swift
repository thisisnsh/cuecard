import SwiftUI

/// This build's new features, on a card floating over whatever is on screen.
/// Shown once per build on launch, and again from Settings.
struct WhatsNewView: View {
    let release: WhatsNewService.Release
    let version: String
    let onClose: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var isShowing = false
    @State private var isFloating = false

    var body: some View {
        ZStack {
            Color.black
                .opacity(isShowing ? 0.45 : 0)
                .ignoresSafeArea()

            if isShowing {
                card
                    .padding(.horizontal, 20)
                    .padding(.vertical, 40)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowing = true
            }
        }
    }

    private var card: some View {
        // Sized to its features, and scrolling only once they outgrow the screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) {
                content
            }
        }
        .frame(maxWidth: 380)
        .background { StarfieldGradient() }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close")
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 30, y: 12)
    }

    private var primary: Color { AppColors.textPrimary(for: colorScheme) }
    private var secondary: Color { AppColors.textSecondary(for: colorScheme) }

    private var content: some View {
        VStack(spacing: 24) {
            Text(release.title ?? "What's New")
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)

            Image("Icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .rotationEffect(.degrees(-8))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 18, y: 10)
                .offset(y: isFloating ? -5 : 5)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isFloating)
                .onAppear { isFloating = true }

            VStack(spacing: 4) {
                Text("CueCard")
                    .font(.headline)
                    .foregroundStyle(primary)
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(release.features.enumerated()), id: \.offset) { _, feature in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondary)
                        Text(feature)
                            .font(.subheadline)
                            .foregroundStyle(primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(primary.opacity(0.05))
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 28)
    }

    /// Let the card leave before the cover underneath it goes.
    private func close() {
        withAnimation(.easeIn(duration: 0.2)) {
            isShowing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onClose()
        }
    }
}

/// The app's background as a slowly turning gradient, with stars twinkling and
/// drifting up through it. Light in light mode, dark in dark mode.
private struct StarfieldGradient: View {
    @Environment(\.colorScheme) var colorScheme

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let speed: Double
        let phase: Double
    }

    /// The same sky every time: positions come from a fixed seed.
    private static let stars: [Star] = {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<48).map { _ in
            Star(
                x: next(),
                y: next(),
                radius: 0.6 + next() * 1.4,
                speed: 0.6 + next() * 1.0,
                phase: next() * .pi * 2
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = t / 6
            let isDark = colorScheme == .dark
            let background = AppColors.background(for: colorScheme)
            let lifted = isDark ? Color(hex: "#24211e") : Color(hex: "#e5ddcf")
            // White glints on dark; on the light background white would vanish,
            // so they take the secondary text color, kept faint.
            let starColor = isDark ? Color.white : AppColors.Light.textSecondary
            let starStrength = isDark ? 1.0 : 0.45

            ZStack {
                LinearGradient(
                    colors: [background, lifted, background],
                    startPoint: UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle)),
                    endPoint: UnitPoint(x: 0.5 - 0.5 * cos(angle), y: 0.5 - 0.5 * sin(angle))
                )

                // A soft glow behind the icon.
                RadialGradient(
                    colors: [.white.opacity(isDark ? 0.08 : 0.7), .clear],
                    center: UnitPoint(x: 0.5, y: 0.36),
                    startRadius: 0,
                    endRadius: 220
                )

                Canvas { context, size in
                    for star in Self.stars {
                        var y = (star.y - t * 0.006 * star.speed).truncatingRemainder(dividingBy: 1)
                        if y < 0 { y += 1 }
                        // Fade out near the edges, so wrapping around never pops.
                        let edge = min(y * 8, (1 - y) * 8, 1)
                        let twinkle = pow((sin(t * star.speed * 1.6 + star.phase) + 1) / 2, 2)
                        let opacity = twinkle * edge * starStrength

                        let center = CGPoint(x: star.x * size.width, y: y * size.height)
                        let glow = star.radius * 4
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                            with: .color(starColor.opacity(opacity * 0.18))
                        )
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - star.radius, y: center.y - star.radius, width: star.radius * 2, height: star.radius * 2)),
                            with: .color(starColor.opacity(opacity))
                        )
                    }
                }
            }
        }
    }
}

/// Covers and sheets slide up by default. The What's New card animates itself,
/// so its cover goes on and off without that slide.
func withoutPresentationAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

extension View {
    /// Present the What's New card over everything, from wherever this is.
    func whatsNewCover(isPresented: Binding<Bool>, release: WhatsNewService.Release?, version: String) -> some View {
        fullScreenCover(isPresented: isPresented) {
            if let release {
                WhatsNewView(release: release, version: version) {
                    withoutPresentationAnimation { isPresented.wrappedValue = false }
                }
                .presentationBackground(.clear)
            }
        }
    }
}

#Preview {
    WhatsNewView(
        release: WhatsNewService.Release(
            title: "Improved with New Features",
            features: ["A rebuilt floating window.", "Select All in the cue bar."]
        ),
        version: "1.5.0",
        onClose: {}
    )
}
