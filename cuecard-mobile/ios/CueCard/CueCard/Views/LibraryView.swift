import SwiftUI
import UniformTypeIdentifiers
import FirebaseAnalytics

/// Where a library screen leads.
enum LibraryRoute: Hashable {
    case folder(String)
    case editor
}

/// Where the app opens: every saved script and deck, filed in folders, with
/// the takes recorded with each. A script opens into the editor from here.
struct LibraryView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [LibraryRoute] = []
    @StateObject private var takeCounts = TakeCounts()
    @ObservedObject private var cardsSession = CueCardsSession.shared
    /// A deck opened from the watch, while the editor isn't open to show it.
    @State private var showingWatchCards = false
    /// A Follow My Voice session in that deck, to ask the reader about.
    @State private var voiceFeedback: VoiceSessionMetrics?
    /// The app went to the background since it was last opened.
    @State private var wasInBackground = false
    @AppStorage(LibraryStorageWarning.dismissedKey) private var warningDismissed = false
    @AppStorage(LibraryStorageWarning.opensKey) private var opensSinceDismissed = 0

    /// The launch's open is counted once, however often this appears.
    private static var hasCountedLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryList(folder: nil, path: $path, takeCounts: takeCounts)
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let name):
                        LibraryList(folder: name, path: $path, takeCounts: takeCounts)
                    case .editor:
                        HomeView()
                    }
                }
        }
        .fullScreenCover(isPresented: $showingWatchCards, onDismiss: watchCardsDidClose) {
            CueCardsView(cards: nil, title: cardsSession.title, deckID: cardsSession.deckID)
                // Passed on by hand: as an iPad app on a Mac, a full screen
                // cover doesn't inherit environment objects.
                .environmentObject(settingsService)
        }
        .onAppear {
            takeCounts.reload()
            showCardsOpenedOnWatch()
            if !Self.hasCountedLaunch {
                Self.hasCountedLaunch = true
                countOpen()
            }
        }
        .onChange(of: cardsSession.sessionID) {
            showCardsOpenedOnWatch()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                wasInBackground = true
            case .active:
                takeCounts.reload()
                showCardsOpenedOnWatch()
                if wasInBackground {
                    wasInBackground = false
                    countOpen()
                }
            default:
                break
            }
        }
        .sheet(isPresented: Binding(
            get: { voiceFeedback != nil },
            set: { if !$0 { voiceFeedback = nil } }
        )) {
            if let voiceFeedback {
                VoiceFeedbackSheet(metrics: voiceFeedback)
            }
        }
        // Back from the editor, there may be new takes or a new note.
        .onChange(of: path) {
            if !path.contains(.editor) { takeCounts.reload() }
        }
    }

    private func watchCardsDidClose() {
        takeCounts.reload()
        if let metrics = VoiceFeedback.shared.pending {
            VoiceFeedback.shared.pending = nil
            voiceFeedback = metrics
        }
    }

    /// The editor shows a deck opened from the watch itself, while it's open.
    private func showCardsOpenedOnWatch() {
        guard scenePhase == .active, !path.contains(.editor), !cardsSession.cards.isEmpty,
              !showingWatchCards else { return }
        showingWatchCards = true
    }

    /// A put-away warning about having no storage folder comes back every
    /// tenth time the app is opened.
    private func countOpen() {
        guard warningDismissed, !settingsService.hasNotesFolder else { return }
        opensSinceDismissed += 1
        if opensSinceDismissed >= LibraryStorageWarning.opensBetweenReminders {
            warningDismissed = false
            opensSinceDismissed = 0
        }
    }
}

/// The warning that scripts are lost with the app until there's a storage
/// folder, and when it's shown again after being put away.
enum LibraryStorageWarning {
    static let dismissedKey = "library_folder_tip_dismissed"
    static let opensKey = "library_opens_since_folder_tip_dismissed"
    static let opensBetweenReminders = 10
}

// MARK: - Sorting

private enum LibrarySort: String, CaseIterable, Identifiable {
    case edited, created, title

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .edited: return "Date Edited"
        case .created: return "Date Created"
        case .title: return "Title"
        }
    }
}

/// A script about to replace what's being written in its mode's editor.
private enum PendingOpen: Identifiable {
    case note(SavedNote)
    case new(ScriptMode)

    var mode: ScriptMode {
        switch self {
        case .note(let note): return note.mode
        case .new(let mode): return mode
        }
    }

    var id: String {
        switch self {
        case .note(let note): return note.id.uuidString
        case .new(let mode): return "new-\(mode.rawValue)"
        }
    }
}

/// The script whose takes are open.
private struct TakesTarget: Identifiable {
    let id: UUID
    let title: String
}

// MARK: - List

/// The top of the library, or one of its folders: the scripts or decks in
/// it, the drafts started in it, and at the top, the folders.
private struct LibraryList: View {
    /// The folder shown, or nil for the top of the library.
    let folder: String?
    @Binding var path: [LibraryRoute]
    @ObservedObject var takeCounts: TakeCounts

    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var notifications: RemoteNotificationService
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var watch = WatchSessionService.shared

