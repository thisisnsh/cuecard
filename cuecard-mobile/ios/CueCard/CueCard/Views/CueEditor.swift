import SwiftUI
import UIKit

/// Script editor that renders `[note …]` cues in their own color while you type,
/// and reports the caret back so cues can be inserted where the user is writing.
struct CueTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool
    let colorScheme: ColorScheme

    static let fontSize: CGFloat = 16

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.text = text
        Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
            Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        } else if context.coordinator.appliedColorScheme != colorScheme {
            Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        }
        context.coordinator.appliedColorScheme = colorScheme

        let clamped = Self.clamp(selectedRange, to: textView.text as NSString)
        if textView.selectedRange != clamped {
            textView.selectedRange = clamped
        }

        // SwiftUI's .focused() doesn't reach into a UIViewRepresentable, so drive
        // first responder status from the binding instead.
        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func clamp(_ range: NSRange, to text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), text.length - location)
        return NSRange(location: location, length: length)
    }

    // MARK: - Highlighting

    static func applyHighlighting(to textView: UITextView, colorScheme: ColorScheme) {
        // Recoloring mid-composition would drop the in-progress marked text.
        guard textView.markedTextRange == nil else { return }

        let isDarkMode = colorScheme == .dark
        let baseAttributes = baseAttributes(isDarkMode: isDarkMode)
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        for match in TeleprompterParser.cueMatches(in: textView.text) {
            let cueColor = match.color.uiColor(isDarkMode: isDarkMode)

            // The tag syntax stays visible — and editable — but recedes.
            storage.addAttributes([
                .foregroundColor: cueColor.withAlphaComponent(0.45),
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium)
            ], range: match.range)

            storage.addAttributes([
                .foregroundColor: cueColor,
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            ], range: match.contentRange)
        }
        storage.endEditing()

        textView.typingAttributes = baseAttributes
    }

    private static func baseAttributes(isDarkMode: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CueTextEditor
        var appliedColorScheme: ColorScheme?

        init(parent: CueTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            CueTextEditor.applyHighlighting(to: textView, colorScheme: parent.colorScheme)
            textView.selectedRange = selection

            parent.text = textView.text
            parent.selectedRange = selection
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let selection = textView.selectedRange
            guard parent.selectedRange != selection else { return }
            parent.selectedRange = selection
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !parent.isFocused else { return }
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.isFocused else { return }
            parent.isFocused = false
        }
    }
}

// MARK: - Cue insertion

extension String {
    /// Insert a cue tag at `range`, adding the spaces needed so it doesn't collide
    /// with the surrounding words. Returns the caret position after the tag.
    func insertingCue(_ tag: String, at range: NSRange) -> (text: String, caret: Int) {
        let nsText = self as NSString
        let location = min(max(range.location + range.length, 0), nsText.length)

        let previous = location > 0 ? nsText.substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < nsText.length ? nsText.substring(with: NSRange(location: location, length: 1)) : ""

        let needsLeadingSpace = !previous.isEmpty && previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let needsTrailingSpace = !next.isEmpty && next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil

        let insertion = (needsLeadingSpace ? " " : "") + tag + (needsTrailingSpace ? " " : "")
        let updated = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
        let caret = location + (insertion as NSString).length - (needsTrailingSpace ? 1 : 0)

        return (updated, caret)
    }
}

// MARK: - Cue bar

/// The row of reusable cues that sits above the keyboard while writing a script.
struct CueBar: View {
    let cues: [Cue]
    let colorScheme: ColorScheme
    var onInsert: (Cue) -> Void
    var onCreate: () -> Void
    var onEdit: (Cue) -> Void
    var onRecolor: (Cue, CueColor) -> Void
    var onDelete: (Cue) -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .frame(width: 34, height: 34)
                    .glassedEffect(in: Circle())
            }
            .accessibilityLabel("New cue")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cues) { cue in
                        Button {
                            onInsert(cue)
                        } label: {
                            CueChip(cue: cue, colorScheme: colorScheme)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onEdit(cue)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Menu {
                                ForEach(CueColor.allCases) { color in
                                    Button {
                                        onRecolor(cue, color)
                                    } label: {
                                        if color == cue.color {
                                            Label(color.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(color.displayName)
                                        }
                                    }
                                }
                            } label: {
                                Label("Color", systemImage: "paintpalette")
                            }

                            Button(role: .destructive) {
                                onDelete(cue)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    .frame(width: 34, height: 34)
                    .glassedEffect(in: Circle())
            }
            .accessibilityLabel("Hide keyboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.background(for: colorScheme).opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary(for: colorScheme).opacity(0.15))
                .frame(height: 0.5)
        }
    }
}

private struct CueChip: View {
    let cue: Cue
    let colorScheme: ColorScheme

    var body: some View {
        Text(cue.text)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(cue.color.color(for: colorScheme))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(cue.color.color(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.13))
            )
            .overlay(
                Capsule()
                    .stroke(cue.color.color(for: colorScheme).opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Composer

/// What the composer sheet is doing: writing a brand new cue, or editing a saved one.
enum CueComposerMode: Identifiable {
    case create
    case edit(Cue)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let cue): return cue.id.uuidString
        }
    }
}

/// Sheet for writing a cue on the spot, or reworking one already in the library.
struct CueComposerSheet: View {
    let mode: CueComposerMode
    /// Called with the finished cue and whether a newly written one should be kept.
    var onCommit: (Cue, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String
    @State private var color: CueColor
    @State private var saveToLibrary = true
    @FocusState private var isTextFieldFocused: Bool

    init(mode: CueComposerMode, onCommit: @escaping (Cue, Bool) -> Void) {
        self.mode = mode
        self.onCommit = onCommit

        switch mode {
        case .create:
            _text = State(initialValue: "")
            _color = State(initialValue: .fallback)
        case .edit(let cue):
            _text = State(initialValue: cue.text)
            _color = State(initialValue: cue.color)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `]` would terminate the tag early, so it can't appear inside a cue.
    private var isValid: Bool {
        !trimmedText.isEmpty && !trimmedText.contains("]") && !trimmedText.contains("\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("smile and pause", text: $text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color.color(for: colorScheme))
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(commit)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(color.color(for: colorScheme).opacity(colorScheme == .dark ? 0.15 : 0.1))
                            )

                        Text("Cues aren't read aloud — they're your reminders on screen.")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                        HStack(spacing: 14) {
                            ForEach(CueColor.allCases) { option in
                                Button {
                                    color = option
                                } label: {
                                    Circle()
                                        .fill(option.color(for: colorScheme))
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            if option == color {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(AppColors.background(for: colorScheme))
                                            }
                                        }
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    AppColors.textPrimary(for: colorScheme),
                                                    lineWidth: option == color ? 2 : 0
                                                )
                                                .padding(-4)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.displayName)
                            }
                        }
                    }

                    if !isEditing {
                        Toggle(isOn: $saveToLibrary) {
                            Text("Keep in my cues")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                        .tint(AppColors.green(for: colorScheme))
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle(isEditing ? "Edit Cue" : "New Cue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background(for: colorScheme), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Insert", action: commit)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.height(isEditing ? 330 : 380)])
        .onAppear { isTextFieldFocused = true }
    }

    private func commit() {
        guard isValid else { return }

        switch mode {
        case .create:
            onCommit(Cue(text: trimmedText, color: color), saveToLibrary)
        case .edit(let cue):
            onCommit(Cue(id: cue.id, text: trimmedText, color: color), true)
        }
        dismiss()
    }
}
