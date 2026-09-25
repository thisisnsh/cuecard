import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import FirebaseAnalytics
import FirebaseCrashlytics

struct HomeView: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var notifications: RemoteNotificationService
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingTeleprompter = false
    @State private var showingCards = false
    /// The cards showing were opened from the watch, not from the editor.
    @State private var cardsOpenedOnWatch = false
    @State private var showingTimerPicker = false
    @State private var timerPickerContentVisible = false
    @State private var showingSavedNotes = false
    @State private var showingSaveDialog = false
    @State private var saveNoteTitle = ""
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: ScriptDocument?
    @State private var exportFileName = "Speech"
    @State private var fileErrorMessage: String?
    @State private var timerPickerTransitionTask: Task<Void, Never>?
    @State private var isEditorFocused = false
    @StateObject private var editorController = CueEditorController()
    @ObservedObject private var watch = WatchSessionService.shared
    @ObservedObject private var cardsSession = CueCardsSession.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// How much of the editor's bottom the controls row covers: the play button
    /// and the timer beside it, plus the gap they sit above. The script keeps this
    /// much room clear so its last line never rests underneath them.
    private static let controlsHeight: CGFloat = 52 + 24

    /// How far the editor reaches up under the top bar: to its middle, so the
    /// script fades out from there down, as gently as it does at the bottom.
    /// Not while a banner sits between the two.
    private var editorTopOverlap: CGFloat {
        notifications.notification(for: .homeBanner) == nil ? 22 : 0
    }

    private var hasNotes: Bool {
        !settingsService.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCardsMode: Bool { settingsService.settings.scriptMode == .cards }

    /// Teleprompter or cards: what the editor writes and the Play button opens.
    /// The bar shows the chosen mode's name.
    private var modeMenu: some View {
        let current = settingsService.settings.scriptMode

        // Plain buttons rather than a picker, so the menu shows no checkmark:
        // the bar already says which mode is on.
        return Menu {
            ForEach(ScriptMode.allCases) { mode in
                Button {
                    AnalyticsEvents.logButtonClick("mode_\(mode.rawValue)", screen: "home")
                    if showingTimerPicker { closeTimerPicker() }
                    isEditorFocused = false
                    settingsService.settings.scriptMode = mode
                } label: {
                    Text(mode.displayName)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(current.displayName)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .fixedSize()
        }
        .accessibilityLabel("Mode: \(current.displayName)")
    }

    private func showCardsOpenedOnWatch() {
        guard scenePhase == .active, !cardsSession.cards.isEmpty, !showingCards,
              !showingTeleprompter, !showingSettings, !showingSavedNotes, !showingHelp else { return }
        cardsOpenedOnWatch = true
        showingCards = true
    }

    private func openTimerPicker() {
        timerPickerTransitionTask?.cancel()

        AnalyticsEvents.logButtonClick("set_timer", screen: "home")

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showingTimerPicker = true
        }

        timerPickerTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                timerPickerContentVisible = true
            }
        }
    }

    /// Ask for a review once the teleprompter has closed and the user is back on a
    /// calm screen. The delay lets the full-screen dismissal finish first, so the
    /// system alert doesn't land on top of an animating view.
    private func requestReviewIfEarned() {
        guard ReviewPromptService.shared.shouldRequestReview else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            ReviewPromptService.shared.logReviewRequested()
            requestReview()
        }
    }

    private func closeTimerPicker() {
        timerPickerTransitionTask?.cancel()

        AnalyticsEvents.logButtonClick("close_timer_picker", screen: "home")

        withAnimation(.easeInOut(duration: 0.18)) {
            timerPickerContentVisible = false
        }

        timerPickerTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showingTimerPicker = false
            }
        }
    }

    @ViewBuilder
    private var timerControl: some View {
        if hasNotes || showingTimerPicker {
            VStack(alignment: .leading, spacing: 0) {
                if showingTimerPicker {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Timer")
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                            Spacer()

                            Button(action: closeTimerPicker) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                                    .padding(6)
                                    .background(
                                        Circle()
                                            .fill(AppColors.background(for: colorScheme).opacity(0.85))
                                    )
                            }
                        }

                        HStack(spacing: 12) {
                            Text("Duration")
                                .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                            Spacer()

                            Picker("Minutes", selection: $settingsService.settings.activeTimerMinutes) {
                                ForEach(0..<60) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 60, height: 88)
                            .clipped()

                            Text(":")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                            Picker("Seconds", selection: $settingsService.settings.activeTimerSeconds) {
                                ForEach(0..<60) { second in
                                    Text(String(format: "%02d", second)).tag(second)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 60, height: 88)
                            .clipped()
                        }
                    }
                    .opacity(timerPickerContentVisible ? 1 : 0)
                    .allowsHitTesting(timerPickerContentVisible)
                } else {
                    Button(action: openTimerPicker) {
                        Text("Set Timer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(showingTimerPicker ? 12 : 0)
            .glassedEffect(
                in: RoundedRectangle(
                    cornerRadius: showingTimerPicker ? 16 : 26,
                    style: .continuous
                )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10)
        } else {
            Button(action: {
                AnalyticsEvents.logButtonClick("add_sample_text", screen: "home")
                settingsService.addSampleText()
            }) {
                Text("Add Sample Text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassedEffect(in: Capsule())
            }
        }
    }

    private func startExport() {
        exportDocument = ScriptDocument(text: TeleprompterParser.normalizingTags(in: settingsService.notes))
        exportFileName = ScriptFile.suggestedFileName(
            title: settingsService.currentNote?.title,
            content: settingsService.notes
        )
        showingExporter = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let text = try ScriptFile.readText(from: url)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fileErrorMessage = "That file is empty."
                    return
                }
                settingsService.importNote(
                    title: ScriptFile.title(for: url),
                    content: TeleprompterParser.normalizingTags(in: text)
                )
            } catch {
                fileErrorMessage = "This file couldn't be read as text."
            }
        case .failure(let error):
            fileErrorMessage = error.localizedDescription
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        exportDocument = nil
        if case .failure(let error) = result {
            fileErrorMessage = error.localizedDescription
        }
    }

    /// Drop an empty cue in at the caret and leave the caret inside it, so the user
    /// can write the cue without hunting for their place.
    private func insertCue() {
        AnalyticsEvents.logButtonClick("insert_cue", screen: "home")
        editorController.insertCue()
    }

    private func selectAllText() {
        AnalyticsEvents.logButtonClick("select_all", screen: "home")
        editorController.selectAll()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background - matches TeleprompterView
                AppColors.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Anything the worker wants people to see, above the script.
                    // Nothing to show is the normal case, and then this is a
                    // zero-height view the layout never notices.
                    if let notification = notifications.notification(for: .homeBanner) {
                        NotificationBanner(notification: notification)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isCardsMode {
                        CardsEditorView(
                            text: $settingsService.notes,
                            isFocused: $isEditorFocused,
                            controller: editorController,
                            cueColor: settingsService.settings.cards.cueColor,
                            colorScheme: colorScheme,
                            fontSize: CGFloat(settingsService.settings.cards.editorFontSize),
                            cardLimit: settingsService.settings.cards.characterLimit,
                            bottomInset: isEditorFocused ? CueBar.height : Self.controlsHeight,
                            topOverlap: editorTopOverlap
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Notes editor
                        NotesEditorView(
                            text: $settingsService.notes,
                            isFocused: $isEditorFocused,
                            controller: editorController,
                            cueColor: settingsService.settings.cueColor,
                            colorScheme: colorScheme,
                            fontSize: CGFloat(settingsService.settings.editorFontSize),
                            keyboardOverlayHeight: CueBar.height,
                            restingOverlayHeight: Self.controlsHeight,
                            topOverlap: editorTopOverlap
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // The editor makes its own room for the keyboard, as scroll
                        // inset. SwiftUI's avoidance would resize it instead, and the
                        // gap it leaves behind on dismissal cuts the script off.
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: notifications.dismissedIDs)
            }
            .overlay(alignment: .bottom) {
                if isEditorFocused {
                    CueBar(
                        colorScheme: colorScheme,
                        onAddCue: insertCue,
                        onSelectAll: selectAllText,
                        onDismissKeyboard: { isEditorFocused = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        timerControl
                    }

                    Spacer(minLength: isCardsMode ? 0 : 12)

                    Button(action: {
                        isEditorFocused = false
                        if isCardsMode {
                            AnalyticsEvents.logButtonClick("start_cards", screen: "home")
                            cardsOpenedOnWatch = false
                            showingCards = true
                        } else {
                            AnalyticsEvents.logButtonClick("start_teleprompter", screen: "home")
                            showingTeleprompter = true
                        }
                    }) {
                        if isCardsMode {
                            Label("Read Cards", systemImage: "rectangle.stack.fill")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .background(Capsule().fill(AppColors.green(for: colorScheme)))
                                .glassedEffect(in: Capsule())
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                                .frame(width: 52, height: 52)
                                .background(
                                    Circle()
                                        .fill(AppColors.green(for: colorScheme))
                                )
                                .glassedEffect(in: Circle())
                        }
                    }
                    .disabled(isCardsMode ? CueCards.cards(in: settingsService.notes).isEmpty : !hasNotes)
                    .opacity(hasNotes ? 1.0 : 0.6)
                    .accessibilityLabel(isCardsMode ? "Open Cards" : "Start Teleprompter")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isEditorFocused)
            .navigationBarTitleDisplayMode(.inline)
            // No bar background: the script's fade shows through its lower half.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    modeMenu
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            if settingsService.currentNoteId != nil && settingsService.hasUnsavedChanges {
                                Button(action: {
                                    AnalyticsEvents.logButtonClick("save_note", screen: "home")
                                    settingsService.saveChangesToCurrentNote()
                                }) {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                }
                            }

                            Button(action: {
                                AnalyticsEvents.logButtonClick("save_as_new", screen: "home")
                                saveNoteTitle = ""
                                showingSaveDialog = true
                            }) {
                                Label("Save as New", systemImage: "doc.badge.plus")
                            }
                            .disabled(!hasNotes)

                            if watch.isWatchAppInstalled, let note = settingsService.currentNote {
                                let isOnWatch = settingsService.watchNoteIDs.contains(note.id)
                                Button(action: {
                                    AnalyticsEvents.logButtonClick(isOnWatch ? "watch_remove_note" : "watch_add_note",
                                                                   screen: "home")
                                    settingsService.setOnWatch(!isOnWatch, noteID: note.id)
                                }) {
                                    Label(isOnWatch ? "Remove from Apple Watch" : "Keep on Apple Watch",
                                          systemImage: isOnWatch ? "applewatch.slash" : "applewatch")
                                }
                            }

                            Divider()

                            Button(action: {
                                AnalyticsEvents.logButtonClick("new_note", screen: "home")
                                settingsService.createNewNote()
                            }) {
                                Label("New", systemImage: "square.and.pencil")
                            }

                            Divider()

                            Button(action: {
                                AnalyticsEvents.logButtonClick("saved_notes", screen: "home")
                                showingSavedNotes = true
                            }) {
                                Label("Saved Content", systemImage: "folder")
                            }

                            Button(action: {
                                AnalyticsEvents.logButtonClick("import_file", screen: "home")
                                showingImporter = true
                            }) {
                                Label("Import from File", systemImage: "arrow.down.doc")
                            }

                            Button(action: {
                                AnalyticsEvents.logButtonClick("export_file", screen: "home")
                                startExport()
                            }) {
                                Label("Export to File", systemImage: "arrow.up.doc")
                            }
                            .disabled(!hasNotes)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                        .menuActionDismissBehavior(.enabled)

                        Button(action: {
                            AnalyticsEvents.logButtonClick("settings", screen: "home")
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                    }
                }

                HelpToolbarItem(page: .writing(settingsService.settings.scriptMode), isPresented: $showingHelp)
            }
            .helpSheet(for: .writing(settingsService.settings.scriptMode), isPresented: $showingHelp)
            .sheet(isPresented: $showingSettings) {
                EditorSettingsView()
            }
            .sheet(isPresented: $showingSavedNotes) {
                SavedNotesView()
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note title", text: $saveNoteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let title = saveNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        settingsService.saveCurrentNote(title: title)
                    }
                }
            } message: {
                Text("Enter a title for your note")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: ScriptFile.importableContentTypes
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: exportFileName
            ) { result in
                handleExport(result)
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { fileErrorMessage != nil },
                set: { if !$0 { fileErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { fileErrorMessage = nil }
            } message: {
                Text(fileErrorMessage ?? "")
            }
            .fullScreenCover(isPresented: $showingTeleprompter, onDismiss: requestReviewIfEarned) {
                TeleprompterView(content: TeleprompterParser.parseNotes(settingsService.notes))
                    // Passed on by hand: as an iPad app on a Mac, a full screen
                    // cover doesn't inherit environment objects.
                    .environmentObject(settingsService)
            }
            .fullScreenCover(isPresented: $showingCards) {
                CueCardsView(cards: cardsOpenedOnWatch ? nil : CueCards.cards(in: settingsService.notes),
                             title: settingsService.currentNote?.title ?? "Cards",
                             deckID: settingsService.currentNoteId)
                    .environmentObject(settingsService)
            }
            // A deck opened from the watch comes up here too, if nothing else is.
            .onChange(of: cardsSession.sessionID) {
                showCardsOpenedOnWatch()
            }
            .onChange(of: scenePhase) {
                showCardsOpenedOnWatch()
            }
        }
        .onAppear {
            showCardsOpenedOnWatch()
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "home",
                AnalyticsParameterScreenClass: "HomeView"
            ])
        }
    }
}

