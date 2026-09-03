import SwiftUI
import UIKit

/// The editor's scroll view. It keeps the caret clear of whatever covers the
/// bottom of the screen — the keyboard, and the cue bar riding above it — so the
/// line being typed stays visible.
final class CueTextView: UITextView {
    /// Height of the cue bar overlaying the bottom of the editor, in points.
    var bottomOverlayHeight: CGFloat = 0 {
        didSet {
            guard bottomOverlayHeight != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Breathing room left between the caret and whatever sits below it.
    private static let caretPadding: CGFloat = 8

    private var keyboardScreenFrame: CGRect = .null
    private var appliedBottomInset: CGFloat?
    private var lastBoundsHeight: CGFloat?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        observeKeyboard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeKeyboard()
    }

    private func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardFrameChanged),
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

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        keyboardScreenFrame = frame?.cgRectValue ?? .null
        setNeedsLayout()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardScreenFrame = .null
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let heightChanged = bounds.height != lastBoundsHeight
        lastBoundsHeight = bounds.height

        let inset = bottomOverlayHeight + keyboardOverlap()
        let insetChanged = inset != appliedBottomInset
        if insetChanged {
            appliedBottomInset = inset
            contentInset.bottom = inset
            verticalScrollIndicatorInsets.bottom = inset
        }

        // Opening the keyboard shrinks the editor, which can leave the caret
        // below the fold; follow it back into view.
        if heightChanged || insetChanged {
            scrollCaretIntoView()
        }
    }

    /// How much of the editor the keyboard covers. Usually nothing — SwiftUI
    /// already lifts the editor clear of it — but measuring means the caret stays
    /// visible even when it doesn't.
    private func keyboardOverlap() -> CGFloat {
        guard !keyboardScreenFrame.isNull, let window else { return 0 }

        let keyboard = convert(window.convert(keyboardScreenFrame, from: nil), from: window)
        guard keyboard.intersects(bounds) else { return 0 }
        return max(0, bounds.maxY - keyboard.minY)
    }

    /// Scroll so the caret sits inside the part of the editor nothing is covering.
    func scrollCaretIntoView() {
        guard isFirstResponder, let caret = selectedTextRange?.end else { return }

        let rect = caretRect(for: caret).insetBy(dx: 0, dy: -Self.caretPadding)
        guard rect.minY.isFinite, rect.maxY.isFinite else { return }

        let visibleTop = contentOffset.y + adjustedContentInset.top
        let visibleBottom = contentOffset.y + bounds.height - adjustedContentInset.bottom

        var target = contentOffset.y
        if rect.maxY > visibleBottom {
            target += rect.maxY - visibleBottom
        } else if rect.minY < visibleTop {
            target -= visibleTop - rect.minY
        } else {
            return
        }

        let lowest = -adjustedContentInset.top
        let highest = max(lowest, contentSize.height + adjustedContentInset.bottom - bounds.height)
        contentOffset.y = min(max(target, lowest), highest)
    }
}

