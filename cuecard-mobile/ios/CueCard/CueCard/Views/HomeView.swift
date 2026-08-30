import SwiftUI
import StoreKit
import FirebaseAnalytics
import FirebaseCrashlytics

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false
    @State private var showingTeleprompter = false
    @State private var showingTimerPicker = false
    @State private var timerPickerContentVisible = false
    @State private var showingSavedNotes = false
    @State private var showingSaveDialog = false
    @State private var saveNoteTitle = ""
    @State private var timerPickerTransitionTask: Task<Void, Never>?
    @State private var isEditorFocused = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var composerMode: CueComposerMode?
    @Environment(\.requestReview) private var requestReview

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

    /// Drop a cue tag in at the caret and leave the caret just after it, so the user
    /// can keep typing without hunting for their place.
    private func insertCue(_ cue: Cue) {
        AnalyticsEvents.logButtonClick("insert_cue", screen: "home")

        let result = settingsService.notes.insertingCue(cue.tag, at: editorSelection)
        settingsService.notes = result.text
        editorSelection = NSRange(location: result.caret, length: 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background - matches TeleprompterView
                AppColors.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Notes editor
                    NotesEditorView(
                        text: $settingsService.notes,
                        selectedRange: $editorSelection,
                        isFocused: $isEditorFocused,
                        colorScheme: colorScheme
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                if isEditorFocused {
                    CueBar(
                        cues: settingsService.cues,
                        colorScheme: colorScheme,
                        onInsert: insertCue,
                        onCreate: {
                            AnalyticsEvents.logButtonClick("new_cue", screen: "home")
                            composerMode = .create
                        },
                        onEdit: { composerMode = .edit($0) },
                        onRecolor: { cue, color in
                            settingsService.updateCue(Cue(id: cue.id, text: cue.text, color: color))
                        },
                        onDelete: { settingsService.deleteCue(id: $0.id) },
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
            .sheet(item: $composerMode) { mode in
                CueComposerSheet(mode: mode) { cue, keepInLibrary in
                    switch mode {
                    case .create:
                        if keepInLibrary {
                            settingsService.addCue(cue)
                        }
                        insertCue(cue)
                    case .edit:
                        settingsService.updateCue(cue)
                    }
                }
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

/// Notes editor with live syntax highlighting for [note] cues
struct NotesEditorView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool
    let colorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text("Add your script here...\n\nTap a cue below the script to drop in a delivery reminder like \"Welcome everyone [note smile and pause]\"")
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            CueTextEditor(
                text: $text,
                selectedRange: $selectedRange,
                isFocused: $isFocused,
                colorScheme: colorScheme
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
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
}

#Preview("Saved Notes") {
    SavedNotesView()
        .environmentObject(SettingsService.shared)
}