/// Notes editor with live syntax highlighting for [cue] tags
struct NotesEditorView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let controller: CueEditorController
    let cueColor: CueColor
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    /// Room the cue bar takes at the bottom while the keyboard is up.
    var keyboardOverlayHeight: CGFloat = 0
    /// Room the home controls take at the bottom once the keyboard has gone.
    var restingOverlayHeight: CGFloat = 0
    /// How far the editor reaches up under the top bar, for the fade to start there.
    var topOverlap: CGFloat = 0

    private var topFade: CGFloat { CueTextEditor.edgeFade + topOverlap }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                // Set on the editor's own font and insets, so the first line sits
                // exactly where the caret waiting in front of it does.
                Text("Add your script here...\n\nTap Add Cue to drop in a delivery reminder, or type [ to write one yourself.\n\nFor example: Welcome everyone [cue smile and pause]")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.top, topFade)
                    .allowsHitTesting(false)
            }

            CueTextEditor(
                text: $text,
                isFocused: $isFocused,
                controller: controller,
                cueColor: cueColor,
                colorScheme: colorScheme,
                fontSize: fontSize,
                keyboardOverlayHeight: keyboardOverlayHeight,
                restingOverlayHeight: restingOverlayHeight,
                topInset: topFade
            )
            .padding(.horizontal, 4)
        }
        // Lines arrive and leave through a fade instead of being cut off against
        // the toolbar above and the controls below.
        .scriptEdgeFade(for: colorScheme, top: topFade, bottom: Self.bottomFade)
        .padding(.top, -topOverlap)
    }

    /// The bottom fade reaches up past the floating controls, so a line is gone
    /// before it can pass behind them.
    private static let bottomFade: CGFloat = 72
}

