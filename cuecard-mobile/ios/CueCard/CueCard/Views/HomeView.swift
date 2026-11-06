import SwiftUI
import StoreKit
import PhotosUI
import FirebaseAnalytics
import FirebaseCrashlytics

/// The editor, opened from the library on one script: written in its mode,
/// played from here, and saved back to the library.
struct HomeView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingTeleprompter = false
    @State private var showingCards = false
    /// The cards showing were opened from the watch, not from the editor.
    @State private var cardsOpenedOnWatch = false
    @State private var showingTimer = false
    @State private var showingVersions = false
    @State private var showingTakes = false
    @State private var showingSaveDialog = false
    @State private var saveNoteTitle = ""
    @State private var showingSaveAsNew = false
    @State private var saveAsNewTitle = ""
    @State private var showingRename = false
    @State private var renameTitle = ""
    @State private var showingImagePicker = false
    @State private var pickedImages: [PhotosPickerItem] = []
    /// Brief confirmation after the Save action, in the status at the bottom.
    @State private var showsSaved = false
    @State private var savedTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isEditorFocused = false
    @StateObject private var editorController = CueEditorController()
    /// Suggestions from the on-device model, while they're open.
    @StateObject private var review = ScriptReview()
    /// Why Suggestions can't help yet, once its button has been tapped.
    @State private var suggestionsUnavailable: String?
    /// Measured so every line stays clear of the controls, including larger text.
    @State private var bottomControlsHeight: CGFloat = 128
    /// The strip at the bottom edge, home indicator and all, where the
    /// script's status sits below the controls.
    @State private var bottomEdgeHeight: CGFloat = 0
    /// A use of a beta AI feature to ask the reader about.
    @State private var aiExperience: AIExperience?
    /// AI Suggestions turned on in Settings, watched so it goes as soon as
    /// it's turned off.
    @AppStorage(AppleIntelligenceSetting.suggestionsKey) private var isSuggestionsEnabled = true
    @ObservedObject private var cardsSession = CueCardsSession.shared
    @StateObject private var takes = TakesLibrary()
    @Namespace private var takesTransition
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// How far the editor reaches up under the top bar: to its middle, so the
    /// script fades out from there down, as gently as it does at the bottom.
    private static let editorTopOverlap: CGFloat = 22

    private var hasNotes: Bool {
        !settingsService.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCardsMode: Bool { settingsService.settings.scriptMode == .cards }

    /// The open note has older versions to go back to.
    private var hasVersionHistory: Bool {
        guard let id = settingsService.currentNoteId else { return false }
        return (settingsService.versionCounts[id] ?? 1) > 1
    }

    /// The script's title, or what it is while it has none, beside the back
    /// button. A saved one opens to be renamed.
    private var titleControl: some View {
        let mode = settingsService.settings.scriptMode
        let note = settingsService.currentNote
        let title = note?.title
            ?? (mode == .cards ? String(localized: "New Deck") : String(localized: "New Script"))

        return Button {
            guard let note else { return }
            AnalyticsEvents.logButtonClick("rename_note", screen: "home")
            isEditorFocused = false
            renameTitle = note.title
            showingRename = true
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(note == nil)
        .accessibilityLabel(title)
        .accessibilityHint(note == nil ? "" : String(localized: "Renames the script"))
    }

    private func showCardsOpenedOnWatch() {
        guard scenePhase == .active, !cardsSession.cards.isEmpty, !showingCards,
              !showingTeleprompter, !showingSettings, !showingHelp,
              !showingTimer, !showingTakes else { return }
        cardsOpenedOnWatch = true
        showingCards = true
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

    /// The timer's length, or that none is set, with its clock drawn in the
    /// color it starts in. Opens the timer sheet.
    @ViewBuilder
    private var timerControl: some View {
        if hasNotes {
            let settings = settingsService.settings
            let duration = settings.activeTimerMinutes * 60 + settings.activeTimerSeconds
            Button {
                AnalyticsEvents.logButtonClick("set_timer", screen: "home")
                isEditorFocused = false
                showingTimer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(duration > 0
                            ? settings.activeTimerStyle.normalColor.color(for: colorScheme)
                            : AppColors.textSecondary(for: colorScheme))
                    Text(duration > 0 ? TimerSheet.format(duration) : "No Timer")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .fixedSize(horizontal: true, vertical: false)
                .glassedEffect(in: Capsule())
                .shadow(color: Color.black.opacity(0.1), radius: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(duration > 0 ? "Timer, \(TimerSheet.format(duration))" : "Timer, not set")
        } else {
            Button(action: {
                AnalyticsEvents.logButtonClick("add_sample_text", screen: "home")
                settingsService.addSampleText()
            }) {
                Text("Add Sample Text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .glassedEffect(in: Capsule())
            }
        }
    }

    /// Back from the teleprompter: anything recorded while it was open is a
    /// take now. After Follow My Voice, the reader is asked how it went —
    /// in place of the review prompt, so it's one question at a time.
    private func teleprompterDidClose() {
        takes.reload()
        if let metrics = VoiceFeedback.shared.pending {
            VoiceFeedback.shared.pending = nil
            aiExperience = .voice(metrics)
        } else {
            requestReviewIfEarned()
        }
    }

    /// Back from the cards: anything recorded is a take now.
    private func cardsDidClose() {
        takes.reload()
    }

    /// Suggestions from Apple's on-device model, for a script being written for
    /// the teleprompter. Not shown where this iPhone has no model to ask, or
    /// AI Suggestions is turned off in Settings.
    private var showsSuggestions: Bool {
        hasNotes && isSuggestionsEnabled && OnDeviceModelAvailability.forSuggestions != .unsupported
    }

    @ViewBuilder
    private var suggestionsControl: some View {
        let availability = OnDeviceModelAvailability.forSuggestions
        if showsSuggestions {
            SuggestionsButton(colorScheme: colorScheme) {
                AnalyticsEvents.logButtonClick("suggestions", screen: "home")
                isEditorFocused = false
                if case .unavailable(let reason) = availability {
                    suggestionsUnavailable = reason
                } else if isCardsMode {
                    startDeckReview()
                } else {
                    review.start(script: settingsService.notes)
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Review the deck as the cards editor writes it, so where each card
    /// starts in the script is where the editor puts it. A deck written
    /// some other way — imported, say — is brought to that form first;
    /// its cards stay the same.
    private func startDeckReview() {
        let deck = CueCards.script(for: CueCards.editableCards(in: settingsService.notes))
        if deck != settingsService.notes { settingsService.notes = deck }
        review.start(script: deck, cardLimit: settingsService.settings.cards.characterLimit)
    }

    /// Put an accepted suggestion into the script, through the editor so it
    /// stays where it's scrolled to. A deck's editor is a card at a time,
    /// so a deck's script is changed itself, and its cards follow.
    private func applySuggestion(_ edit: (range: NSRange, replacement: String)) {
        guard isCardsMode || !editorController.replace(edit.range, with: edit.replacement) else { return }
        settingsService.notes = (settingsService.notes as NSString)
            .replacingCharacters(in: edit.range, with: edit.replacement)
    }

    /// The suggestions being reviewed, for the editor to mark.
    private var suggestionMarks: SuggestionMarks? {
        guard review.isActive else { return nil }
        return SuggestionMarks(
            ranges: review.suggestions.map(\.mark),
            focused: review.focused?.mark,
            onTap: { review.focus(at: $0) }
        )
    }

    /// The videos recorded while the teleprompter or cards were open on the script. Once
    /// it has been, and before Photos can be read, a button to go find them.
    @ViewBuilder
    private var takesControl: some View {
        if hasTakes {
            Button {
                AnalyticsEvents.logButtonClick("takes", screen: "home")
                isEditorFocused = false
                showingTakes = true
            } label: {
                TakesIcon(count: takes.takes.count, colorScheme: colorScheme, transition: takesTransition)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Save to the open note, or ask for a title if the script isn't one yet.
    /// `button` says which of the save buttons was used.
    private func save(from button: String) {
        AnalyticsEvents.logButtonClick(button, screen: "home")
        if settingsService.currentNoteId != nil {
            if settingsService.saveChangesToCurrentNote() {
                flashSaved()
            } else {
                errorMessage = String(localized: "Your note couldn't be saved. Try again.")
            }
        } else {
            saveNoteTitle = ""
            showingSaveDialog = true
        }
    }

    private func flashSaved() {
        showsSaved = true
        savedTask?.cancel()
        savedTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            showsSaved = false
        }
    }

    /// Keep what's written as a script of its own, named to start with after
    /// the one open, which stays as it was last saved.
    private func beginSaveAsNew() {
        AnalyticsEvents.logButtonClick("save_as_new_menu", screen: "home")
        isEditorFocused = false
        saveAsNewTitle = settingsService.currentNote.map {
            String(localized: "\($0.title) Copy", comment: "Title of a duplicated script")
        } ?? ""
        showingSaveAsNew = true
    }

    /// Whether the script has changes to save, and the saved one's version,
    /// in small text at the bottom edge, below the controls, so they don't
    /// move up for it. "Saved" for a moment after saving. The version opens
    /// its history.
    @ViewBuilder
    private var statusFooter: some View {
        let isUnsaved = settingsService.hasUnsavedChanges
        let state: String? = isUnsaved ? String(localized: "Unsaved")
            : showsSaved ? String(localized: "Saved") : nil
        let version = settingsService.currentNoteId.map {
            String(localized: "Version \(settingsService.versionCounts[$0] ?? 1)")
        }
        let text = [state, version].compactMap { $0 }.joined(separator: " · ")
        if !text.isEmpty {
            Button {
                AnalyticsEvents.logButtonClick("version_history_footer", screen: "home")
                isEditorFocused = false
                showingVersions = true
            } label: {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(version == nil)
            .accessibilityHint(version == nil ? "" : String(localized: "Opens Version History"))
            .animation(.easeInOut(duration: 0.2), value: text)
        }
    }

    /// Save, at the bottom beside AI Suggestions, or the timer without it,
    /// while there are changes to save.
    @ViewBuilder
    private var saveButton: some View {
        if settingsService.hasUnsavedChanges {
            Button {
                isEditorFocused = false
                save(from: "save_note_bottom")
            } label: {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .fixedSize(horizontal: true, vertical: false)
                    .glassedEffect(in: Capsule(), interactive: true)
                    .shadow(color: Color.black.opacity(0.1), radius: 10)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Saves your changes")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Drop a `[cue]` in at the caret with its text selected, so the user can
    /// type the cue over it without hunting for their place.
    private func insertCue() {
        AnalyticsEvents.logButtonClick("insert_cue", screen: "home")
        editorController.insertCue()
    }

    /// Mark the caret's spot as an anchor the teleprompter can jump to.
    private func insertAnchor() {
        AnalyticsEvents.logButtonClick("insert_anchor", screen: "home")
        editorController.insertAnchor()
    }

    /// Bold or italicize the selection, or the word at the caret.
    private func format(_ style: EmphasisStyle) {
        AnalyticsEvents.logButtonClick(style == .bold ? "format_bold" : "format_italic", screen: "home")
        editorController.toggle(style)
    }

    /// Keep the images picked from the library and place them at the caret.
    private func addPickedImages() {
        let items = pickedImages
        guard !items.isEmpty else { return }
        pickedImages = []
        editorController.beginAddingImages()
        Task {
            var names: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let name = await Task.detached(operation: { ScriptImages.add(data) }).value else { continue }
                names.append(name)
            }
            if names.count < items.count {
                errorMessage = String(localized: "An image couldn't be added. Try again.")
            }
            editorController.insertImages(names)
        }
    }

    /// What floats over the bottom of the script: the cue bar while writing,
    /// the suggestions while they're open, the timer and Play otherwise.
    @ViewBuilder
    private var bottomControls: some View {
        if isEditorFocused {
            CueBar(
                colorScheme: colorScheme,
                onAddCue: insertCue,
                // Anchors are for jumping through the teleprompter;
                // cards are turned one at a time.
                onAddAnchor: isCardsMode ? nil : insertAnchor,
                onAddImage: {
                    AnalyticsEvents.logButtonClick("insert_image", screen: "home")
                    showingImagePicker = true
                },
                onFormat: format,
                onDismissKeyboard: {
                    AnalyticsEvents.logButtonClick("hide_keyboard", screen: "home")
                    isEditorFocused = false
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if review.isActive {
            SuggestionsPanel(
                review: review,
                colorScheme: colorScheme,
                cueColor: settingsService.settings.activeCueColor,
                onAccept: { suggestion in
                    if let edit = review.accept(suggestion.id) { applySuggestion(edit) }
                },
                onAcceptAll: {
                    review.acceptAll().forEach(applySuggestion)
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                if hasNotes && !showsSuggestions {
                    // Without AI Suggestions, the timer has the left to itself,
                    // and Takes and Play are on the right.
                    HStack(spacing: 12) {
                        timerControl
                        saveButton
                        Spacer(minLength: 0)
                        takesControl
                        startButton
                    }
                } else if hasNotes {
                    // AI Suggestions on the left; Takes, the timer and Play on
                    // the right, the timer beside Play. With no room for them
                    // on one line, Takes stacks over the timer.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            suggestionsControl
                            saveButton
                            Spacer(minLength: 0)
                            takesControl
                            timerControl
                            startButton
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 12) {
                                saveButton
                                suggestionsControl
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 12) {
                                takesControl
                                timerControl
                            }
                            startButton
                        }
                    }
                } else {
                    timerControl
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            // Where there's no strip at the bottom edge for the status, room
            // is left for it here.
            .padding(.bottom, bottomEdgeHeight < 20 ? 30 : 12)
        }
    }

    private var hasTakes: Bool {
        !takes.takes.isEmpty || (takes.hasSessions && (takes.status == .notDetermined || takes.status == .limited))
    }

    private var startButton: some View {
        Button {
            isEditorFocused = false
            if isCardsMode {
                AnalyticsEvents.logButtonClick("start_cards", screen: "home")
                cardsOpenedOnWatch = false
                showingCards = true
            } else {
                AnalyticsEvents.logButtonClick("start_teleprompter", screen: "home")
                showingTeleprompter = true
            }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(AppColors.green(for: colorScheme)))
                .glassedEffect(in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isCardsMode ? CueCards.cards(in: settingsService.notes).isEmpty : !hasNotes)
        .opacity(hasNotes ? 1 : 0.4)
        .accessibilityLabel(isCardsMode ? "Open Cards" : "Start Teleprompter")
    }

    var body: some View {
        handlingSuggestions(home)
            .sheet(isPresented: Binding(
                get: { aiExperience != nil },
                set: { if !$0 { aiExperience = nil } }
            )) {
                if let aiExperience {
                    AIFeedbackSheet(experience: aiExperience)
                }
            }
    }

    /// What the suggestions need from the screen around them, kept apart from
    /// the rest of it, which is already as much as the compiler takes at once.
    private func handlingSuggestions(_ content: some View) -> some View {
        content
            .animation(.easeInOut(duration: 0.25), value: review.isActive)
            // Anything but an accepted suggestion changing the script — another
            // note opened — leaves the suggestions pointing at the wrong words.
            .onChange(of: settingsService.notes) {
                review.scriptDidChange(to: settingsService.notes)
            }
            .onChange(of: isCardsMode) {
                review.end()
            }
            .onChange(of: isSuggestionsEnabled) {
                if !isSuggestionsEnabled { review.end() }
            }
            // A review seen through: ask how it went.
            .onChange(of: review.finished) {
                guard let finished = review.finished else { return }
                review.finished = nil
                aiExperience = .suggestions(finished)
            }
            .alert("AI Suggestions", isPresented: Binding(
                get: { suggestionsUnavailable != nil || review.errorMessage != nil },
                set: { if !$0 { suggestionsUnavailable = nil; review.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    AnalyticsEvents.logButtonClick("suggestions_alert_ok", screen: "home")
                }
            } message: {
                Text(suggestionsUnavailable ?? review.errorMessage ?? "")
            }
    }

    private var home: some View {
        ZStack {
            // Background - matches TeleprompterView
            AppColors.background(for: colorScheme)
                .ignoresSafeArea()

            Group {
                if isCardsMode {
                    CardsEditorView(
                        text: $settingsService.notes,
                        isFocused: $isEditorFocused,
                        controller: editorController,
                        cueColor: settingsService.settings.cards.cueColor,
                        colorScheme: colorScheme,
                        fontSize: CGFloat(settingsService.settings.cards.editorFontSize),
                        cardLimit: settingsService.settings.cards.characterLimit,
                        bottomInset: isEditorFocused ? CueBar.height
                            : bottomControlsHeight,
                        topOverlap: Self.editorTopOverlap,
                        suggestionMarks: suggestionMarks
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
                        restingOverlayHeight: bottomControlsHeight,
                        topOverlap: Self.editorTopOverlap,
                        suggestionMarks: suggestionMarks
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The editor makes its own room for the keyboard, as scroll
                    // inset. SwiftUI's avoidance would resize it instead, and the
                    // gap it leaves behind on dismissal cuts the script off.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
        }
        .overlay(alignment: .bottom) {
            bottomControls
                .frame(maxWidth: 680)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if !isEditorFocused { bottomControlsHeight = height }
                }
        }
        .overlay(alignment: .bottom) {
            if !isEditorFocused && !review.isActive {
                statusFooter
                    .frame(height: max(bottomEdgeHeight, 24), alignment: .top)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.opacity)
            }
        }
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { height in
                    bottomEdgeHeight = height
                }
        }
        .animation(.easeInOut(duration: 0.2), value: settingsService.hasUnsavedChanges)
        .animation(.easeInOut(duration: 0.2), value: isEditorFocused)
        .navigationBarTitleDisplayMode(.inline)
        // No bar background: the script's fade shows through its lower half.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbar }
        .helpSheet(for: .writing(settingsService.settings.scriptMode), isPresented: $showingHelp)
        .sheet(isPresented: $showingSettings) {
            EditorSettingsView()
        }
        .sheet(isPresented: $showingVersions) {
            if let id = settingsService.currentNoteId {
                NoteVersionsView(noteID: id)
            }
        }
        .sheet(isPresented: $showingTimer) {
            TimerSheet()
        }
        .sheet(isPresented: $showingTakes) {
            TakesView(library: takes, scriptTitle: settingsService.currentNote?.title)
                .zoomsFromTakes(in: takesTransition)
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $pickedImages,
                      maxSelectionCount: 10, matching: .images)
        .onChange(of: pickedImages) {
            addPickedImages()
        }
        .modifier(EditorAlerts(editor: self))
        .fullScreenCover(isPresented: $showingTeleprompter, onDismiss: teleprompterDidClose) {
            TeleprompterView(content: TeleprompterParser.parseNotes(settingsService.notes))
                // Passed on by hand: as an iPad app on a Mac, a full screen
                // cover doesn't inherit environment objects.
                .environmentObject(settingsService)
        }
        .fullScreenCover(isPresented: $showingCards, onDismiss: cardsDidClose) {
            CueCardsView(cards: cardsOpenedOnWatch ? nil : CueCards.cards(in: settingsService.notes),
                         title: cardsOpenedOnWatch ? cardsSession.title
                            : settingsService.currentNote?.title ?? String(localized: "Cards"),
                         deckID: cardsOpenedOnWatch ? cardsSession.deckID : settingsService.currentNoteId)
                .environmentObject(settingsService)
        }
        // A deck opened from the watch comes up here too, if nothing else is.
        .onChange(of: cardsSession.sessionID) {
            showCardsOpenedOnWatch()
        }
        .onChange(of: scenePhase) {
            showCardsOpenedOnWatch()
            if scenePhase == .active { takes.reload() }
        }
        .onChange(of: settingsService.currentScriptID) {
            takes.load(scriptID: settingsService.currentScriptID)
        }
        .onAppear {
            takes.load(scriptID: settingsService.currentScriptID)
            showCardsOpenedOnWatch()
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "home",
                AnalyticsParameterScreenClass: "HomeView"
            ])
        }
    }

    /// Let the navigation bar fit the title between navigation and actions.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            titleControl
        }
        .sharedBackgroundHidden()

        // One item, so the gear and ••• sit closer than separate items'
        // buttons do.
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                Button(action: {
                    AnalyticsEvents.logButtonClick("settings", screen: "home")
                    isEditorFocused = false
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        .frame(width: 34, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")

                Menu {
                    Button {
                        save(from: "save_note_menu")
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!settingsService.hasUnsavedChanges)
                    // With no saved script open, Save asks for a title already.
                    if settingsService.currentNoteId != nil {
                        Button(action: beginSaveAsNew) {
                            Label("Save as New", systemImage: "plus.square.on.square")
                        }
                        .disabled(!hasNotes)
                    }
                    if hasVersionHistory {
                        Button {
                            AnalyticsEvents.logButtonClick("version_history_menu", screen: "home")
                            isEditorFocused = false
                            showingVersions = true
                        } label: {
                            Label("Version History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        .frame(width: 34, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Script Options")
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsEvents.logButtonClick("editor_menu", screen: "home")
                })
            }
        }

        HelpToolbarItem(page: .writing(settingsService.settings.scriptMode), isPresented: $showingHelp)
    }

    /// The editor's alerts, kept apart from the rest of it, which is already
    /// as much as the compiler takes at once.
    private struct EditorAlerts: ViewModifier {
        let editor: HomeView

        private var settingsService: SettingsService { editor.settingsService }

        func body(content: Content) -> some View {
            content
                .alert("Something Went Wrong", isPresented: Binding(
                    get: { editor.errorMessage != nil },
                    set: { if !$0 { editor.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {
                        AnalyticsEvents.logButtonClick("editor_error_ok", screen: "home")
                        editor.errorMessage = nil
                    }
                } message: {
                    Text(editor.errorMessage ?? "")
                }
                .alert("Save Note", isPresented: editor.$showingSaveDialog) {
                    TextField("Note title", text: editor.$saveNoteTitle)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("save_dialog_cancel", screen: "home")
                    }
                    Button("Save") {
                        AnalyticsEvents.logButtonClick("save_dialog_save", screen: "home")
                        let title = editor.saveNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty {
                            if settingsService.saveCurrentNote(title: title) {
                                editor.flashSaved()
                            } else {
                                editor.errorMessage = String(localized: "Your note couldn't be saved. Try again.")
                            }
                        }
                    }
                } message: {
                    Text("Enter a title for your note")
                }
                .alert("Save as New", isPresented: editor.$showingSaveAsNew) {
                    TextField("Note title", text: editor.$saveAsNewTitle)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("save_as_new_cancel", screen: "home")
                    }
                    Button("Save") {
                        AnalyticsEvents.logButtonClick("save_as_new_save", screen: "home")
                        let title = editor.saveAsNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty {
                            if settingsService.saveCurrentNoteAsNew(title: title) {
                                editor.flashSaved()
                            } else {
                                editor.errorMessage = String(localized: "Your note couldn't be saved. Try again.")
                            }
                        }
                    }
                } message: {
                    Text("Your changes go in a new script. “\(settingsService.currentNote?.title ?? "")” stays as it was last saved.")
                }
                .alert("Rename Script", isPresented: editor.$showingRename) {
                    TextField("Title", text: editor.$renameTitle)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("rename_dialog_cancel", screen: "home")
                    }
                    Button("Rename") {
                        AnalyticsEvents.logButtonClick("rename_dialog_save", screen: "home")
                        let title = editor.renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let id = settingsService.currentNoteId, !title.isEmpty,
                           !settingsService.updateNote(id: id, title: title) {
                            editor.errorMessage = String(localized: "The note couldn't be renamed. Try again.")
                        }
                    }
                }
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
    /// Suggestions being reviewed, marked in the script.
    var suggestionMarks: SuggestionMarks?

    private var topFade: CGFloat { CueTextEditor.edgeFade + topOverlap }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                // Set on the editor's own font and insets, so the first line sits
                // exactly where the caret waiting in front of it does.
                Text("Add your script here...\n\nTap Cue to drop in a delivery reminder, or type [ to write one yourself.\n\nFor example: Welcome everyone [smile and pause]")
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
                topInset: topFade,
                suggestionMarks: suggestionMarks
            )
            .padding(.horizontal, 4)
        }
        // Lines arrive and leave through a fade instead of being cut off against
        // the toolbar above and the controls below.
        .scriptEdgeFade(for: colorScheme, top: topFade,
                        bottom: isFocused ? Self.bottomFade : max(Self.bottomFade, restingOverlayHeight))
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
    /// Suggestions being reviewed, marked in the cards they're on. The deck
    /// can't be changed meanwhile, other than by taking one.
    var suggestionMarks: SuggestionMarks?

    private var isReviewing: Bool { suggestionMarks != nil }

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
                    cardRow(card, number: index + 1, marks: marks(forCardAt: index))
                        .id(card.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isReviewing {
                                Button(role: .destructive) {
                                    AnalyticsEvents.logButtonClick("remove_card", screen: "home")
                                    remove(card.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
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
                .disabled(isReviewing)
                .opacity(isReviewing ? 0.4 : 1)
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
            // The card with the suggestion being looked at comes into view.
            .onChange(of: suggestionMarks?.focused) {
                guard let focused = suggestionMarks?.focused,
                      let index = cardStarts.lastIndex(where: { $0 <= focused.location }),
                      cards.indices.contains(index) else { return }
                withAnimation { proxy.scrollTo(cards[index].id, anchor: .center) }
            }
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

    /// Where each card starts in the script the editor writes.
    private var cardStarts: [Int] {
        let separator = ("\n\(CueCards.separatorTag)\n" as NSString).length
        var starts: [Int] = []
        var location = 0
        for card in cards {
            starts.append(location)
            location += (card.text as NSString).length + separator
        }
        return starts
    }

    /// The suggestions on one card, moved from where they are in the script
    /// to where they are in the card. Every card gets marks while reviewing,
    /// none or some, so none can be typed in.
    private func marks(forCardAt index: Int) -> SuggestionMarks? {
        guard let suggestionMarks else { return nil }
        let start = cardStarts[index]
        let end = start + (cards[index].text as NSString).length
        func local(_ range: NSRange) -> NSRange? {
            guard range.location >= start, NSMaxRange(range) <= end else { return nil }
            return NSRange(location: range.location - start, length: range.length)
        }
        return SuggestionMarks(
            ranges: suggestionMarks.ranges.compactMap(local),
            focused: suggestionMarks.focused.flatMap(local),
            onTap: { suggestionMarks.onTap($0 + start) }
        )
    }

    private func cardRow(_ card: EditableCard, number: Int, marks: SuggestionMarks?) -> some View {
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
                    keyboardOverlayHeight: CueBar.height,
                    suggestionMarks: marks
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
        // A tap on the card around the text still starts writing in it,
        // unless suggestions are open.
        .onTapGesture { if !isReviewing { focusedCard = card.id } }
    }

    /// The first card explains the deck. Later ones only ask for the next
    /// thought, since by then it's clear what a card is.
    private func placeholder(forCardNumber number: Int) -> String {
        number == 1
            ? String(localized: "One thought per card.\n\nType [ or tap Add Cue for reminders like [pause].",
                     comment: "Keep the brackets around [pause]; translate the word inside them.")
            : String(localized: "Your next thought…")
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

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentObject(SettingsService.shared)
}
