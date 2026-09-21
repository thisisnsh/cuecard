import SwiftUI
import FirebaseAnalytics

/// Cards mode: the script as a deck, one card at a time. Swipe the top card
/// left to put it away and right to bring the last one back, the way
/// notifications are cleared. With the Lock Screen chosen, the same deck runs
/// as a Live Activity too, and both move together.
struct CueCardsView: View {
    let cards: [String]

    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var session = CueCardsSession.shared
    @State private var dragOffset: CGFloat = 0

    private var settings: TeleprompterSettings { settingsService.settings }

    /// How far a card has to be dragged to count as a swipe.
    private static let swipeDistance: CGFloat = 90
    private static let deckAnimation = Animation.spring(response: 0.4, dampingFraction: 0.84)
    /// How far below the top card each card behind it peeks out.
    private static let peek: CGFloat = 14

    private var progress: String {
        session.isFinished ? "Done" : "\(session.index + 1) of \(session.cards.count)"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    AppColors.background(for: colorScheme)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        deck(width: geometry.size.width)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, Self.peek * 2)
                            .frame(maxHeight: .infinity)

                        hint
                            .padding(.horizontal, 32)
                            .padding(.top, 12)

                        controls
                            .padding(.top, 20)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        AnalyticsEvents.logButtonClick("close", screen: "cards")
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text(progress)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                }
            }
        }
        .onAppear {
            session.start(cards: cards, cueColor: settings.cueColor,
                          showOnLockScreen: settings.cardDisplay == .lockScreen)
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "cards"
            ])
            Analytics.logEvent("cards_open", parameters: [
                "count": cards.count,
                "display": settings.cardDisplay.rawValue
            ])
        }
        .onDisappear {
            session.end()
        }
    }

    // MARK: - Deck

    /// The card before the top one waits just off the left edge, ready to be
    /// swiped back in. The next two sit behind the top card, peeking out below.
    /// Every card keeps its identity as it moves between those places, so a
    /// swipe, a button and the Lock Screen all animate the deck the same way.
    private func deck(width: CGFloat) -> some View {
        let lower = max(session.index - 1, 0)
        let upper = min(session.index + 3, session.cards.count)

        return ZStack {
            if session.isFinished {
                finishedCard
                    .transition(.opacity)
            }

            ForEach(lower..<upper, id: \.self) { cardIndex in
                let placement = placement(of: cardIndex - session.index, width: width)
                CueCardFace(
                    runs: CueCards.runs(for: session.cards[cardIndex]),
                    cueColor: settings.cueColor,
                    fontSize: CGFloat(settings.fontSize),
                    colorScheme: colorScheme
                )
                .scaleEffect(placement.scale, anchor: .bottom)
                .offset(x: placement.x, y: placement.y)
                .rotationEffect(.degrees(placement.rotation), anchor: .bottom)
                .opacity(placement.opacity)
                .zIndex(placement.zIndex)
                .accessibilityHidden(cardIndex != session.index)
            }
        }
        .contentShape(Rectangle())
        .gesture(swipe(width: width))
        .animation(Self.deckAnimation, value: session.index)
    }

    private struct Placement {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scale: CGFloat = 1
        var rotation: Double = 0
        var opacity: Double = 1
        var zIndex: Double = 0
    }

    /// Where a card sits, from how far it is from the top of the deck.
    private func placement(of offset: Int, width: CGFloat) -> Placement {
        let offscreen = -(width + 60)

        if offset < 0 {
            // Follows the finger in from the left edge, twice as fast so it is
            // well in view by the time the swipe counts.
            let x = min(0, offscreen + max(dragOffset, 0) * 2)
            return Placement(x: x, rotation: Double(x) / 40, zIndex: 2)
        }

        if offset == 0 {
            let x: CGFloat
            if dragOffset < 0 {
                x = dragOffset
            } else if session.index == 0 {
                // Nothing to bring back: the card gives a little and settles.
                x = dragOffset * 0.15
            } else {
                x = 0
            }
            return Placement(x: x, rotation: Double(x) / 25, zIndex: 1)
        }

        // Cards behind move up into place as the top one is swiped away.
        let leaving = dragOffset < 0 ? min(-dragOffset / width, 1) : 0
        let depth = CGFloat(offset) - leaving
        return Placement(
            y: Self.peek * depth,
            scale: 1 - 0.05 * depth,
            opacity: offset > 2 ? 0 : 1,
            zIndex: -Double(offset)
        )
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let distance = value.translation.width
                let predicted = value.predictedEndTranslation.width
                withAnimation(Self.deckAnimation) {
                    if (distance < -Self.swipeDistance || predicted < -width / 2), !session.isFinished {
                        session.next()
                        Analytics.logEvent("cards_next", parameters: ["source": "swipe"])
                    } else if (distance > Self.swipeDistance || predicted > width / 2), session.index > 0 {
                        session.previous()
                        Analytics.logEvent("cards_previous", parameters: ["source": "swipe"])
                    }
                    dragOffset = 0
                }
            }
    }

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.green(for: colorScheme))
            Text("All cards done")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            Text("Swipe right to bring the last card back, or start over.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CueCardFace.cornerRadius, style: .continuous)
                .stroke(AppColors.textSecondary(for: colorScheme).opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        )
    }

    // MARK: - Hint

    /// How to move through the deck, and whether it is on the Lock Screen too.
    @ViewBuilder
    private var hint: some View {
        let secondary = AppColors.textSecondary(for: colorScheme)

        if settings.cardDisplay == .lockScreen {
            if session.isOnLockScreen {
                Label("On your Lock Screen too. Use its arrows to move through the cards there.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .multilineTextAlignment(.center)
            } else if session.lockScreenUnavailable {
                Label("Turn on Live Activities for CueCard in Settings to see your cards on the Lock Screen.",
                      systemImage: "lock.slash")
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button(action: {
                    AnalyticsEvents.logButtonClick("show_on_lock_screen", screen: "cards")
                    session.showOnLockScreen()
                }) {
                    Label("Show on Lock Screen", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .glassedEffect(in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("Swipe left for the next card, right to bring one back.")
                .font(.footnote)
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 24) {
            Button(action: {
                AnalyticsEvents.logButtonClick("previous_card", screen: "cards")
                withAnimation(Self.deckAnimation) { session.previous() }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .frame(width: 52, height: 52)
                    .glassedEffect(in: Circle())
            }
            .disabled(session.index == 0)
            .opacity(session.index == 0 ? 0.4 : 1)
            .accessibilityLabel("Previous Card")

            Button(action: {
                if session.isFinished {
                    AnalyticsEvents.logButtonClick("restart_cards", screen: "cards")
                    withAnimation(Self.deckAnimation) { session.restart() }
                } else {
                    AnalyticsEvents.logButtonClick("next_card", screen: "cards")
                    withAnimation(Self.deckAnimation) { session.next() }
                }
            }) {
                Image(systemName: session.isFinished ? "arrow.counterclockwise" : "chevron.right")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(AppColors.green(for: colorScheme)))
                    .glassedEffect(in: Circle())
            }
            .accessibilityLabel(session.isFinished ? "Start Over" : "Next Card")

            // Balances the back button, so the main one sits in the middle.
            Color.clear
                .frame(width: 52, height: 52)
        }
    }
}

/// One card of the deck, cues drawn in their color.
private struct CueCardFace: View {
    let runs: [CueCardRun]
    let cueColor: CueColor
    let fontSize: CGFloat
    let colorScheme: ColorScheme

    static let cornerRadius: CGFloat = 28

    var body: some View {
        runs.text(primary: AppColors.textPrimary(for: colorScheme), cue: cueColor.color(for: colorScheme))
            .font(.system(size: fontSize, weight: .semibold))
            // A card past its limit shrinks to fit rather than being cut off.
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.11) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(AppColors.textSecondary(for: colorScheme).opacity(0.2), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 16, y: 6)
    }
}