/// Cards mode's editor: every card its own page, written on separately, with
/// a button below the last one to start another. A swipe removes a card.
///
/// The deck is stored as one script with a separator between cards; the
/// separators are only ever written here, never shown.
struct CardsEditorView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let controller: CueEditorController
    let cueColor: CueColor
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    /// The characters a card holds before the rest is marked.
    let cardLimit: Int
    /// Room kept clear below the last card for what floats over the list.
    let bottomInset: CGFloat
    /// How far the list reaches up under the top bar, for the fade to start there.
    var topOverlap: CGFloat = 0

    private struct EditableCard: Identifiable {
        let id = UUID()
        var text: String
    }

    @State private var cards: [EditableCard] = []
    /// The script last written from `cards`, so an edit made here isn't read
    /// back in as a whole new deck.
    @State private var writtenText: String?
    @State private var focusedCard: UUID?

    static let cornerRadius: CGFloat = 22
    private static let newCardButtonID = "new-card"
    /// The first card starts below the top fade, never inside it.
    private static let topFade: CGFloat = 20

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    cardRow(card, number: index + 1)
                        .id(card.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                AnalyticsEvents.logButtonClick("remove_card", screen: "home")
                                remove(card.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }

                Button {
                    AnalyticsEvents.logButtonClick("insert_card", screen: "home")
                    addCard(scrollingWith: proxy)
                } label: {
                    Label("Create New Card", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .stroke(AppColors.textSecondary(for: colorScheme).opacity(0.35),
                                        style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(Self.newCardButtonID)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .topScrollEdgeEffectHidden()
            .contentMargins(.top, topOverlap + Self.topFade - 8, for: .scrollContent)
            .contentMargins(.bottom, bottomInset + 16, for: .scrollContent)
        }
        // A list draws on past its frame into the home indicator's strip, below
        // where the fade ends. Kept inside it, the cards fade out before the
        // edge like the script does.
        .clipped()
        // The bottom fade reaches up past what floats over the list, so a card
        // is gone before it passes behind the controls or the cue bar.
        .scriptEdgeFade(for: colorScheme, top: topOverlap + Self.topFade, bottom: bottomInset)
        .padding(.top, -topOverlap)
        .onAppear(perform: loadCards)
        .onChange(of: text) {
            guard text != writtenText else { return }
            loadCards()
        }
        .onChange(of: focusedCard) {
            let hasFocus = focusedCard != nil
            if isFocused != hasFocus { isFocused = hasFocus }
        }
        .onChange(of: isFocused) {
            if !isFocused {
                focusedCard = nil
            } else if focusedCard == nil {
                focusedCard = cards.last?.id
            }
        }
    }

    private func cardRow(_ card: EditableCard, number: Int) -> some View {
        let measure = CueCards.measure(card: card.text, limit: cardLimit)
        let isOver = measure.overflow != nil
        // The count only shows once a card is getting close to full.
        let showsCount = measure.length * 5 >= cardLimit * 4
        let secondary = AppColors.textSecondary(for: colorScheme)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Card \(number)")
                    .foregroundStyle(secondary)
                Spacer()
                if showsCount {
                    Text("\(measure.length)/\(cardLimit)")
                        .foregroundStyle(isOver ? AppColors.red(for: colorScheme) : secondary)
                }
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .accessibilityElement(children: .combine)

            ZStack(alignment: .topLeading) {
                if card.text.isEmpty {
                    Text(placeholder(forCardNumber: number))
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(secondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                }

                CueTextEditor(
                    text: binding(for: card.id),
                    isFocused: focusBinding(for: card.id),
                    controller: controller,
                    cueColor: cueColor,
                    colorScheme: colorScheme,
                    fontSize: fontSize,
                    cardLimit: cardLimit,
                    growsWithText: true,
                    keyboardOverlayHeight: CueBar.height
                )
            }
            .frame(minHeight: fontSize * 3, alignment: .topLeading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.11) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(isOver ? AppColors.red(for: colorScheme).opacity(0.6)
                               : AppColors.textSecondary(for: colorScheme).opacity(0.2),
                        lineWidth: isOver ? 1 : 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        // A tap on the card around the text still starts writing in it.
        .onTapGesture { focusedCard = card.id }
    }

    /// The first card explains the deck. Later ones only ask for the next
    /// thought, since by then it's clear what a card is.
    private func placeholder(forCardNumber number: Int) -> String {
        number == 1
            ? "One thought per card.\n\nType [ or tap Add Cue for reminders like [cue pause]."
            : "Your next thought…"
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { cards.first { $0.id == id }?.text ?? "" },
            set: { newText in
                guard let index = cards.firstIndex(where: { $0.id == id }),
                      cards[index].text != newText else { return }
                cards[index].text = newText
                writeScript()
            }
        )
    }

    private func focusBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { focusedCard == id },
            set: { isFocused in
                if isFocused {
                    focusedCard = id
                } else if focusedCard == id {
                    focusedCard = nil
                }
            }
        )
    }

    /// Start writing in a new card after the last, or in the last one if it
    /// hasn't been written in yet.
    private func addCard(scrollingWith proxy: ScrollViewProxy) {
        if let last = cards.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedCard = last.id
            withAnimation { proxy.scrollTo(Self.newCardButtonID, anchor: .bottom) }
            return
        }

        let card = EditableCard(text: "")
        cards.append(card)
        writeScript()
        focusedCard = card.id
        // After the new row is laid out, so there is somewhere to scroll to.
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(Self.newCardButtonID, anchor: .bottom) }
        }
    }

    /// Take a card out of the deck. The last one left is emptied instead, so
    /// there is always a card to write in.
    private func remove(_ id: UUID) {
        if focusedCard == id { focusedCard = nil }
        if cards.count == 1 {
            cards = [EditableCard(text: "")]
        } else {
            cards.removeAll { $0.id == id }
        }
        writeScript()
    }

    private func loadCards() {
        cards = CueCards.editableCards(in: text).map { EditableCard(text: $0) }
        writtenText = text
    }

    private func writeScript() {
        let script = CueCards.script(for: cards.map(\.text))
        writtenText = script
        if text != script { text = script }
    }
}

