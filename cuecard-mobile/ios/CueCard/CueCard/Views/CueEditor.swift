import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// Marks the `[cue …]` scaffolding — the brackets, the keyword, the color name —
    /// so the layout manager can drop its glyphs while the script keeps the tag.
    static let cueSyntax = NSAttributedString.Key("CueCardCueSyntax")
    /// Carries the capsule tint for the cue text itself.
    static let cueCapsule = NSAttributedString.Key("CueCardCueCapsule")
}

/// Draws the capsule behind cue text. The tag around it has no glyphs, so what the
/// user sees is a colored pill they can type inside.
final class CueLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage, let container = textContainers.first else { return }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.cueCapsule, in: characterRange) { value, range, _ in
            guard let color = value as? UIColor else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let capsule = rect
                    .insetBy(dx: -6, dy: -1)
                    .offsetBy(dx: origin.x, dy: origin.y)
                color.setFill()
                UIBezierPath(roundedRect: capsule, cornerRadius: capsule.height / 2).fill()
            }
        }
    }
}

/// Handle on the live text view, so cues can be added and recolored where the user
/// is writing rather than through the text binding, which would move the caret.
@MainActor
final class CueEditorController: ObservableObject {
    /// The color of the cue holding the caret, or the one the next cue will use.
    @Published private(set) var activeColor: CueColor = .fallback
    /// Whether the caret sits in a cue, so a color tap can say what it will do.
    @Published private(set) var isEditingCue = false

    /// Seeded into a new capsule and left selected, so typing replaces it.
    static let placeholder = "cue"

    fileprivate weak var textView: UITextView?
    fileprivate var onProgrammaticEdit: (() -> Void)?

    /// Add a capsule where the user is writing, with its placeholder selected.
    func insertCue() {
        guard let textView else { return }

        let text = textView.text as NSString
        let selection = textView.selectedRange
        let location = min(max(selection.location + selection.length, 0), text.length)

        let previous = location > 0 ? text.substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < text.length ? text.substring(with: NSRange(location: location, length: 1)) : ""

        let needsLeadingSpace = !previous.isEmpty && previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let needsTrailingSpace = !next.isEmpty && next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil

        let tag = TeleprompterParser.cueTag(text: Self.placeholder, color: activeColor)
        let insertion = (needsLeadingSpace ? " " : "") + tag + (needsTrailingSpace ? " " : "")

        textView.selectedRange = NSRange(location: location, length: 0)
        textView.insertText(insertion)

        // Leave the placeholder selected, so the first keystroke becomes the cue.
        let placeholderLength = (Self.placeholder as NSString).length
        let tagStart = location + (needsLeadingSpace ? 1 : 0)
        let contentStart = tagStart + (tag as NSString).length - placeholderLength - 1
        textView.selectedRange = NSRange(location: contentStart, length: placeholderLength)

        onProgrammaticEdit?()
    }

    /// Recolor the cue holding the caret, or choose the color the next one will use.
    func apply(_ color: CueColor) {
        activeColor = color

        guard let textView,
              let match = cueAtCaret(in: textView),
              match.color != color else { return }

        let contentLength = (match.content as NSString).length
        let offsetInContent = min(
            max(0, textView.selectedRange.location - match.contentRange.location),
            contentLength
        )
        let tag = TeleprompterParser.cueTag(text: match.content, color: color)

        replace(match.range, with: tag, in: textView)

        // Put the caret back where it was, measured from the start of the cue text.
        let contentStart = match.range.location + (tag as NSString).length - contentLength - 1
        textView.selectedRange = NSRange(location: contentStart + offsetInContent, length: 0)

        onProgrammaticEdit?()
    }

    /// Keep the bar's swatch in step with wherever the caret has landed.
    func syncActiveColor() {
        guard let textView else { return }

        if let match = cueAtCaret(in: textView) {
            if !isEditingCue { isEditingCue = true }
            if activeColor != match.color { activeColor = match.color }
        } else if isEditingCue {
            isEditingCue = false
        }
    }

    private func cueAtCaret(in textView: UITextView) -> CueMatch? {
        let caret = textView.selectedRange.location
        return TeleprompterParser.cueMatches(in: textView.text).first { match in
            caret >= match.range.location && caret <= match.range.location + match.range.length
        }
    }

    /// Edit through `replace` rather than the text storage, so undo keeps working.
    private func replace(_ range: NSRange, with text: String, in textView: UITextView) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }

        textView.replace(textRange, withText: text)
    }
}

