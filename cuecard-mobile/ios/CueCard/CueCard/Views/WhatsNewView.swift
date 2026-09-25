import SwiftUI

/// This build's new features, on a glass card floating over whatever is on
/// screen, which shows through blurred. Shown once per build on launch, and
/// again from Settings.
struct WhatsNewView: View {
    let release: WhatsNewService.Release
    let version: String
    let onClose: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var isShowing = false
    @State private var isFloating = false
    @State private var isCardFloating = false

    private static let cornerRadius: CGFloat = 32

    var body: some View {
        ZStack {
            // What's underneath stays in view, softened, so the card reads as
            // hovering over it rather than replacing it.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12))
                .opacity(isShowing ? 1 : 0)
                .ignoresSafeArea()

            if isShowing {
                card
                    // A slow drift, out of step with the icon's, so the two
                    // never move as one.
                    .offset(y: isCardFloating ? -4 : 4)
                    .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: isCardFloating)
                    .onAppear { isCardFloating = true }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 48)
                    .transition(.scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: 24)))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
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
        // The stars show faintly through the glass rather than filling it.
        .background { StarfieldGradient().opacity(colorScheme == .dark ? 0.55 : 0.45) }
        .clipShape(shape)
        .glassedEffect(in: shape)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primary)
                    .frame(width: 32, height: 32)
                    .glassedEffect(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close")
        }
        // Light catching the top edge of the glass.
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.35 : 0.8), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
        // A wide, soft shadow well below the card, so it sits high off the page.
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 40, y: 24)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 4)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
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
                    .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.6), lineWidth: 0.7)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 28)
    }

    /// Let the card leave before the window it's in goes.
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

/// Floats the What's New card in a window of its own, above the app's.
///
/// Presented from a view instead, it can only go up when nothing else is:
/// a cover from the root fails while cards or Settings are open, and one from
/// a screen goes when that screen does. A window sits over whatever is on
/// screen now, and whatever opens after.
@MainActor
enum WhatsNewPresenter {
    private static var window: UIWindow?

    static func show(release: WhatsNewService.Release, version: String) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }

        let card = WhatsNewView(release: release, version: version, onClose: hide)
            // A window of its own doesn't inherit the theme set on the app's.
            .preferredColorScheme(SettingsService.shared.settings.themePreference.colorScheme)
        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    private static func hide() {
        window?.isHidden = true
        window = nil
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