/// Script editor that renders `[cue …]` tags in the cue color while you type, and
/// writes the brackets for you: pressing `[` drops in a whole empty cue with the
/// caret inside it, so a cue is never left half-open.
struct CueTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool
    let cueColor: CueColor
    let colorScheme: ColorScheme
    /// Height of the cue bar floating over the bottom of the editor, if it's showing.
    var bottomOverlayHeight: CGFloat = 0

    static let fontSize: CGFloat = 16

    func makeUIView(context: Context) -> CueTextView {
        let textView = CueTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.text = text
        Self.applyHighlighting(to: textView, cueColor: cueColor, colorScheme: colorScheme)
        return textView
    }

    func updateUIView(_ textView: CueTextView, context: Context) {
        context.coordinator.parent = self
        textView.bottomOverlayHeight = bottomOverlayHeight

        let styleChanged = context.coordinator.appliedColorScheme != colorScheme
            || context.coordinator.appliedCueColor != cueColor

        if textView.text != text {
            textView.text = text
            Self.applyHighlighting(to: textView, cueColor: cueColor, colorScheme: colorScheme)
        } else if styleChanged {
            Self.applyHighlighting(to: textView, cueColor: cueColor, colorScheme: colorScheme)
        }
        context.coordinator.appliedColorScheme = colorScheme
        context.coordinator.appliedCueColor = cueColor

        let clamped = Self.clamp(selectedRange, to: textView.text as NSString)
        if textView.selectedRange != clamped {
            textView.selectedRange = clamped
            textView.scrollCaretIntoView()
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

    static func applyHighlighting(to textView: UITextView, cueColor: CueColor, colorScheme: ColorScheme) {
        // Recoloring mid-composition would drop the in-progress marked text.
        guard textView.markedTextRange == nil else { return }

        let isDarkMode = colorScheme == .dark
        let baseAttributes = baseAttributes(isDarkMode: isDarkMode)
        let tagColor = cueColor.uiColor(isDarkMode: isDarkMode)
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        // Only closed tags are colored, so a cue being typed stays plain text
        // until its bracket lands.
        for match in TeleprompterParser.cueMatches(in: textView.text) {
            // The tag syntax stays visible — and editable — but recedes.
            storage.addAttributes([
                .foregroundColor: tagColor.withAlphaComponent(0.45),
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium)
            ], range: match.range)

            storage.addAttributes([
                .foregroundColor: tagColor,
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
        var appliedCueColor: CueColor?

        init(parent: CueTextEditor) {
            self.parent = parent
        }

        /// Writes both brackets on `[`, and takes them both back away again on the
        /// backspace that follows, so a `[` meant literally costs one extra keystroke
        /// instead of six.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "[", range.length == 0 {
                replace(
                    range,
                    with: TeleprompterParser.emptyCueTag,
                    caret: range.location + (TeleprompterParser.cueTagPrefix as NSString).length,
                    in: textView
                )
                return false
            }

            if text.isEmpty, range.length == 1, let emptyCue = emptyCueSurrounding(range, in: textView) {
                replace(emptyCue, with: "[", caret: emptyCue.location + 1, in: textView)
                return false
            }

            return true
        }

        /// The range of an untouched `[cue ]` the caret is sitting inside, if this
        /// backspace is the one deleting its trailing space. A cue with anything
        /// written in it deletes a character at a time like ordinary text.
        private func emptyCueSurrounding(_ range: NSRange, in textView: UITextView) -> NSRange? {
            let prefixLength = (TeleprompterParser.cueTagPrefix as NSString).length
            let tagLength = (TeleprompterParser.emptyCueTag as NSString).length
            let start = range.location - (prefixLength - 1)

            let full = textView.text as NSString
            guard start >= 0, start + tagLength <= full.length else { return nil }

            let candidate = NSRange(location: start, length: tagLength)
            guard full.substring(with: candidate) == TeleprompterParser.emptyCueTag else { return nil }
            return candidate
        }

        /// Edit the text ourselves, then run everything `textViewDidChange` would have.
        private func replace(_ range: NSRange, with replacement: String, caret: Int, in textView: UITextView) {
            // The keyboard has to be told about an edit it didn't make itself, or it
            // keeps autocorrecting against the text it still thinks is there.
            textView.inputDelegate?.textWillChange(textView)
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            CueTextEditor.applyHighlighting(
                to: textView,
                cueColor: parent.cueColor,
                colorScheme: parent.colorScheme
            )

            let selection = NSRange(location: caret, length: 0)
            textView.selectedRange = selection
            textView.inputDelegate?.textDidChange(textView)

            parent.text = textView.text
            parent.selectedRange = selection
            (textView as? CueTextView)?.scrollCaretIntoView()
        }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            CueTextEditor.applyHighlighting(
                to: textView,
                cueColor: parent.cueColor,
                colorScheme: parent.colorScheme
            )
            textView.selectedRange = selection

            parent.text = textView.text
            parent.selectedRange = selection

            // UITextView's own scroll-to-caret ignores the bottom inset, so the
            // last line would slide under the cue bar as it's typed.
            (textView as? CueTextView)?.scrollCaretIntoView()
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
    /// Insert an empty cue at `range`, adding the spaces needed so it doesn't
    /// collide with the surrounding words. Returns the caret position inside the
    /// tag, ready for the cue to be typed.
    func insertingEmptyCue(at range: NSRange) -> (text: String, caret: Int) {
        let nsText = self as NSString
        let location = min(max(range.location + range.length, 0), nsText.length)

        let previous = location > 0 ? nsText.substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < nsText.length ? nsText.substring(with: NSRange(location: location, length: 1)) : ""

        let needsLeadingSpace = !previous.isEmpty && previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let needsTrailingSpace = !next.isEmpty && next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil

        let leading = needsLeadingSpace ? " " : ""
        let insertion = leading + TeleprompterParser.emptyCueTag + (needsTrailingSpace ? " " : "")
        let updated = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
        let caret = location
            + (leading as NSString).length
            + (TeleprompterParser.cueTagPrefix as NSString).length

        return (updated, caret)
    }
}

// MARK: - Cue bar

/// The strip above the keyboard while a script is being written: one button to
/// drop a cue in at the caret, and one to get the keyboard out of the way.
struct CueBar: View {
    /// The bar's height. The editor keeps this much room clear at the bottom so
    /// the line being typed never hides behind it.
    static let height: CGFloat = 54

    let colorScheme: ColorScheme
    var onAddCue: () -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAddCue) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add Cue")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .glassedEffect(in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

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
        .frame(height: Self.height)
        .background(AppColors.background(for: colorScheme).opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary(for: colorScheme).opacity(0.15))
                .frame(height: 0.5)
        }
    }
}
