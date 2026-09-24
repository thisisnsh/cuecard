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

    private var hasNotes: Bool {
        !settingsService.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCardsMode: Bool { settingsService.settings.scriptMode == .cards }

    /// Teleprompter or cards: what the editor writes and the Play button opens.
    private var modeMenu: some View {
        let current = settingsService.settings.scriptMode

        return Menu {
            Picker("Mode", selection: Binding(
                get: { settingsService.settings.scriptMode },
                set: { mode in
                    AnalyticsEvents.logButtonClick("mode_\(mode.rawValue)", screen: "home")
                    if showingTimerPicker { closeTimerPicker() }
                    isEditorFocused = false
                    settingsService.settings.scriptMode = mode
                }
            )) {
                ForEach(ScriptMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode)
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

    /// Where the cards will be read. It is chosen before writing, since it sets
    /// how long each card can be, so the menu says so beside each choice.
    private var cardDisplayMenu: some View {
        let current = settingsService.settings.cardDisplay

        return Menu {
            Section("Where will you read your cards?") {
                ForEach(CardDisplay.allCases) { display in
                    Button(action: {
                        AnalyticsEvents.logButtonClick("card_display_\(display.rawValue)", screen: "home")
                        settingsService.settings.cardDisplay = display
                    }) {
                        Label(display.displayName, systemImage: display == current ? "checkmark" : display.systemImage)
                        Text("Up to \(display.characterLimit) characters a card")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(current.displayName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Show cards on the \(current.displayName)")
    }

    /// The card being written and how full it is, or once the keyboard has
    /// gone, how many cards there are and how many run too long.
    @ViewBuilder
    private var cardStatus: some View {
        let notes = settingsService.notes
        let limit = settingsService.settings.cardDisplay.characterLimit
        let red = AppColors.red(for: colorScheme)

        Group {
            if isEditorFocused {
                let position = CueCards.position(of: editorController.caretLocation, in: notes, limit: limit)
                let isOver = position.measure.overflow != nil
                HStack(spacing: 6) {
                    Text(position.number.map { "Card \($0)" } ?? "New card")
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    Text("\(position.measure.length)/\(limit)")
                        .foregroundStyle(isOver ? red : AppColors.textPrimary(for: colorScheme))
                }
            } else {
                let count = CueCards.cards(in: notes).count
                let overflowing = CueCards.overflowingCount(in: notes, limit: limit)
                HStack(spacing: 6) {
                    Text(count == 1 ? "1 card" : "\(count) cards")
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    if overflowing > 0 {
                        Text("\(overflowing) too long")
                            .foregroundStyle(red)
                    }
                }
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    private func showCardsOpenedOnWatch() {
        guard scenePhase == .active, !cardsSession.cards.isEmpty, !showingCards,
              !showingTeleprompter, !showingSettings, !showingSavedNotes else { return }
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
        if isCardsMode && hasNotes {
            Button(action: insertCard) {
                Label("Add Card", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassedEffect(in: Capsule())
            }
        } else if hasNotes || showingTimerPicker {
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

                            Picker("Minutes", selection: $settingsService.settings.timerMinutes) {
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

                            Picker("Seconds", selection: $settingsService.settings.timerSeconds) {
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

    /// End the card being written and start the next one at the caret.
    private func insertCard() {
        AnalyticsEvents.logButtonClick("insert_card", screen: "home")
        editorController.insertCardSeparator()
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
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                cardDisplayMenu
                                Spacer(minLength: 8)
                                cardStatus
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                cardDisplayMenu
                                cardStatus
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }

                    // Notes editor
                    NotesEditorView(
                        text: $settingsService.notes,
                        isFocused: $isEditorFocused,
                        controller: editorController,
                        cueColor: settingsService.settings.cueColor,
                        colorScheme: colorScheme,
                        fontSize: CGFloat(settingsService.settings.editorFontSize),
                        mode: settingsService.settings.scriptMode,
                        cardLimit: isCardsMode ? settingsService.settings.cardDisplay.characterLimit : nil,
                        keyboardOverlayHeight: CueBar.height,
                        restingOverlayHeight: Self.controlsHeight
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The editor makes its own room for the keyboard, as scroll
                    // inset. SwiftUI's avoidance would resize it instead, and the
                    // gap it leaves behind on dismissal cuts the script off.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
                .animation(.easeInOut(duration: 0.25), value: notifications.dismissedIDs)
            }
            .overlay(alignment: .bottom) {
                if isEditorFocused {
                    CueBar(
                        colorScheme: colorScheme,
                        onAddCue: insertCue,
                        onAddCard: isCardsMode ? insertCard : nil,
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
            .navigationTitle("CueCard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

                            Button(action: {
                                AnalyticsEvents.logButtonClick("saved_notes", screen: "home")
                                showingSavedNotes = true
                            }) {
                                Label("Saved Content", systemImage: "folder")
                            }

                            Divider()

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
            }
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
    var mode: ScriptMode = .teleprompter
    var cardLimit: Int?
    /// Room the cue bar takes at the bottom while the keyboard is up.
    var keyboardOverlayHeight: CGFloat = 0
    /// Room the home controls take at the bottom once the keyboard has gone.
    var restingOverlayHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                // Set on the editor's own font and insets, so the first line sits
                // exactly where the caret waiting in front of it does.
                Text(mode == .cards
                     ? "One thought per card.\n\nWrite a few talking points, then tap Add Card for the next one.\n\nUse Add Cue for reminders like [cue pause]."
                     : "Add your script here...\n\nTap Add Cue to drop in a delivery reminder, or type [ to write one yourself.\n\nFor example: Welcome everyone [cue smile and pause]")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.top, CueTextEditor.edgeFade)
                    .allowsHitTesting(false)
            }

            CueTextEditor(
                text: $text,
                isFocused: $isFocused,
                controller: controller,
                cueColor: cueColor,
                colorScheme: colorScheme,
                fontSize: fontSize,
                mode: mode,
                cardLimit: cardLimit,
                keyboardOverlayHeight: keyboardOverlayHeight,
                restingOverlayHeight: restingOverlayHeight
            )
            .padding(.horizontal, 4)
        }
        // Lines arrive and leave through a fade instead of being cut off against
        // the toolbar above and the controls below.
        .scriptEdgeFade(for: colorScheme, top: CueTextEditor.edgeFade, bottom: Self.bottomFade)
    }

    /// The bottom fade reaches up past the floating controls, so a line is gone
    /// before it can pass behind them.
    private static let bottomFade: CGFloat = 72
}

/// View for displaying and managing saved notes
struct SavedNotesView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var noteToRename: SavedNote?
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
            }
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