    @AppStorage("library_sort") private var sort: LibrarySort = .edited
    @AppStorage("library_mode") private var mode: ScriptMode = .teleprompter
    @AppStorage(LibraryStorageWarning.dismissedKey) private var warningDismissed = false
    @AppStorage(LibraryStorageWarning.opensKey) private var opensSinceDismissed = 0

    @State private var query = ""
    @FocusState private var isSearching: Bool
    @State private var showingHelp = false
    @State private var showingImporter = false
    @State private var showingFolderPicker = false
    @State private var showingStopFolder = false
    @State private var showingStopFolderFailed = false
    @State private var showingDeleteAll = false
    @State private var pendingOpen: PendingOpen?
    @State private var draftToDiscard: ScriptMode?
    @State private var noteToRename: SavedNote?
    @State private var noteToDelete: SavedNote?
    @State private var renameTitle = ""
    /// A new folder is being named, and the note to file in it, if any.
    @State private var showingNewFolder = false
    @State private var noteForNewFolder: SavedNote?
    @State private var newFolderName = ""
    @State private var folderToRename: String?
    @State private var folderToDelete: String?
    @State private var folderTitle = ""
    @State private var takesTarget: TakesTarget?
    @State private var errorMessage: String?

    private static let screen = "library"
    private static let rowInsets = EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)

    private var isRoot: Bool { folder == nil }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Searching from the top looks through every folder.
    private var isSearchingAll: Bool { isRoot && !trimmedQuery.isEmpty }

    /// The saved notes shown: this folder's, or every one that matches the
    /// search from the top, of the chosen mode, in the chosen order.
    private var notes: [SavedNote] {
        let shown = settingsService.savedNotes.filter { note in
            (isSearchingAll || note.folder == folder)
                && note.mode == mode
                && matches(title: note.title, content: note.content)
        }
        switch sort {
        case .edited: return shown.sorted { $0.updatedAt > $1.updatedAt }
        case .created: return shown.sorted { $0.createdAt > $1.createdAt }
        case .title: return shown.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// A new script of the chosen mode that isn't saved yet, if it was
    /// started here.
    private var hasDraft: Bool {
        let text = settingsService.notes(for: mode)
        return settingsService.noteId(for: mode) == nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isSearchingAll || settingsService.draftFolder(for: mode) == folder)
            && matches(title: "", content: text)
    }

    private var folders: [String] {
        guard isRoot, trimmedQuery.isEmpty else { return [] }
        return settingsService.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func matches(title: String, content: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return title.localizedStandardContains(trimmedQuery)
            || LibraryText.plain(content).localizedStandardContains(trimmedQuery)
    }

    /// What the chosen mode's scripts are called.
    private var kindName: String {
        mode == .cards ? String(localized: "Decks") : String(localized: "Scripts")
    }

    var body: some View {
        List {
            if isRoot, let notification = notifications.notification(for: .homeBanner) {
                NotificationBanner(notification: notification)
                    .plainRow(insets: Self.rowInsets)
            }

            if isRoot, trimmedQuery.isEmpty, showsStorageWarning {
                LibraryStorageBanner(
                    isUnreachable: settingsService.hasNotesFolder,
                    colorScheme: colorScheme,
                    onChoose: {
                        AnalyticsEvents.logButtonClick("choose_notes_folder_banner", screen: Self.screen)
                        showingFolderPicker = true
                    },
                    onDismiss: settingsService.hasNotesFolder ? nil : {
                        AnalyticsEvents.logButtonClick("dismiss_folder_tip", screen: Self.screen)
                        withAnimation {
                            warningDismissed = true
                            opensSinceDismissed = 0
                        }
                    }
                )
                .plainRow(insets: Self.rowInsets)
            }

            if !folders.isEmpty {
                sectionLabel(String(localized: "Folders"))
                folderChips
                    .plainRow(insets: EdgeInsets(top: 2, leading: 0, bottom: 14, trailing: 0))
            }

            if hasDraft || !notes.isEmpty {
                if !folders.isEmpty {
                    sectionLabel(kindName)
                }
                if hasDraft {
                    draftRow(mode)
                }
                ForEach(notes) { note in
                    noteRow(note)
                }
            } else {
                emptyState
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .plainRow(insets: Self.rowInsets)
            }

            if isRoot, trimmedQuery.isEmpty {
                footer
                    .plainRow(insets: EdgeInsets(top: 10, leading: 24, bottom: 16, trailing: 24))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .scrollEdgeFade()
        .background(AppColors.background(for: colorScheme).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: showsStorageWarning)
        .safeAreaInset(edge: .bottom, spacing: 0) { libraryControls }
        .navigationTitle(folder ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .helpSheet(for: .library, isPresented: $showingHelp)
        .sheet(item: $takesTarget, onDismiss: takeCounts.reload) { target in
            ScriptTakesSheet(scriptID: target.id, title: target.title)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: ScriptFile.importableContentTypes) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            handleFolderPick(result)
        }
        .modifier(LibraryAlerts(list: self))
        .onAppear {
            settingsService.syncNotesFolder()
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: Self.screen,
                AnalyticsParameterScreenClass: "LibraryView"
            ])
        }
    }

    // MARK: Pieces

    /// Shown until there's a storage folder, unless put away, and whenever
    /// the folder there is can't be reached.
    private var showsStorageWarning: Bool {
        settingsService.hasNotesFolder ? settingsService.notesFolderName == nil : !warningDismissed
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            modeMenu
        }

        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }

        HelpToolbarItem(page: .library, isPresented: $showingHelp)
    }

    /// Teleprompter or cards: whose scripts the library shows. The bar shows
    /// the chosen mode's name, or in a folder, whose name needs the room, its
    /// symbol.
    private var modeMenu: some View {
        // Plain buttons rather than a picker, so the menu shows no checkmark:
        // the bar already says which mode is on.
        Menu {
            ForEach(ScriptMode.allCases) { choice in
                Button {
                    AnalyticsEvents.logButtonClick("library_mode_\(choice.rawValue)", screen: Self.screen)
                    mode = choice
                } label: {
                    Label(choice.displayName, systemImage: choice.systemImage)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isRoot {
                    Text(mode.displayName)
                        .font(.headline)
                } else {
                    Image(systemName: mode.systemImage)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .fixedSize()
        }
        .accessibilityLabel("Mode: \(mode.displayName)")
        .simultaneousGesture(TapGesture().onEnded {
            AnalyticsEvents.logButtonClick("library_mode_menu", screen: Self.screen)
        })
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            .plainRow(insets: EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
    }

    @ViewBuilder
    private var emptyState: some View {
        let secondary = AppColors.textSecondary(for: colorScheme)
        VStack(spacing: 6) {
            if !trimmedQuery.isEmpty {
                Text("No Results")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text("Nothing in your \(kindName.lowercased()) matches “\(trimmedQuery)”.")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            } else {
                Text(mode == .cards ? "No Decks Yet" : "No Scripts Yet")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text(mode == .cards
                     ? "Tap + below to start a deck of cards."
                     : "Tap + below to write a script for the teleprompter.")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var footer: some View {
        LibraryFooter(colorScheme: colorScheme)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Searching and starting a script, together at the bottom. While
    /// searching, it's only the search, above the keyboard.
    private var libraryControls: some View {
        HStack(spacing: 10) {
            searchRow
            if isSearching {
                Button("Done") {
                    AnalyticsEvents.logButtonClick("library_search_done", screen: Self.screen)
                    isSearching = false
                }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            } else {
                newButton
            }
        }
        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(AppColors.background(for: colorScheme))
    }

    private var newButton: some View {
        Button { startNew(mode) } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .frame(width: 48, height: 48)
                .background(AppColors.green(for: colorScheme), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .cards ? "New Deck" : "New Script")
    }

    private var searchRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .accessibilityHidden(true)
            TextField(searchPrompt, text: $query)
                .focused($isSearching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { isSearching = false }
                .accessibilityLabel(searchPrompt)
            if !query.isEmpty {
                Button {
                    AnalyticsEvents.logButtonClick("library_search_clear", screen: Self.screen)
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear Search")
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .glassedEffect(in: Capsule())
    }

    private var searchPrompt: String {
        folder.map { String(localized: "Search \($0)", comment: "Search a library folder") }
            ?? String(localized: "Search")
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                Picker("Sort By", selection: $sort.loggingClicks("library_sort", screen: Self.screen)) {
                    ForEach(LibrarySort.allCases) { Text($0.displayName).tag($0) }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            Button {
                AnalyticsEvents.logButtonClick("import_file", screen: Self.screen)
                showingImporter = true
            } label: {
                Label("Import File", systemImage: "arrow.down.doc")
            }
            if isRoot {
                Button {
                    AnalyticsEvents.logButtonClick("new_folder", screen: Self.screen)
                    beginNewFolder(for: nil)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            if let folder {
                Divider()


                Button {
                    AnalyticsEvents.logButtonClick("rename_folder", screen: Self.screen)
                    folderTitle = folder
                    folderToRename = folder
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    AnalyticsEvents.logButtonClick("delete_folder", screen: Self.screen)
                    folderToDelete = folder
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
            if isRoot {
                Divider()

                Button {
                    AnalyticsEvents.logButtonClick("choose_notes_folder", screen: Self.screen)
                    showingFolderPicker = true
                } label: {
                    Label(settingsService.hasNotesFolder ? "Change Storage Folder" : "Choose Storage Folder",
                          systemImage: "externaldrive.badge.plus")
                }
                if settingsService.hasNotesFolder {
                    Button {
                        AnalyticsEvents.logButtonClick("stop_notes_folder", screen: Self.screen)
                        showingStopFolder = true
                    } label: {
                        Label("Stop Using Storage Folder", systemImage: "externaldrive.badge.minus")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    AnalyticsEvents.logButtonClick("delete_all_notes", screen: Self.screen)
                    showingDeleteAll = true
                } label: {
                    Label("Delete All Scripts", systemImage: "trash")
                }
                .disabled(settingsService.savedNotes.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        }
        .accessibilityLabel("Library Options")
        .simultaneousGesture(TapGesture().onEnded {
            AnalyticsEvents.logButtonClick("library_menu", screen: Self.screen)
        })
    }

    private func beginNewFolder(for note: SavedNote?) {
        noteForNewFolder = note
        newFolderName = ""
        showingNewFolder = true
    }

    // MARK: Rows

    /// The folders side by side, scrolling sideways, with one to make another.
    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(folders, id: \.self) { name in
                    folderChip(name)
                }
                Button {
                    AnalyticsEvents.logButtonClick("new_folder_chip", screen: Self.screen)
                    beginNewFolder(for: nil)
                } label: {
                    Text("New Folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .overlay(
                            Capsule().stroke(AppColors.textSecondary(for: colorScheme).opacity(0.4),
                                             style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollEdgeFade(axis: .horizontal, length: 20, insetContent: false)
    }

    private func folderChip(_ name: String) -> some View {
        let count = settingsService.savedNotes.filter { $0.folder == name && $0.mode == mode }.count
        return Button {
            AnalyticsEvents.logButtonClick("open_folder", screen: Self.screen)
            path.append(.folder(name))
        } label: {
            HStack(spacing: 8) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassedEffect(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                AnalyticsEvents.logButtonClick("rename_folder_chip", screen: Self.screen)
                folderTitle = name
                folderToRename = name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                AnalyticsEvents.logButtonClick("delete_folder_chip", screen: Self.screen)
                folderToDelete = name
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(name), \(count)")
        .accessibilityHint("Opens the folder")
    }

    private func draftRow(_ mode: ScriptMode) -> some View {
        let scriptID = mode == .cards ? settingsService.cardsScriptID : settingsService.teleprompterScriptID
        let title = mode == .cards ? String(localized: "New Deck") : String(localized: "New Script")
        return LibraryScriptRow(
            title: title,
            preview: LibraryText.preview(of: settingsService.notes(for: mode)),
            detail: String(localized: "Not saved yet"),
            badge: String(localized: "Draft"),
            takes: takeCounts.count(for: scriptID),
            colorScheme: colorScheme,
            onTakes: {
                AnalyticsEvents.logButtonClick("library_takes_draft", screen: Self.screen)
                takesTarget = TakesTarget(id: scriptID, title: title)
            }
        )
        .onTapGesture {
            AnalyticsEvents.logButtonClick("open_draft", screen: Self.screen)
            openDraft(mode)
        }
        .plainRow(insets: Self.rowInsets)
        .contextMenu {
            Button {
                AnalyticsEvents.logButtonClick("open_draft_menu", screen: Self.screen)
                openDraft(mode)
            } label: {
                Label("Keep Writing", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                AnalyticsEvents.logButtonClick("discard_draft_menu", screen: Self.screen)
                draftToDiscard = mode
            } label: {
                Label("Discard", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                AnalyticsEvents.logButtonClick("discard_draft_swipe", screen: Self.screen)
                draftToDiscard = mode
            } label: {
                Label("Discard", systemImage: "trash")
            }
            .tint(AppColors.red(for: colorScheme))
        }
    }

    private func noteRow(_ note: SavedNote) -> some View {
        let isOpen = settingsService.noteId(for: note.mode) == note.id
        return LibraryScriptRow(
            title: note.title,
            preview: LibraryText.preview(of: note.content),
            detail: detail(of: note),
            badge: isOpen && settingsService.hasUnsavedChanges(in: note.mode) ? String(localized: "Unsaved") : nil,
            takes: takeCounts.count(for: note.id),
            colorScheme: colorScheme,
            onTakes: {
                AnalyticsEvents.logButtonClick("library_takes_note", screen: Self.screen)
                takesTarget = TakesTarget(id: note.id, title: note.title)
            }
        )
        .onTapGesture { open(note) }
        .plainRow(insets: Self.rowInsets)
        .contextMenu { noteMenu(note) }
        .swipeActions(edge: .trailing) {
            Button {
                AnalyticsEvents.logButtonClick("delete_note_swipe", screen: Self.screen)
                noteToDelete = note
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(AppColors.red(for: colorScheme))
        }
        .swipeActions(edge: .leading) {
            Button {
                AnalyticsEvents.logButtonClick("rename_note_swipe", screen: Self.screen)
                renameTitle = note.title
                noteToRename = note
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
            Button {
                duplicate(note, from: "duplicate_note")
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(AppColors.blue(for: colorScheme))
        }
    }

    @ViewBuilder
    private func noteMenu(_ note: SavedNote) -> some View {
        Button {
            open(note, from: "load_note_menu")
        } label: {
            Label("Open", systemImage: "square.and.pencil")
        }

        Button {
            AnalyticsEvents.logButtonClick("rename_note_menu", screen: Self.screen)
            renameTitle = note.title
            noteToRename = note
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            duplicate(note, from: "duplicate_note_menu")
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Menu {
            Picker("Move to Folder", selection: Binding(
                get: { note.folder },
                set: { move(note, to: $0) }
            )) {
                Text("None").tag(String?.none)
                ForEach(settingsService.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                        id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .pickerStyle(.inline)

            Button {
                AnalyticsEvents.logButtonClick("new_folder_move", screen: Self.screen)
                beginNewFolder(for: note)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }

        ScriptShareLink(title: note.title, content: note.content)

        if watch.isWatchAppInstalled {
            let isOnWatch = settingsService.watchNoteIDs.contains(note.id)
            Button {
                AnalyticsEvents.logButtonClick(isOnWatch ? "watch_remove_note" : "watch_add_note", screen: Self.screen)
                settingsService.setOnWatch(!isOnWatch, noteID: note.id)
            } label: {
                Label(isOnWatch ? "Remove from Apple Watch" : "Keep on Apple Watch",
                      systemImage: isOnWatch ? "applewatch.slash" : "applewatch")
            }
        }

        Divider()

        Button(role: .destructive) {
            AnalyticsEvents.logButtonClick("delete_note_menu", screen: Self.screen)
            noteToDelete = note
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// When it was last edited, how many cards a deck has, whether it's on
    /// the watch, and, in search results from every folder, its folder.
    private func detail(of note: SavedNote) -> String {
        var parts = [LibraryText.date(note.updatedAt)]
        if note.mode == .cards {
            let count = CueCards.cards(in: note.content).count
            parts.append(String(localized: "\(count) cards", comment: "How many cards a deck has"))
        }
        if settingsService.watchNoteIDs.contains(note.id) {
            parts.append(String(localized: "On Apple Watch"))
        }
        if isSearchingAll, let folder = note.folder {
            parts.append(folder)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    /// Open a saved note in the editor. One already open there keeps what's
    /// being written in it; any other replaces its mode's script, once the
    /// user agrees to lose what isn't saved.
    private func open(_ note: SavedNote, from button: String = "load_note") {
        AnalyticsEvents.logButtonClick(button, screen: Self.screen)
        if settingsService.noteId(for: note.mode) == note.id {
            openDraft(note.mode)
        } else if settingsService.hasUnsavedChanges(in: note.mode) {
            pendingOpen = .note(note)
        } else {
            proceed(with: .note(note))
        }
    }

    /// Back to what's being written in `mode`, as it was left.
    private func openDraft(_ mode: ScriptMode) {
        settingsService.settings.scriptMode = mode
        path.append(.editor)
    }

    private func startNew(_ mode: ScriptMode) {
        AnalyticsEvents.logButtonClick(mode == .cards ? "new_deck" : "new_script", screen: Self.screen)
        if settingsService.hasUnsavedChanges(in: mode) {
            pendingOpen = .new(mode)
        } else {
            proceed(with: .new(mode))
        }
    }

    fileprivate func proceed(with pending: PendingOpen) {
        switch pending {
        case .note(let note):
            settingsService.loadNote(note)
        case .new(let mode):
            settingsService.createNewNote(mode: mode, in: folder)
        }
        path.append(.editor)
    }

    private func duplicate(_ note: SavedNote, from button: String) {
        AnalyticsEvents.logButtonClick(button, screen: Self.screen)
        if settingsService.duplicateNote(id: note.id) == nil {
            errorMessage = String(localized: "The script couldn't be duplicated. Try again.")
        }
    }

    private func move(_ note: SavedNote, to folder: String?, from button: String = "move_note") {
        AnalyticsEvents.logButtonClick(button, screen: Self.screen)
        if !settingsService.moveNote(id: note.id, toFolder: folder) {
            errorMessage = String(localized: "The script couldn't be moved. Try again.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let text = try ScriptFile.readText(from: url)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = String(localized: "That file is empty.")
                    return
                }
                let content = TeleprompterParser.normalizingTags(in: text)
                if settingsService.importNote(title: ScriptFile.title(for: url), content: content, folder: folder) == nil {
                    errorMessage = String(localized: "The file couldn't be saved as a script. Try again.")
                }
            } catch let error as ScriptFile.FileTooLarge {
                errorMessage = TextPack.isPackage(url)
                    ? String(localized: "That file is larger than 100 MB, so it can't be imported.")
                    : String(localized: "That file is larger than 10 MB, so it can't be imported.")
                Analytics.logEvent("file_too_large", parameters: [
                    "source": "import",
                    "size_mb": error.size / (1024 * 1024)
                ])
            } catch {
                errorMessage = String(localized: "This file couldn't be read as text.")
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleFolderPick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try settingsService.chooseNotesFolder(url)
            } catch {
                errorMessage = String(localized: "This folder can't be used for your scripts.")
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Why deleting scripts left files behind in the storage folder.
    fileprivate func undeletedFilesMessage(count: Int) -> String {
        if let folder = settingsService.notesFolderName {
            return count == 1
                ? String(localized: "Its file in “\(folder)” folder couldn't be deleted. CueCard will try again, and won't bring it back as notes.")
                : String(localized: "Their files in “\(folder)” folder couldn't be deleted. CueCard will try again, and won't bring them back as notes.")
        }
        return count == 1
            ? String(localized: "Its file will be deleted from the notes folder once it can be reached.")
            : String(localized: "Their files will be deleted from the notes folder once it can be reached.")
    }

    // MARK: Alerts

    /// Every alert the library asks with, kept apart from the list, which is
    /// already as much as the compiler takes at once.
    private struct LibraryAlerts: ViewModifier {
        let list: LibraryList

        func body(content: Content) -> some View {
            content
                .modifier(NoteAlerts(list: list))
                .modifier(FolderAlerts(list: list))
                .modifier(StorageAlerts(list: list))
        }
    }

    private struct NoteAlerts: ViewModifier {
        let list: LibraryList

        private var settingsService: SettingsService { list.settingsService }

        func body(content: Content) -> some View {
            content
                .alert("Unsaved Changes", isPresented: Binding(
                    get: { list.pendingOpen != nil },
                    set: { if !$0 { list.pendingOpen = nil } }
                ), presenting: list.pendingOpen) { pending in
                    if settingsService.noteId(for: pending.mode) != nil {
                        Button("Save and Continue") {
                            AnalyticsEvents.logButtonClick("unsaved_save_continue", screen: LibraryList.screen)
                            if settingsService.saveChanges(in: pending.mode) {
                                list.proceed(with: pending)
                            } else {
                                list.errorMessage = String(localized: "Your note couldn't be saved. Try again.")
                            }
                        }
                    }
                    Button("Keep Editing") {
                        AnalyticsEvents.logButtonClick("unsaved_keep_editing", screen: LibraryList.screen)
                        list.openDraft(pending.mode)
                    }
                    Button("Discard Changes", role: .destructive) {
                        AnalyticsEvents.logButtonClick("unsaved_discard", screen: LibraryList.screen)
                        list.proceed(with: pending)
                    }
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("unsaved_cancel", screen: LibraryList.screen)
                    }
                } message: { pending in
                    Text(unsavedMessage(for: pending.mode))
                }
                .alert("Discard Draft?", isPresented: Binding(
                    get: { list.draftToDiscard != nil },
                    set: { if !$0 { list.draftToDiscard = nil } }
                ), presenting: list.draftToDiscard) { mode in
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("discard_draft_cancel", screen: LibraryList.screen)
                    }
                    Button("Discard", role: .destructive) {
                        AnalyticsEvents.logButtonClick("discard_draft", screen: LibraryList.screen)
                        let current = settingsService.settings.scriptMode
                        settingsService.createNewNote(mode: mode)
                        settingsService.settings.scriptMode = current
                    }
                } message: { _ in
                    Text("It was never saved, so it can't be brought back.")
                }
                .alert("Rename Script", isPresented: Binding(
                    get: { list.noteToRename != nil },
                    set: { if !$0 { list.noteToRename = nil } }
                )) {
                    TextField("Title", text: list.$renameTitle)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("rename_note_cancel", screen: LibraryList.screen)
                    }
                    Button("Rename") {
                        AnalyticsEvents.logButtonClick("rename_note_confirm", screen: LibraryList.screen)
                        guard let note = list.noteToRename else { return }
                        let title = list.renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty, !settingsService.updateNote(id: note.id, title: title) {
                            list.errorMessage = String(localized: "The note couldn't be renamed. Try again.")
                        }
                    }
                }
                .alert("Delete “\(list.noteToDelete?.title ?? "")”?", isPresented: Binding(
                    get: { list.noteToDelete != nil },
                    set: { if !$0 { list.noteToDelete = nil } }
                ), presenting: list.noteToDelete) { note in
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("delete_note_cancel", screen: LibraryList.screen)
                    }
                    Button("Delete", role: .destructive) {
                        AnalyticsEvents.logButtonClick("delete_note", screen: LibraryList.screen)
                        if !settingsService.deleteNote(id: note.id) {
                            list.errorMessage = String(localized: "The note was deleted. \(list.undeletedFilesMessage(count: 1))")
                        }
                    }
                } message: { _ in
                    if let folder = settingsService.notesFolderName {
                        Text("Its versions and its file in “\(folder)” folder are deleted too. Takes stay in Photos.")
                    } else {
                        Text("Its versions are deleted too. Takes stay in Photos.")
                    }
                }
                .alert("Something Went Wrong", isPresented: Binding(
                    get: { list.errorMessage != nil },
                    set: { if !$0 { list.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {
                        AnalyticsEvents.logButtonClick("library_error_ok", screen: LibraryList.screen)
                    }
                } message: {
                    Text(list.errorMessage ?? "")
                }
        }

        private func unsavedMessage(for mode: ScriptMode) -> String {
            if let id = settingsService.noteId(for: mode),
               let title = settingsService.savedNotes.first(where: { $0.id == id })?.title {
                return String(localized: "“\(title)” has changes that aren't saved. Opening another script in its place loses them.")
            }
            return mode == .cards
                ? String(localized: "The new deck you started isn't saved. Opening another in its place loses it.")
                : String(localized: "The new script you started isn't saved. Opening another in its place loses it.")
        }
    }

    private struct FolderAlerts: ViewModifier {
        let list: LibraryList

        private var settingsService: SettingsService { list.settingsService }

        func body(content: Content) -> some View {
            content
                .alert("New Folder", isPresented: list.$showingNewFolder) {
                    TextField("Name", text: list.$newFolderName)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("new_folder_cancel", screen: LibraryList.screen)
                    }
                    Button("Create") {
                        AnalyticsEvents.logButtonClick("new_folder_create", screen: LibraryList.screen)
                        guard let name = settingsService.createFolder(named: list.newFolderName) else {
                            list.errorMessage = String(localized: "There's already a folder with that name, or the name can't be used.")
                            return
                        }
                        if let note = list.noteForNewFolder {
                            list.move(note, to: name, from: "move_note_new_folder")
                        }
                    }
                } message: {
                    Text(settingsService.notesFolderName.map {
                        String(localized: "It's made in “\($0)” folder too.")
                    } ?? "")
                }
                .alert("Rename Folder", isPresented: Binding(
                    get: { list.folderToRename != nil },
                    set: { if !$0 { list.folderToRename = nil } }
                )) {
                    TextField("Name", text: list.$folderTitle)
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("rename_folder_cancel", screen: LibraryList.screen)
                    }
                    Button("Rename") {
                        AnalyticsEvents.logButtonClick("rename_folder_confirm", screen: LibraryList.screen)
                        guard let name = list.folderToRename else { return }
                        guard settingsService.renameFolder(name, to: list.folderTitle) else {
                            list.errorMessage = String(localized: "There's already a folder with that name, or the name can't be used.")
                            return
                        }
                        // Renamed from inside it: the screen follows.
                        if list.folder == name, let renamed = settingsService.folders.first(where: {
                            $0 == ScriptFile.folderName(from: list.folderTitle)
                        }), !list.path.isEmpty {
                            list.path[list.path.count - 1] = .folder(renamed)
                        }
                    }
                }
                .alert("Delete “\(list.folderToDelete ?? "")” Folder?", isPresented: Binding(
                    get: { list.folderToDelete != nil },
                    set: { if !$0 { list.folderToDelete = nil } }
                ), presenting: list.folderToDelete) { name in
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("delete_folder_cancel", screen: LibraryList.screen)
                    }
                    Button("Delete Folder", role: .destructive) {
                        AnalyticsEvents.logButtonClick("delete_folder_confirm", screen: LibraryList.screen)
                        settingsService.deleteFolder(name)
                        if list.folder == name, !list.path.isEmpty {
                            list.path.removeLast()
                        }
                    }
                } message: { _ in
                    Text("The scripts in it aren't deleted. They move to the top of your library.")
                }
        }
    }

    private struct StorageAlerts: ViewModifier {
        let list: LibraryList

        private var settingsService: SettingsService { list.settingsService }

        func body(content: Content) -> some View {
            content
                // Alerts rather than confirmation dialogs, which leave Cancel out
                // where they open as a popover.
                .alert("Stop Using Storage Folder?", isPresented: list.$showingStopFolder) {
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("stop_notes_folder_cancel", screen: LibraryList.screen)
                    }
                    Button("Stop Using Folder", role: .destructive) {
                        AnalyticsEvents.logButtonClick("stop_notes_folder_confirm", screen: LibraryList.screen)
                        if !settingsService.stopUsingNotesFolder() {
                            list.showingStopFolderFailed = true
                        }
                    }
                } message: {
                    if let folder = settingsService.notesFolderName {
                        Text("The script files in “\(folder)” folder will be deleted. Your scripts stay in CueCard, but are deleted if the app is removed.")
                    } else {
                        Text("Your scripts stay in CueCard, but are deleted if the app is removed.")
                    }
                }
                .alert("Delete All Scripts?", isPresented: list.$showingDeleteAll) {
                    Button("Cancel", role: .cancel) {
                        AnalyticsEvents.logButtonClick("delete_all_notes_cancel", screen: LibraryList.screen)
                    }
                    Button("Delete All", role: .destructive) {
                        AnalyticsEvents.logButtonClick("delete_all_notes_confirm", screen: LibraryList.screen)
                        let count = settingsService.savedNotes.count
                        if !settingsService.deleteAllNotes() {
                            list.errorMessage = String(localized: "Your notes were deleted. \(list.undeletedFilesMessage(count: count))")
                        }
                    }
                } message: {
                    if let folder = settingsService.notesFolderName {
                        Text("Every saved script and its file in “\(folder)” folder will be deleted. This can't be undone.")
                    } else {
                        Text("Every saved script will be deleted. This can't be undone.")
                    }
                }
                .alert("Couldn't Delete Script Files", isPresented: list.$showingStopFolderFailed) {
                    Button("Keep Using Folder", role: .cancel) {
                        AnalyticsEvents.logButtonClick("stop_notes_folder_keep", screen: LibraryList.screen)
                    }
                    Button("Stop Anyway") {
                        AnalyticsEvents.logButtonClick("stop_notes_folder_anyway", screen: LibraryList.screen)
                        settingsService.stopUsingNotesFolderKeepingFiles()
                    }
                } message: {
                    if let folder = settingsService.notesFolderName {
                        Text("Some script files in “\(folder)” folder couldn't be deleted, so it's still in use. You can stop using it anyway and leave the files there.")
                    } else {
                        Text("The storage folder can't be reached, so its script files couldn't be deleted. You can stop using it anyway and leave the files there.")
                    }
                }
        }
    }
}

// MARK: - Rows

private extension View {
    /// A row of the library's list drawn on its own, with no background or
    /// separator from the list.
    func plainRow(insets: EdgeInsets) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// A script or deck as a card: its title, how it starts, when it was
/// edited, and the takes recorded with it, which open from here.
private struct LibraryScriptRow: View {
    let title: String
    let preview: String
    let detail: String
    /// Draft or Unsaved, beside the title.
    let badge: String?
    let takes: Int
    let colorScheme: ColorScheme
    let onTakes: () -> Void

    static let cornerRadius: CGFloat = 22

    private var secondary: Color { AppColors.textSecondary(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.yellow(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.yellow(for: colorScheme).opacity(0.15)))
                        .fixedSize()
                }
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(secondary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if takes > 0 {
                    Button(action: onTakes) {
                        Text(String(localized: "\(takes) Takes", comment: "How many videos were recorded with a script"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(secondary.opacity(0.15)))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.11) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(secondary.opacity(0.2), lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if takes > 0 {
                Button(String(localized: "Show Takes"), action: onTakes)
            }
        }
    }
}

// MARK: - Storage

/// Says plainly that scripts are lost with the app until there's a storage
/// folder, and offers to choose one. Put away, it comes back every tenth
/// time the app is opened. With a folder that can't be reached, says that.
private struct LibraryStorageBanner: View {
    /// There's a folder, but it can't be reached.
    let isUnreachable: Bool
    let colorScheme: ColorScheme
    let onChoose: () -> Void
    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isUnreachable ? "Storage Folder Can't Be Reached" : "Your Scripts Aren't Backed Up")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    Text(isUnreachable
                         ? "Your scripts are only kept in CueCard until it's back. Choose it again if it moved."
                         : "If CueCard is deleted, your scripts go with it. Choose a folder on this iPhone or in iCloud Drive to keep each one as a file.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onDismiss {
                    Spacer(minLength: 0)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColors.textSecondary(for: colorScheme).opacity(0.15)))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Not Now")
                }
            }

            Button(action: onChoose) {
                Text(isUnreachable ? "Choose Folder Again" : "Choose Folder")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .background(Capsule().fill(AppColors.textPrimary(for: colorScheme)))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LibraryScriptRow.cornerRadius, style: .continuous)
                .fill(AppColors.yellow(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LibraryScriptRow.cornerRadius, style: .continuous)
                .stroke(AppColors.yellow(for: colorScheme).opacity(0.4), lineWidth: 1)
        )
    }
}

/// Where scripts are kept, at the end of the library, with anything the
/// storage folder couldn't take.
private struct LibraryFooter: View {
    @EnvironmentObject var settingsService: SettingsService
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = oversizedFilesWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.yellow(for: colorScheme))
            }
            if let warning = undeletedFilesWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.yellow(for: colorScheme))
            }
            Label {
                storageText
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .font(.caption)
    }

    private var storageText: Text {
        if settingsService.notesFolderIsInICloud {
            Text("Your scripts stay in your iCloud Drive.")
        } else if settingsService.notesFolderName != nil {
            Text("Your scripts stay on your device.")
        } else if settingsService.hasNotesFolder {
            Text("The storage folder can't be reached, so your scripts stay only on your device until it's back.")
        } else {
            Text("Your scripts stay on your device and are deleted along with the app.")
        }
    }

    /// Files in the storage folder that were too large to bring in, if any.
    private var oversizedFilesWarning: String? {
        let files = settingsService.notesFolderOversizedFiles
        guard let first = files.first else { return nil }
        if files.count == 1 {
            return String(localized: "“\(first)” is larger than 10 MB, so it wasn't added to your notes.")
        }
        return String(localized: "\(files.count) files in the notes folder are larger than 10 MB, so they weren't added to your notes.")
    }

    /// Files of deleted scripts still in the storage folder, if any.
    private var undeletedFilesWarning: String? {
        let files = settingsService.notesFolderUndeletedFiles
        guard let first = files.first else { return nil }
        if files.count == 1 {
            return String(localized: "“\(first)” couldn't be deleted from the notes folder. Its note stays deleted.")
        }
        return String(localized: "\(files.count) files couldn't be deleted from the notes folder. Their notes stay deleted.")
    }
}

// MARK: - Takes

/// The takes of a script opened from the library, rather than the editor.
private struct ScriptTakesSheet: View {
    let title: String
    @StateObject private var library: TakesLibrary

    init(scriptID: UUID, title: String) {
        self.title = title
        _library = StateObject(wrappedValue: {
            let library = TakesLibrary()
            library.load(scriptID: scriptID)
            return library
        }())
    }

    var body: some View {
        TakesView(library: library, scriptTitle: title)
    }
}

// MARK: - Text

enum LibraryText {
    /// A script's words, without card breaks, images, anchors or emphasis
    /// markers, for searching and previews.
    static func plain(_ content: String) -> String {
        RichText.plain(TeleprompterParser.removingAnchors(from: TeleprompterParser.removingImages(
            from: CueCards.removingSeparators(from: content))))
    }

    /// The start of a script, on one line.
    static func preview(of content: String) -> String {
        String(plain(content).trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// The time today, Yesterday, or the date.
    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Sharing

/// Share a script as text, or — with images in it — as a TextPack, so they
/// go with it.
struct ScriptShareLink: View {
    let title: String?
    let content: String

    var body: some View {
        let subject = title ?? String(localized: "Speech")
        if content.contains("[image"), !TeleprompterParser.imageMatches(in: content).isEmpty {
            ShareLink(item: ScriptPackage(title: title, content: content),
                      subject: Text(subject), preview: SharePreview(subject)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: TeleprompterParser.normalizingTags(in: content), subject: Text(subject)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteNotificationService.shared)
}