/// Text view that keeps a screen's worth of room below the script, so the last line
/// can be scrolled up to where the eye already is.
final class CueTextView: UITextView {
    override func layoutSubviews() {
        super.layoutSubviews()

        // Half of what's actually visible, so the last line can always reach the
        // middle of the screen — with or without a keyboard covering the bottom.
        let visibleHeight = bounds.height - contentInset.bottom
        let desired = max(visibleHeight * 0.5, 200)
        if abs(textContainerInset.bottom - desired) > 1 {
            textContainerInset.bottom = desired
        }
    }
}

/// Script editor that shows cues as colored capsules — the `[cue …]` tag around them
/// is in the text, and in exported files, but never on screen.
struct CueTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let colorScheme: ColorScheme
    let controller: CueEditorController

    static let fontSize: CGFloat = 16

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, explicitly: hiding the tag and drawing the capsule are both
        // NSLayoutManager work.
        let storage = NSTextStorage()
        let layoutManager = CueLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.delegate = context.coordinator

        let textView = CueTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 240, right: 16)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.text = text

        context.coordinator.textView = textView
        context.coordinator.startObservingKeyboard()
        controller.textView = textView
        controller.onProgrammaticEdit = { [weak coordinator = context.coordinator] in
            coordinator?.syncAfterEdit()
        }

        Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = textView

        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            textView.selectedRange = CueTextEditor.clamp(selection, to: textView.text as NSString)
            Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        } else if context.coordinator.appliedColorScheme != colorScheme {
            Self.applyHighlighting(to: textView, colorScheme: colorScheme)
        }
        context.coordinator.appliedColorScheme = colorScheme

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

    static func clamp(_ range: NSRange, to text: NSString) -> NSRange {
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
        let matches = TeleprompterParser.cueMatches(in: textView.text)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        for match in matches {
            storage.addAttributes(
                cueAttributes(for: match.color, isDarkMode: isDarkMode),
                range: match.contentRange
            )

            // The tag itself stays in the text but is given no glyphs to draw.
            for range in match.syntaxRanges {
                storage.addAttribute(.cueSyntax, value: true, range: range)
            }
        }
        storage.endEditing()

        textView.layoutManager.invalidateGlyphs(
            forCharacterRange: fullRange,
            changeInLength: 0,
            actualCharacterRange: nil
        )
        textView.layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)

        // Typing inside a capsule should stay in the capsule's color rather than
        // flashing plain until the next pass.
        let caret = textView.selectedRange.location
        let enclosing = matches.first { match in
            caret >= match.contentRange.location
                && caret <= match.contentRange.location + match.contentRange.length
        }
        textView.typingAttributes = enclosing
            .map { cueAttributes(for: $0.color, isDarkMode: isDarkMode) } ?? baseAttributes
    }

    private static func cueAttributes(for color: CueColor, isDarkMode: Bool) -> [NSAttributedString.Key: Any] {
        let uiColor = color.uiColor(isDarkMode: isDarkMode)
        return [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: uiColor,
            .cueCapsule: uiColor.withAlphaComponent(isDarkMode ? 0.22 : 0.15)
        ]
    }

    private static func baseAttributes(isDarkMode: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, NSLayoutManagerDelegate {
        var parent: CueTextEditor
        var appliedColorScheme: ColorScheme?
        weak var textView: UITextView?
        private var isAdjustingSelection = false

        /// Height of the cue bar that sits between the script and the keyboard.
        private static let cueBarHeight: CGFloat = 50

        init(parent: CueTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Re-highlight and push the text back to SwiftUI after an edit we made ourselves.
        func syncAfterEdit() {
            guard let textView else { return }
            let selection = textView.selectedRange
            CueTextEditor.applyHighlighting(to: textView, colorScheme: parent.colorScheme)
            textView.selectedRange = selection
            parent.text = textView.text
            parent.controller.syncActiveColor()
        }

        // MARK: Keyboard

        /// The editor ignores the keyboard's safe area — SwiftUI leaves a phantom gap
        /// behind when a UIKit responder resigns, which clipped the last lines — so the
        /// room for the keyboard is scroll inset, managed here and given back in full
        /// the moment the keyboard goes away.
        func startObservingKeyboard() {
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(keyboardWillHide),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        @objc private func keyboardWillChangeFrame(_ notification: Notification) {
            guard let textView,
                  let window = textView.window,
                  let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }

            let keyboard = window.convert(frame, from: nil)
            let editor = textView.convert(textView.bounds, to: window)
            let overlap = max(0, editor.maxY - keyboard.minY)

            setBottomInset(overlap > 0 ? overlap + Self.cueBarHeight : 0)
        }

        @objc private func keyboardWillHide() {
            setBottomInset(0)
        }

        private func setBottomInset(_ inset: CGFloat) {
            guard let textView, abs(textView.contentInset.bottom - inset) > 0.5 else { return }

            textView.contentInset.bottom = inset
            textView.verticalScrollIndicatorInsets.bottom = inset

            // Bring the line being written out from behind the keyboard.
            if textView.isFirstResponder {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }

        // MARK: Editing

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            CueTextEditor.applyHighlighting(to: textView, colorScheme: parent.colorScheme)
            textView.selectedRange = selection
            parent.text = textView.text
            parent.controller.syncActiveColor()
        }

        /// A cue reads as one word, so it deletes as one: a backspace that clips the
        /// hidden tag takes the whole capsule with it. Edits inside the cue text —
        /// typing over the placeholder, say — are left alone.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard range.length > 0 else { return true }

            var expanded = range
            for match in TeleprompterParser.cueMatches(in: textView.text)
            where match.syntaxRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                expanded = NSUnionRange(expanded, match.range)
            }
            guard expanded != range,
                  let start = textView.position(from: textView.beginningOfDocument, offset: expanded.location),
                  let end = textView.position(from: start, offset: expanded.length),
                  let textRange = textView.textRange(from: start, to: end) else { return true }

            // Going through `replace` rather than the storage keeps undo working. It
            // re-enters here with the full tag, which expands to itself and passes.
            textView.replace(textRange, withText: text)
            textView.selectedRange = NSRange(location: expanded.location + (text as NSString).length, length: 0)
            syncAfterEdit()
            return false
        }

        /// The tag has no glyphs, so the caret would otherwise stall on positions that
        /// look identical. Push it to the nearest edge the user can actually see.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isAdjustingSelection else { return }

            if textView.selectedRange.length == 0 {
                for match in TeleprompterParser.cueMatches(in: textView.text) {
                    guard let snapped = match.caretEscape(from: textView.selectedRange.location) else { continue }

                    isAdjustingSelection = true
                    textView.selectedRange = NSRange(location: snapped, length: 0)
                    isAdjustingSelection = false
                    break
                }
            }

            parent.controller.syncActiveColor()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !parent.isFocused else { return }
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            removeEmptyCues(in: textView)

            guard parent.isFocused else { return }
            parent.isFocused = false
        }

        /// A capsule the user emptied out and walked away from has nothing to say, on
        /// screen or in an export, so it goes when they leave the editor.
        private func removeEmptyCues(in textView: UITextView) {
            let empties = TeleprompterParser.cueMatches(in: textView.text)
                .filter { $0.content.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !empties.isEmpty else { return }

            let storage = textView.textStorage
            for match in empties.reversed() {
                var range = match.range

                // Don't leave a double space where the capsule used to be.
                let end = range.location + range.length
                if range.location > 0, end < storage.length,
                   storage.attributedSubstring(from: NSRange(location: range.location - 1, length: 1)).string == " ",
                   storage.attributedSubstring(from: NSRange(location: end, length: 1)).string == " " {
                    range = NSRange(location: range.location, length: range.length + 1)
                }
                storage.replaceCharacters(in: range, with: "")
            }

            textView.selectedRange = CueTextEditor.clamp(textView.selectedRange, to: textView.text as NSString)
            syncAfterEdit()
        }

        // MARK: NSLayoutManagerDelegate

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes: UnsafePointer<Int>,
            font: UIFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            guard let storage = layoutManager.textStorage else { return 0 }

            var properties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            var hidAny = false

            for offset in 0..<glyphRange.length {
                let characterIndex = characterIndexes[offset]
                guard characterIndex < storage.length,
                      storage.attribute(.cueSyntax, at: characterIndex, effectiveRange: nil) != nil else { continue }

                properties[offset].insert(.null)
                hidAny = true
            }
            guard hidAny else { return 0 }

            layoutManager.setGlyphs(
                glyphs,
                properties: &properties,
                characterIndexes: characterIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
            return glyphRange.length
        }
    }
}

// MARK: - Cue bar

/// Sits above the keyboard: add a capsule, and set its color.
struct CueBar: View {
    let activeColor: CueColor
    let isEditingCue: Bool
    let colorScheme: ColorScheme
    var onAddCue: () -> Void
    var onPickColor: (CueColor) -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAddCue) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Cue")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(activeColor.color(for: colorScheme))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(activeColor.color(for: colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.14))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add cue")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CueColor.allCases) { color in
                        Button {
                            onPickColor(color)
                        } label: {
                            Circle()
                                .fill(color.color(for: colorScheme))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            AppColors.textPrimary(for: colorScheme),
                                            lineWidth: color == activeColor ? 2 : 0
                                        )
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isEditingCue ? "Recolor cue \(color.displayName)" : "New cue color \(color.displayName)"
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            // Swatches slide under a soft edge instead of being sliced off.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

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
