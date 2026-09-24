import SwiftUI
import FirebaseAnalytics

/// Cards mode: one card at a time, synced with widgets and the Live Activity.
struct CueCardsView: View {
    /// The deck to open. Nil when it is already open: opened from the watch.
    let cards: [String]?
    /// What the watch calls the deck.
    let title: String
    /// The saved note the deck came from, so the watch can match it to its
    /// own copy.
    let deckID: UUID?

    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var session = CueCardsSession.shared
    @State private var hasOpenedDeck = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingLockScreenHelp = false
    @State private var showingSettings = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: TeleprompterSettings { settingsService.settings }

    /// How far a card has to be dragged to count as a swipe.
    private static let swipeDistance: CGFloat = 90
    private static let deckAnimation = Animation.spring(response: 0.4, dampingFraction: 0.84)
    /// How far below the top card each card behind it peeks out.
    private static let peek: CGFloat = 14

    private var progress: String {
        session.isFinished ? "Done" : "\(session.index + 1) of \(session.cards.count)"
    }

    private var nextLabel: String {
        if session.isFinished { return "Start Over" }
        return session.index == session.cards.count - 1 ? "Finish" : "Next Card"
    }

    private var animation: Animation? { reduceMotion ? nil : Self.deckAnimation }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    AppColors.background(for: colorScheme)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        PageDots(count: session.cards.count, index: session.index, colorScheme: colorScheme)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .accessibilityHidden(true)

                        deck(width: geometry.size.width)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, Self.peek * 2)
                            .frame(maxHeight: .infinity)

                        hint
                            .padding(.horizontal, 32)
                            .padding(.top, 12)

                        controls
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
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
                        session.end()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(session.title.isEmpty ? title : session.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(progress)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        AnalyticsEvents.logButtonClick("settings", screen: "cards")
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                CardsSettingsView()
                    .environmentObject(settingsService)
            }
            .sheet(isPresented: $showingLockScreenHelp) {
                NavigationStack {
                    List {
                        Section {
                            Label("Use Back and Next on the Live Activity to turn cards.", systemImage: "hand.tap")
                            Label("Authenticate with Face ID, Touch ID or your passcode to use the buttons.", systemImage: "lock.open")
                            Label("Add the Cards widget from your Home Screen widget gallery. Medium and large widgets include card controls.", systemImage: "square.grid.2x2")
                            Text("The small Lock Screen widget shows a preview. Interactive buttons require iOS 17 or later.")
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("Read from your Lock Screen")
                        } footer: {
                            Text("Your place stays in sync with the app and Apple Watch. Closing this deck ends its Live Activity and clears the widgets.")
                        }
                        if session.lockScreenUnavailable && !session.isOnLockScreen {
                            Text("Check that Live Activities are enabled for CueCard in Settings, then return to this deck and try again.")
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            Button("Try Again") {
                                session.showOnLockScreen()
                                showingLockScreenHelp = false
                            }
                        }
                    }
                    .navigationTitle("Lock Screen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingLockScreenHelp = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "cards",
                AnalyticsParameterScreenClass: "CueCardsView"
            ])
            guard !hasOpenedDeck else { return }
            hasOpenedDeck = true
            guard let cards else { return }
            session.start(cards: cards, title: title, deckID: deckID,
                          showOnLockScreen: settings.cardDisplay == .lockScreen)
            Analytics.logEvent("cards_open", parameters: [
                "count": cards.count,
                "display": settings.cardDisplay.rawValue
            ])
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
                    cueColor: settings.cards.cueColor,
                    fontSize: CGFloat(settings.cards.fontSize),
                    colorScheme: colorScheme
                )
                .scaleEffect(placement.scale, anchor: .bottom)
                .offset(x: placement.x, y: placement.y)
                .rotationEffect(.degrees(placement.rotation), anchor: .bottom)
                .opacity(placement.opacity)
                .zIndex(placement.zIndex)
                .accessibilityHidden(cardIndex != session.index)
                .allowsHitTesting(cardIndex == session.index)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(width: width))
        .animation(animation, value: session.index)
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
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let distance = value.translation.width
                let predicted = value.predictedEndTranslation.width
                guard abs(distance) > abs(value.translation.height) else {
                    withAnimation(animation) { dragOffset = 0 }
                    return
                }
                withAnimation(animation) {
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

        if settings.cardDisplay == .lockScreen || session.isOnLockScreen {
            if session.isOnLockScreen || session.lockScreenUnavailable {
                Button { showingLockScreenHelp = true } label: {
                    Label(session.isOnLockScreen ? "Also on Lock Screen" : "Enable Lock Screen cards",
                          systemImage: session.isOnLockScreen ? "lock.fill" : "lock.slash")
                        .font(.footnote)
                        .foregroundStyle(secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows Lock Screen instructions")
            } else {
                Button(action: {
                    AnalyticsEvents.logButtonClick("show_on_lock_screen", screen: "cards")
                    session.showOnLockScreen()
                }) {
                    Label("Show on Lock Screen", systemImage: "lock.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        } else if !session.isFinished {
            Text("Swipe to turn the card")
                .font(.footnote)
                .foregroundStyle(secondary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            Button(action: {
                AnalyticsEvents.logButtonClick("previous_card", screen: "cards")
                withAnimation(animation) { session.previous() }
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
                    withAnimation(animation) { session.restart() }
                } else {
                    AnalyticsEvents.logButtonClick("next_card", screen: "cards")
                    withAnimation(animation) { session.next() }
                }
            }) {
                HStack(spacing: 10) {
                    Text(nextLabel)
                    Image(systemName: session.isFinished ? "arrow.counterclockwise" :
                            (session.index == session.cards.count - 1 ? "checkmark" : "arrow.right"))
                }
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(AppColors.green(for: colorScheme)))
                .glassedEffect(in: Capsule())
            }
            .accessibilityLabel(nextLabel)
        }
    }
}

/// Where the deck is, a dot a card. A long deck shows the dots around the
/// card on top, the ones at either edge shrunk to say there are more.
private struct PageDots: View {
    let count: Int
    let index: Int
    let colorScheme: ColorScheme

    private static let maxVisible = 9
    private static let size: CGFloat = 7

    var body: some View {
        let window = visibleRange
        HStack(spacing: 8) {
            ForEach(window, id: \.self) { dot in
                Circle()
                    .fill(color(for: dot))
                    .frame(width: Self.size, height: Self.size)
                    .scaleEffect(scale(for: dot, in: window))
            }
        }
        .frame(height: Self.size)
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    private var visibleRange: Range<Int> {
        guard count > Self.maxVisible else { return 0..<count }
        let start = min(max(index - Self.maxVisible / 2, 0), count - Self.maxVisible)
        return start..<(start + Self.maxVisible)
    }

    /// The card on top in green, and every card once the deck is done.
    private func color(for dot: Int) -> Color {
        dot == index || index >= count
            ? AppColors.green(for: colorScheme)
            : AppColors.textSecondary(for: colorScheme).opacity(0.35)
    }

    private func scale(for dot: Int, in window: Range<Int>) -> CGFloat {
        let moreBefore = window.lowerBound > 0 && dot == window.lowerBound
        let moreAfter = window.upperBound < count && dot == window.upperBound - 1
        return moreBefore || moreAfter ? 0.55 : 1
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
        ScrollView {
            runs.text(primary: AppColors.textPrimary(for: colorScheme), cue: cueColor.color(for: colorScheme))
                .font(.system(size: fontSize, weight: .semibold))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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
