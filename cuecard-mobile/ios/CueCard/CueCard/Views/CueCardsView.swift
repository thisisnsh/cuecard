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
    @State private var showingHelp = false
    @State private var showingCamera = false
    /// Listens for Follow My Voice, which turns each card once its last words are said.
    @StateObject private var voice = VoiceFollower()
    @State private var deckFollower: DeckFollower?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: TeleprompterSettings { settingsService.settings }
    /// What the deck's takes are filed under: its saved note, or the ID it
    /// will be saved under.
    private var scriptID: UUID { session.deckID ?? settingsService.cardsScriptID }

    /// How far a card has to be dragged to count as a swipe.
    private static let swipeDistance: CGFloat = 90
    private static let deckAnimation = Animation.spring(response: 0.4, dampingFraction: 0.84)
    /// How far below the top card each card behind it peeks out.
    private static let peek: CGFloat = 14

    private var progress: String {
        session.isFinished ? String(localized: "Done")
            : String(localized: "\(session.index + 1) of \(session.cards.count)", comment: "Card number out of the deck's total")
    }

    private var nextLabel: String {
        if session.isFinished { return String(localized: "Start Over") }
        return session.index == session.cards.count - 1 ? String(localized: "Finish") : String(localized: "Next Card")
    }

    private var animation: Animation? { reduceMotion ? nil : Self.deckAnimation }

    var body: some View {
        CameraRecordingView(isPresented: $showingCamera, scriptID: scriptID) {
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
                                .frame(maxWidth: 600)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .cameraWindowArea()
                .navigationTitle("Cards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(AppColors.background(for: colorScheme), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            AnalyticsEvents.logButtonClick("cards_close", screen: "cards")
                            finishFollowingVoice()
                            session.end()
                            TakeStore.shared.end()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .principal) {
                        // The dots show where the deck is, so the title
                        // bar is the timer's.
                        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                            timerText(at: context.date)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(progress)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            AnalyticsEvents.logButtonClick("cards_camera", screen: "cards")
                            showingCamera.toggle()
                        } label: {
                            Image(systemName: showingCamera ? "camera.fill" : "camera")
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                        .accessibilityLabel(showingCamera ? "Close Camera" : "Record Video")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                AnalyticsEvents.logButtonClick(followsVoice ? "cards_follow_voice_off" : "cards_follow_voice_on", screen: "cards")
                                settingsService.settings.cards.followsVoice.toggle()
                            } label: {
                                Label(followsVoice ? "Turn Off Follow My Voice" : "Follow My Voice",
                                      systemImage: followsVoice ? "waveform.circle.fill" : "waveform.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                        .accessibilityLabel("Reading Options")
                        .simultaneousGesture(TapGesture().onEnded {
                            AnalyticsEvents.logButtonClick("cards_menu", screen: "cards")
                        })
                    }
                    HelpToolbarItem(page: .cards, isPresented: $showingHelp)
                }
                .helpSheet(for: .cards, isPresented: $showingHelp)
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
                                    AnalyticsEvents.logButtonClick("cards_lock_screen_open_settings", screen: "cards")
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }
                                Button("Try Again") {
                                    AnalyticsEvents.logButtonClick("cards_lock_screen_try_again", screen: "cards")
                                    session.showOnLockScreen()
                                    showingLockScreenHelp = false
                                }
                            }
                        }
                        .navigationTitle("Lock Screen")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    AnalyticsEvents.logButtonClick("cards_lock_screen_help_done", screen: "cards")
                                    showingLockScreenHelp = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "cards",
                AnalyticsParameterScreenClass: "CueCardsView"
            ])
            guard !hasOpenedDeck else { return }
            hasOpenedDeck = true
            // A video recorded from now until the deck closes is a take of it,
            // counted once the deck below is open. Listening starts then too.
            defer {
                TakeStore.shared.begin(scriptID: scriptID)
                if followsVoice { startFollowingVoice() }
            }
            guard let cards else { return }
            session.start(cards: cards, title: title, deckID: deckID,
                          showOnLockScreen: settings.cards.showOnLockScreen)
            Analytics.logEvent("cards_open", parameters: [
                "count": cards.count,
                "on_lock_screen": settings.cards.showOnLockScreen ? 1 : 0
            ])
        }
        .onDisappear {
            voice.stop()
            TakeStore.shared.end()
        }
        .onChange(of: followsVoice) { _, follows in
            if follows {
                startFollowingVoice()
            } else {
                voice.stop()
                deckFollower = nil
            }
        }
        // Another deck opened from the watch is listened for in its place.
        .onChange(of: session.sessionID) {
            guard followsVoice, !session.cards.isEmpty,
                  let deckFollower, deckFollower.sessionID != session.sessionID else { return }
            voice.stop()
            startFollowingVoice()
        }
    }

    // MARK: - Follow My Voice

    private var followsVoice: Bool { settings.cards.followsVoice }

    /// Turn the cards with the reader's voice, and start listening.
    private func startFollowingVoice() {
        let follower = DeckFollower(deck: SpokenDeck(cards: session.cards), sessionID: session.sessionID)
        deckFollower = follower
        let animation = animation
        voice.screen = "cards"
        voice.readingCharacter = { follower.readingCharacter(onCard: CueCardsSession.shared.index) }
        voice.onProgress = { character in
            follower.lastCharacter = character
            let card = follower.deck.card(at: character)
            let session = CueCardsSession.shared
            let current = session.index
            guard card != current else { return }
            withAnimation(animation) { session.show(cardAt: card) }
            Analytics.logEvent(card > current ? "cards_next" : "cards_previous", parameters: ["source": "voice"])
        }
        listen()
    }

    private func listen() {
        guard let deckFollower else { return }
        Task { await voice.start(text: deckFollower.deck.text) }
    }

    /// After a session long enough to judge, ask how it went.
    private func finishFollowingVoice() {
        guard followsVoice else { return }
        voice.stop()
        let metrics = voice.metrics
        Analytics.logEvent("follow_voice_session", parameters: VoiceFeedback.parameters(for: metrics))
        if metrics.listenedSeconds >= VoiceFeedback.minimumSeconds {
            VoiceFeedback.shared.pending = metrics
        }
    }

    /// What Follow My Voice is doing, or why it can't. A tap stops or
    /// starts listening.
    private var voiceStatus: some View {
        let label: (text: String, icon: String) = switch voice.status {
        case .unavailable(let reason): (reason, "exclamationmark.triangle")
        case .listening: (String(localized: "Listening. Each card turns when you finish it."), "waveform")
        case .idle: (String(localized: "Not listening. Tap to listen."), "mic.slash")
        }
        return Button {
            AnalyticsEvents.logButtonClick(voice.isListening ? "cards_follow_voice_stop" : "cards_follow_voice_listen",
                                           screen: "cards")
            if voice.isListening {
                voice.stop()
            } else {
                listen()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: label.icon)
                    .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                Text(label.text)
                    .lineLimit(3)
                BetaBadge()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassedEffect(in: Capsule(), interactive: true)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint(voice.isListening ? "Stops listening" : "Starts listening")
    }

    // MARK: - Timer

    /// Time left on the cards timer, or time since the deck opened with no
    /// timer set, the way the teleprompter shows it.
    @ViewBuilder
    private func timerText(at date: Date) -> some View {
        if let state = session.timerState(at: date) {
            let elapsed = Int(date.timeIntervalSince(session.startedAt))
            let seconds = session.timerDuration > 0 ? session.timerDuration - elapsed : elapsed
            Text(" \(TeleprompterParser.formatTime(seconds)) ")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(state.tint.color(for: colorScheme))
        }
    }

    // MARK: - Deck

    /// The card before the top one waits just off the left edge, ready to be
    /// swiped back in. The next two sit behind the top card, peeking out below.
    /// Every card keeps its identity as it moves between those places, so a
    /// swipe, a button and the Lock Screen all animate the deck the same way.
    ///
    /// The cards and their words are drawn apart, for the camera to sit
    /// between them: over the cards, under the words.
    private func deck(width: CGFloat) -> some View {
        let lower = max(session.index - 1, 0)
        let upper = min(session.index + 3, session.cards.count)

        return ZStack {
            ZStack {
                if session.isFinished {
                    finishedCard
                        .transition(.opacity)
                }

                ForEach(lower..<upper, id: \.self) { cardIndex in
                    let placement = placement(of: cardIndex - session.index, width: width)
                    place(CueCardBack(colorScheme: colorScheme), at: placement)
                        .zIndex(placement.zIndex)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }

            CameraBackdrop()

            ZStack {
                ForEach(lower..<upper, id: \.self) { cardIndex in
                    let offset = cardIndex - session.index
                    let placement = placement(of: offset, width: width)
                    place(CueCardFace(
                        card: session.cards[cardIndex],
                        cueColor: settings.cards.cueColor,
                        fontSize: CGFloat(settings.cards.fontSize),
                        colorScheme: colorScheme
                    ), at: placement)
                    // The words are drawn over every card, so those of the
                    // cards behind the top one are left out, and the top
                    // card's are cleared where the card before it passes over.
                    .opacity(offset > 0 ? 0 : 1)
                    .mask { uncovered(by: offset - 1, width: width, isCovered: cardIndex > 0 && offset >= 0) }
                    .zIndex(placement.zIndex)
                    .accessibilityHidden(cardIndex != session.index)
                    .allowsHitTesting(cardIndex == session.index)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(width: width))
        .animation(animation, value: session.index)
    }

    private func place(_ card: some View, at placement: Placement) -> some View {
        card
            .scaleEffect(placement.scale, anchor: .bottom)
            .offset(x: placement.x, y: placement.y)
            .rotationEffect(.degrees(placement.rotation), anchor: .bottom)
            .opacity(placement.opacity)
    }

    /// A mask leaving out the card at `offset`. Always drawn, so the hole
    /// follows the card through every animation. Uncovered, it waits further
    /// off screen than any card: cards past the left edge share one place.
    ///
    /// The mask reaches well past the deck, which sits inset from the screen,
    /// so a card's words aren't cut off as it's swiped toward the edge.
    private func uncovered(by offset: Int, width: CGFloat, isCovered: Bool) -> some View {
        place(RoundedRectangle(cornerRadius: CueCardFace.cornerRadius, style: .continuous),
              at: isCovered ? placement(of: offset, width: width) : Placement(x: -2 * (width + 60)))
            .opacity(isCovered ? 1 : 0)
            .blendMode(.destinationOut)
            .background { Rectangle().padding(-2 * (width + 60)) }
            .compositingGroup()
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

    /// Whether the deck is on the Lock Screen too, or else how to move
    /// through it. A deck meant for the Lock Screen says so from the start,
    /// not only once its Live Activity is up.
    @ViewBuilder
    private var hint: some View {
        let secondary = AppColors.textSecondary(for: colorScheme)
        let unavailable = session.lockScreenUnavailable && !session.isOnLockScreen

        if followsVoice {
            voiceStatus
        } else if session.isOnLockScreen || settings.cards.showOnLockScreen {
            Button {
                AnalyticsEvents.logButtonClick("cards_lock_screen_help", screen: "cards")
                showingLockScreenHelp = true
            } label: {
                Label(unavailable ? "Enable Lock Screen cards" : "Also on Lock Screen",
                      systemImage: unavailable ? "lock.slash" : "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows Lock Screen instructions")
        } else if !session.isFinished {
            Text("Swipe to turn the card")
                .font(.footnote)
                .foregroundStyle(secondary)
                .frame(minHeight: 44)
        }
    }

    // MARK: - Controls

    /// A stable back control and a wider primary action, within thumb reach.
    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: {
                AnalyticsEvents.logButtonClick("previous_card", screen: "cards")
                withAnimation(animation) { session.previous() }
            }) {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassedEffect(in: Capsule())
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
                HStack(spacing: 8) {
                    Text(nextLabel)
                    Image(systemName: session.isFinished ? "arrow.counterclockwise" :
                            (session.index == session.cards.count - 1 ? "checkmark" : "arrow.right"))
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(AppColors.green(for: colorScheme)))
                .glassedEffect(in: Capsule())
            }
            .accessibilityLabel(nextLabel)
        }
    }
}

/// Where the reader's voice has got to in the deck, and so which card it's on.
@MainActor
private final class DeckFollower {
    let deck: SpokenDeck
    /// The deck's session, so it's listened for again only when another opens.
    let sessionID: UUID
    /// The spot in the deck the voice last reached.
    var lastCharacter: Double?

    init(deck: SpokenDeck, sessionID: UUID) {
        self.deck = deck
        self.sessionID = sessionID
    }

    /// Where reading is: as far as the voice got, while that's on the card
    /// showing. A card turned some other way — a swipe, the watch, the Lock
    /// Screen — is read from its start.
    func readingCharacter(onCard index: Int) -> Double {
        if let lastCharacter, deck.card(at: lastCharacter) == index { return lastCharacter }
        return deck.start(ofCard: index)
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

/// One card of the deck, without its words.
private struct CueCardBack: View {
    let colorScheme: ColorScheme

    static func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.11) : Color.white
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CueCardFace.cornerRadius, style: .continuous)
        shape
            .fill(Self.color(for: colorScheme))
            .overlay(shape.stroke(AppColors.textSecondary(for: colorScheme).opacity(0.2), lineWidth: 0.7))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 16, y: 6)
    }
}

