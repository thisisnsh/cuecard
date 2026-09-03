import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import FirebaseAnalytics
import FirebaseCrashlytics

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var remoteConfig: RemoteConfigService
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false
    @State private var showingTeleprompter = false
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
    @Environment(\.requestReview) private var requestReview

    /// How much of the editor's bottom the controls row covers: the play button
    /// and the timer beside it, plus the gap they sit above. The script keeps this
    /// much room clear so its last line never rests underneath them.
    private static let controlsHeight: CGFloat = 52 + 24

    private var hasNotes: Bool {
        !settingsService.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    if let message = remoteConfig.message(for: .homeBanner) {
                        RemoteMessageBanner(message: message)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Notes editor
                    NotesEditorView(
                        text: $settingsService.notes,
                        isFocused: $isEditorFocused,
                        controller: editorController,
                        cueColor: settingsService.settings.cueColor,
                        colorScheme: colorScheme,
                        keyboardOverlayHeight: CueBar.height,
                        restingOverlayHeight: Self.controlsHeight
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The editor makes its own room for the keyboard, as scroll
                    // inset. SwiftUI's avoidance would resize it instead, and the
                    // gap it leaves behind on dismissal cuts the script off.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
                .animation(.easeInOut(duration: 0.25), value: remoteConfig.dismissedIDs)
            }
            .overlay(alignment: .bottom) {
                if isEditorFocused {
                    CueBar(
                        colorScheme: colorScheme,
                        onAddCue: insertCue,
                        onDismissKeyboard: { isEditorFocused = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        timerControl
                    }

                    Spacer(minLength: 12)

                    Button(action: {
                        AnalyticsEvents.logButtonClick("start_teleprompter", screen: "home")
                        isEditorFocused = false
                        showingTeleprompter = true
                    }) {
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
                    .disabled(!hasNotes)
                    .opacity(hasNotes ? 1.0 : 0.6)
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
                    Button(action: {
                        AnalyticsEvents.logButtonClick("saved_notes", screen: "home")
                        showingSavedNotes = true
                    }) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
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

                            Divider()

                            Button(action: {
                                AnalyticsEvents.logButtonClick("new_note", screen: "home")
                                settingsService.createNewNote()
                            }) {
                                Label("New Note", systemImage: "square.and.pencil")
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
                SettingsView()
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
                TeleprompterView(
                    content: TeleprompterParser.parseNotes(settingsService.notes),
                    settings: settingsService.settings
                )
            }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "home"
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
    /// Room the cue bar takes at the bottom while the keyboard is up.
    var keyboardOverlayHeight: CGFloat = 0
    /// Room the home controls take at the bottom once the keyboard has gone.
    var restingOverlayHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text("Add your script here...\n\nTap Add Cue below the script — or just type [ — to drop in a delivery reminder like \"Welcome everyone [cue smile and pause]\"")
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.top, CueTextEditor.edgeFade + 8)
                    .allowsHitTesting(false)
            }

            CueTextEditor(
                text: $text,
                isFocused: $isFocused,
                controller: controller,
                cueColor: cueColor,
                colorScheme: colorScheme,
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

    var body: some View {
        NavigationStack {
            Group {
                if settingsService.savedNotes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                        Text("No Saved Notes")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                        Text("Save your notes to access them later")
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
                                    Text(note.title)
                                        .font(.headline)
                                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                                    Text(note.content.prefix(100).replacingOccurrences(of: "\n", with: " "))
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
            .navigationTitle("Saved Notes")
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
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteConfigService.shared)
}

#Preview("Saved Notes") {
    SavedNotesView()
        .environmentObject(SettingsService.shared)
}