/// View for displaying and managing saved notes
struct SavedNotesView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var noteToRename: SavedNote?
    @State private var showingHelp = false
    @State private var renameTitle = ""

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// The start of a note, with card breaks read as spaces.
    private func preview(of note: SavedNote) -> String {
        String(CueCards.removingSeparators(from: note.content).prefix(120))
            .replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        NavigationStack {
            Group {
                if settingsService.savedNotes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                        Text("No Saved Content")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                        Text("Save your scripts and cards to open them later")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background(for: colorScheme))
                } else {
                    List {
                        ForEach(settingsService.savedNotes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                            Button(action: {
                                AnalyticsEvents.logButtonClick("load_note", screen: "saved_notes", parameters: ["note_id": note.id.uuidString])
                                settingsService.loadNote(note)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(note.title)
                                            .font(.headline)
                                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                                        if note.mode == .cards {
                                            Text("Cards")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppColors.green(for: colorScheme))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(AppColors.green(for: colorScheme).opacity(0.15)))
                                        }
                                    }

                                    Text(preview(of: note))
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                                        .lineLimit(2)

                                    Text(dateFormatter.string(from: note.updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.7))
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    AnalyticsEvents.logButtonClick("delete_note", screen: "saved_notes", parameters: ["note_id": note.id.uuidString])
                                    settingsService.deleteNote(id: note.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    AnalyticsEvents.logButtonClick("rename_note", screen: "saved_notes", parameters: ["note_id": note.id.uuidString])
                                    renameTitle = note.title
                                    noteToRename = note
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: "saved_notes")
                        dismiss()
                    }
                }
                HelpToolbarItem(page: .savedContent, isPresented: $showingHelp)
            }
            .helpSheet(for: .savedContent, isPresented: $showingHelp)
            .alert("Rename Note", isPresented: Binding(
                get: { noteToRename != nil },
                set: { if !$0 { noteToRename = nil } }
            )) {
                TextField("Note title", text: $renameTitle)
                Button("Cancel", role: .cancel) {
                    noteToRename = nil
                }
                Button("Rename") {
                    if let note = noteToRename {
                        let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty {
                            settingsService.updateNote(id: note.id, title: title)
                        }
                    }
                    noteToRename = nil
                }
            } message: {
                Text("Enter a new title for your note")
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteNotificationService.shared)
}

#Preview("Saved Notes") {
    SavedNotesView()
        .environmentObject(SettingsService.shared)
}