/// The words on one card of the deck, cues drawn in their color, and its
/// images, drawn over its `CueCardBack`.
private struct CueCardFace: View {
    let card: String
    let cueColor: CueColor
    let fontSize: CGFloat
    let colorScheme: ColorScheme

    static let cornerRadius: CGFloat = 28
    private static let padding: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(CardBlock.blocks(for: card).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let runs):
                            text(runs)
                        case .image(let name):
                            // An image on its own fills the card.
                            ScriptImageView(name: name)
                                .frame(maxHeight: max(geometry.size.height - Self.padding * 2, 0))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.padding)
            }
            .scrollEdgeFade(length: Self.padding, insetContent: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private func text(_ runs: [CueCardRun]) -> some View {
        runs.text(primary: AppColors.textPrimary(for: colorScheme), cue: cueColor.color(for: colorScheme),
                  cueFont: .system(size: fontSize * 0.82, weight: .semibold))
            .font(.system(size: fontSize, weight: .semibold))
            .lineSpacing(runs.hasWideScript ? WideScript.lineSpacing(ofSize: fontSize) : 4)
            // In the card's color, so the words stay readable over the
            // camera drawn behind them. Over the card itself it doesn't show.
            .shadow(color: CueCardBack.color(for: colorScheme), radius: 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One stretch of a card as the app draws it: words, or an image.
private enum CardBlock {
    case text([CueCardRun])
    /// The image's file name
    case image(String)

    /// A card's words broken around its images, each image a block of its
    /// own however it was written.
    static func blocks(for card: String) -> [CardBlock] {
        let nsCard = card as NSString
        var blocks: [CardBlock] = []
        var start = 0

        func appendText(upTo end: Int) {
            let text = nsCard.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.text(CueCards.runs(for: text))) }
        }

        for match in TeleprompterParser.imageMatches(in: card) {
            appendText(upTo: match.range.location)
            blocks.append(.image(match.name))
            start = NSMaxRange(match.range)
        }
        appendText(upTo: nsCard.length)
        return blocks
    }
}
