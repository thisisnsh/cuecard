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
        .fullScreenCover(isPresented: $showingWatchCards, onDismiss: takeCounts.reload) {
            CueCardsView(cards: nil, title: cardsSession.title, deckID: cardsSession.deckID)
                // Passed on by hand: as an iPad app on a Mac, a full screen
                // cover doesn't inherit environment objects.
                .environmentObject(settingsService)
        }
        .onAppear {
            takeCounts.reload()
            showCardsOpenedOnWatch()
        }
        .onChange(of: cardsSession.sessionID) {
            showCardsOpenedOnWatch()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            takeCounts.reload()
            showCardsOpenedOnWatch()
        }
        // Back from the editor, there may be new takes or a new note.
        .onChange(of: path) {
            if !path.contains(.editor) { takeCounts.reload() }
        }
    }

    /// The editor shows a deck opened from the watch itself, while it's open.
    private func showCardsOpenedOnWatch() {
        guard scenePhase == .active, !path.contains(.editor), !cardsSession.cards.isEmpty,
              !showingWatchCards else { return }
        showingWatchCards = true
    }
}

// MARK: - Sorting and filtering

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

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, teleprompter, cards

    var id: String { rawValue }

    var mode: ScriptMode? {
        switch self {
        case .all: return nil
        case .teleprompter: return .teleprompter
        case .cards: return .cards
        }
    }

    var displayName: String {
        mode?.displayName ?? String(localized: "All")
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

/// The top of the library, or one of its folders: the scripts in it, the
/// drafts started in it, and at the top, the folders.
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
    @AppStorage("library_filter") private var filter: LibraryFilter = .all
    /// The card about the notes folder was put away. The footer still says
    /// what happens without one.
    @AppStorage("library_folder_tip_dismissed") private var folderTipDismissed = false

    @State private var query = ""
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
                && (filter.mode == nil || note.mode == filter.mode)
                && matches(title: note.title, content: note.content)
        }
        switch sort {
        case .edited: return shown.sorted { $0.updatedAt > $1.updatedAt }
        case .created: return shown.sorted { $0.createdAt > $1.createdAt }
        case .title: return shown.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// Modes with a new script that isn't saved yet, started here.
    private var drafts: [ScriptMode] {
        ScriptMode.allCases.filter { mode in
            let text = settingsService.notes(for: mode)
            return settingsService.noteId(for: mode) == nil
                && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (isSearchingAll || settingsService.draftFolder(for: mode) == folder)
                && (filter.mode == nil || filter.mode == mode)
                && matches(title: "", content: text)
        }
    }

    private var folders: [String] {
        guard isRoot, trimmedQuery.isEmpty else { return [] }
        return settingsService.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isEmpty: Bool {
        notes.isEmpty && drafts.isEmpty && folders.isEmpty
    }

    private func matches(title: String, content: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return title.localizedStandardContains(trimmedQuery)
            || LibraryText.plain(content).localizedStandardContains(trimmedQuery)
    }

    var body: some View {
        List {
            if isRoot, let notification = notifications.notification(for: .homeBanner) {
                Section {
                    NotificationBanner(notification: notification)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if isRoot, trimmedQuery.isEmpty, needsFolderCard {
                Section {
                    LibraryStorageCard(
                        isUnreachable: settingsService.hasNotesFolder,
                        colorScheme: colorScheme,
                        onChoose: {
                            AnalyticsEvents.logButtonClick("choose_notes_folder", screen: Self.screen)
                            showingFolderPicker = true
                        },
                        onDismiss: settingsService.hasNotesFolder ? nil : {
                            AnalyticsEvents.logButtonClick("dismiss_folder_tip", screen: Self.screen)
                            withAnimation { folderTipDismissed = true }
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                if !folders.isEmpty {
                    ForEach(folders, id: \.self) { name in
                        folderRow(name)
                    }
                }
            } header: {
                filterPicker
            }

            if !drafts.isEmpty || !notes.isEmpty {
                Section {
                    ForEach(drafts) { mode in
                        draftRow(mode)
                    }
                    ForEach(notes) { note in
                        noteRow(note)
                    }
                } header: {
                    if !folders.isEmpty {
                        Text("Scripts")
                    }
                }
            } else if isRoot, trimmedQuery.isEmpty, folders.isEmpty {
                // In the list, not over it, so the storage card stays in view.
                Section {
                    emptyState
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            }

            if isRoot {
                Section {
                } footer: {
                    footer
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background(for: colorScheme).ignoresSafeArea())
        .overlay {
            if !isRoot || !trimmedQuery.isEmpty { emptyState }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                newButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .searchable(text: $query, prompt: searchPrompt)
        .navigationTitle(folder ?? String(localized: "Library"))
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
            HelpToolbarItem(page: .library, isPresented: $showingHelp)
        }
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

    private var searchPrompt: String {
        folder.map { String(localized: "Search \($0)", comment: "Search a library folder") }
            ?? String(localized: "Search All Scripts")
    }

    /// Shown until there's a notes folder, unless put away, and whenever the
    /// folder there is can't be reached.
    private var needsFolderCard: Bool {
        settingsService.hasNotesFolder ? settingsService.notesFolderName == nil : !folderTipDismissed
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(LibraryFilter.allCases) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .textCase(nil)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var emptyState: some View {
        if isEmpty {
            if !trimmedQuery.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else if filter != .all, !settingsService.savedNotes.isEmpty {
                ContentUnavailableView("No \(filter.displayName) Scripts", systemImage: filter.mode?.systemImage ?? "doc")
            } else if !isRoot {
                ContentUnavailableView("Empty Folder", systemImage: "folder",
                                       description: Text("Tap New to write in here, or move scripts in from the library."))
            } else {
                ContentUnavailableView("No Scripts Yet", systemImage: "text.alignleft",
                                       description: Text("Tap New to write a script for the teleprompter, or a deck of cards."))
            }
        }
    }

    private var footer: some View {
        LibraryFooter(colorScheme: colorScheme)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    private var newButton: some View {
        Menu {
            Button {
                startNew(.teleprompter)
            } label: {
                Label("Teleprompter Script", systemImage: ScriptMode.teleprompter.systemImage)
            }
            Button {
                startNew(.cards)
            } label: {
                Label("Cards Deck", systemImage: ScriptMode.cards.systemImage)
            }
            Divider()
            Button {
                AnalyticsEvents.logButtonClick("import_file", screen: Self.screen)
                showingImporter = true
            } label: {
                Label("Import File", systemImage: "arrow.down.doc")
            }
        } label: {
            Label("New", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background(Capsule().fill(AppColors.green(for: colorScheme)))
                .glassedEffect(in: Capsule())
                .shadow(color: Color.black.opacity(0.1), radius: 10)
        }
        .accessibilityLabel("New Script")
    }

    private var moreMenu: some View {
        Menu {
            Picker(selection: $sort) {
                ForEach(LibrarySort.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)

            Divider()

            if isRoot {
                Button {
                    AnalyticsEvents.logButtonClick("new_folder", screen: Self.screen)
                    noteForNewFolder = nil
                    newFolderName = ""
                    showingNewFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } else if let folder {
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

            Button {
                AnalyticsEvents.logButtonClick("import_file", screen: Self.screen)
                showingImporter = true
            } label: {
                Label("Import File", systemImage: "arrow.down.doc")
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
        .accessibilityLabel("More")
    }

    // MARK: Rows

    private func folderRow(_ name: String) -> some View {
        let count = settingsService.savedNotes.filter { $0.folder == name }.count
        return NavigationLink(value: LibraryRoute.folder(name)) {
            HStack(spacing: 14) {
                LibraryTile(systemImage: "folder.fill", color: AppColors.blue(for: colorScheme))
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
        .contextMenu {
            Button {
                folderTitle = name
                folderToRename = name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                folderToDelete = name
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                folderToDelete = name
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(AppColors.red(for: colorScheme))
            Button {
                folderTitle = name
                folderToRename = name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func draftRow(_ mode: ScriptMode) -> some View {
        LibraryScriptRow(
            title: mode == .cards ? String(localized: "New Deck") : String(localized: "New Script"),
            mode: mode,
            preview: LibraryText.preview(of: settingsService.notes(for: mode)),
            detail: String(localized: "Not saved yet"),
            badge: String(localized: "Draft"),
            isOnWatch: false,
            takes: takeCounts.count(for: mode == .cards ? settingsService.cardsScriptID
                                                        : settingsService.teleprompterScriptID),
            colorScheme: colorScheme,
            onTakes: {
                takesTarget = TakesTarget(id: mode == .cards ? settingsService.cardsScriptID
                                                             : settingsService.teleprompterScriptID,
                                          title: mode == .cards ? String(localized: "New Deck")
                                                                : String(localized: "New Script"))
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { openDraft(mode) }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                openDraft(mode)
            } label: {
                Label("Keep Writing", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                draftToDiscard = mode
            } label: {
                Label("Discard", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
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
            mode: note.mode,
            preview: LibraryText.preview(of: note.content),
            detail: detail(of: note),
            badge: isOpen && settingsService.hasUnsavedChanges(in: note.mode) ? String(localized: "Unsaved") : nil,
            isOnWatch: settingsService.watchNoteIDs.contains(note.id),
            takes: takeCounts.count(for: note.id),
            colorScheme: colorScheme,
            onTakes: {
                AnalyticsEvents.logButtonClick("takes", screen: Self.screen)
                takesTarget = TakesTarget(id: note.id, title: note.title)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { open(note) }
        .accessibilityAddTraits(.isButton)
        .contextMenu { noteMenu(note) }
        .swipeActions(edge: .trailing) {
            Button {
                noteToDelete = note
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(AppColors.red(for: colorScheme))
        }
        .swipeActions(edge: .leading) {
            Button {
                AnalyticsEvents.logButtonClick("rename_note", screen: Self.screen)
                renameTitle = note.title
                noteToRename = note
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
            Button {
                duplicate(note)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(AppColors.blue(for: colorScheme))
        }
    }

    @ViewBuilder
    private func noteMenu(_ note: SavedNote) -> some View {
        Button {
            open(note)
        } label: {
            Label("Open", systemImage: "square.and.pencil")
        }

        Button {
            AnalyticsEvents.logButtonClick("rename_note", screen: Self.screen)
            renameTitle = note.title
            noteToRename = note
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            duplicate(note)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Menu {
            Picker("Move to Folder", selection: Binding(
                get: { note.folder },
                set: { move(note, to: $0) }
            )) {
                Label("Library", systemImage: "tray").tag(String?.none)
                ForEach(settingsService.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                        id: \.self) { name in
                    Label(name, systemImage: "folder").tag(String?.some(name))
                }
            }
            .pickerStyle(.inline)

            Button {
                noteForNewFolder = note
                newFolderName = ""
                showingNewFolder = true
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
            noteToDelete = note
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// When it was last edited, how many cards a deck has, and, in search
    /// results from every folder, the folder it's in.
    private func detail(of note: SavedNote) -> String {
        var parts = [LibraryText.date(note.updatedAt)]
        if note.mode == .cards {
            let count = CueCards.cards(in: note.content).count
            parts.append(String(localized: "\(count) cards", comment: "How many cards a deck has"))
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
    private func open(_ note: SavedNote) {
        AnalyticsEvents.logButtonClick("load_note", screen: Self.screen)
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

    private func duplicate(_ note: SavedNote) {
        AnalyticsEvents.logButtonClick("duplicate_note", screen: Self.screen)
        if settingsService.duplicateNote(id: note.id) == nil {
            errorMessage = String(localized: "The script couldn't be duplicated. Try again.")
        }
    }

    private func move(_ note: SavedNote, to folder: String?) {
        AnalyticsEvents.logButtonClick("move_note", screen: Self.screen)
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
                            if settingsService.saveChanges(in: pending.mode) {
                                list.proceed(with: pending)
                            } else {
                                list.errorMessage = String(localized: "Your note couldn't be saved. Try again.")
                            }
                        }
                    }
                    Button("Keep Editing") { list.openDraft(pending.mode) }
                    Button("Discard Changes", role: .destructive) { list.proceed(with: pending) }
                    Button("Cancel", role: .cancel) { }
                } message: { pending in
                    Text(unsavedMessage(for: pending.mode))
                }
                .alert("Discard Draft?", isPresented: Binding(
                    get: { list.draftToDiscard != nil },
                    set: { if !$0 { list.draftToDiscard = nil } }
                ), presenting: list.draftToDiscard) { mode in
                    Button("Cancel", role: .cancel) { }
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
                    Button("Cancel", role: .cancel) { }
                    Button("Rename") {
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
                    Button("Cancel", role: .cancel) { }
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
                    Button("OK", role: .cancel) { }
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
                    Button("Cancel", role: .cancel) { }
                    Button("Create") {
                        guard let name = settingsService.createFolder(named: list.newFolderName) else {
                            list.errorMessage = String(localized: "There's already a folder with that name, or the name can't be used.")
                            return
                        }
                        if let note = list.noteForNewFolder {
                            list.move(note, to: name)
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
                    Button("Cancel", role: .cancel) { }
                    Button("Rename") {
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
                    Button("Cancel", role: .cancel) { }
                    Button("Delete Folder", role: .destructive) {
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
                    Button("Cancel", role: .cancel) { }
                    Button("Stop Using Folder", role: .destructive) {
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
                    Button("Cancel", role: .cancel) { }
                    Button("Delete All", role: .destructive) {
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
                    Button("Keep Using Folder", role: .cancel) { }
                    Button("Stop Anyway") {
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

/// A mode's or a folder's symbol on a tinted square, leading each row.
private struct LibraryTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

/// A script or deck: its title, how it starts, when it was edited, and the
/// takes recorded with it, which open from here.
private struct LibraryScriptRow: View {
    let title: String
    let mode: ScriptMode
    let preview: String
    let detail: String
    /// Draft or Unsaved, beside the title.
    let badge: String?
    let isOnWatch: Bool
    let takes: Int
    let colorScheme: ColorScheme
    let onTakes: () -> Void

    private var secondary: Color { AppColors.textSecondary(for: colorScheme) }

    private var tint: Color {
        mode == .cards ? AppColors.purple(for: colorScheme) : AppColors.blue(for: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LibraryTile(systemImage: mode == .cards ? "rectangle.stack.fill" : "text.alignleft", color: tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    if isOnWatch {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundStyle(secondary)
                            .accessibilityLabel("On Apple Watch")
                    }
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
                        .foregroundStyle(secondary.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if takes > 0 {
                        Button(action: onTakes) {
                            Label(String(localized: "\(takes) Takes", comment: "How many videos were recorded with a script"),
                                  systemImage: "film.stack")
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
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if takes > 0 {
                Button(String(localized: "Show Takes"), action: onTakes)
            }
        }
    }
}

// MARK: - Storage

/// Says plainly that scripts are lost with the app until there's a folder
/// to keep them in, and offers to choose one. Or, with a folder that can't
/// be reached, says that.
private struct LibraryStorageCard: View {
    /// There's a folder, but it can't be reached.
    let isUnreachable: Bool
    let colorScheme: ColorScheme
    let onChoose: () -> Void
    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isUnreachable ? "externaldrive.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.yellow(for: colorScheme))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isUnreachable ? "Storage Folder Can't Be Reached" : "Only in This App")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    Text(isUnreachable
                         ? "Your scripts are only kept in CueCard until it's back. Choose it again if it moved."
                         : "If CueCard is deleted, your scripts go with it. Choose a folder to keep each one as a file, on this iPhone or in iCloud Drive.")
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .background(Capsule().fill(AppColors.textPrimary(for: colorScheme)))
            }
            .buttonStyle(.borderless)

            if !isUnreachable {
                Text("Pick an empty folder or one made for your scripts. Text files in it become scripts, and the folders in it become folders here.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.yellow(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.yellow(for: colorScheme).opacity(0.35), lineWidth: 1)
        )
    }
}

/// Where scripts are kept and what CueCard does with them, at the end of the
/// library, with anything the storage folder couldn't take.
private struct LibraryFooter: View {
    @EnvironmentObject var settingsService: SettingsService
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 10) {
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
        .multilineTextAlignment(.center)
        .textCase(nil)
    }

    private var storageText: Text {
        if let folder = settingsService.notesFolderName {
            Text("No account, and nothing uploaded by CueCard. Your scripts are kept on this iPhone and as files in “\(folder)” folder, so they stay if the app is removed.")
        } else if settingsService.hasNotesFolder {
            Text("No account, and nothing uploaded by CueCard. The storage folder can't be reached, so your scripts are only kept on this iPhone until it's back.")
        } else {
            Text("No account, and nothing uploaded by CueCard. Your scripts are kept only on this iPhone, and are deleted if the app is removed.")
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
