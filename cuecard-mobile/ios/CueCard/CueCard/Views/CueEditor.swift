import SwiftUI
import UIKit

/// The duration and curve the keyboard is moving with, so the text can travel with
/// it rather than jumping ahead.
private struct KeyboardAnimation {
    let duration: TimeInterval
    let options: UIView.AnimationOptions

    init(_ notification: Notification) {
        let info = notification.userInfo
        duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 7
        options = UIView.AnimationOptions(rawValue: UInt(curve) << 16)
    }
}

/// The editor's scroll view. It keeps the line being typed clear of the keyboard
/// and of the cue bar riding on top of it.
///
/// The editor ignores the keyboard's safe area, so SwiftUI never resizes it: the
/// gap SwiftUI leaves behind when a UIKit responder resigns would cut the bottom of
/// the script off, and its resize lands a frame after the keyboard notification, so
/// measuring here as well made the text jump too far and settle back. All the room
/// for the keyboard is scroll inset, and this view owns it.
final class CueTextView: UITextView {
    /// Height of the cue bar covering the bottom of the editor while the keyboard
    /// is up. It rides with the keyboard, so it only counts when the keyboard does.
    var keyboardOverlayHeight: CGFloat = 0 {
        didSet {
            guard keyboardOverlayHeight != oldValue else { return }
            updateBottomInset()
        }
    }

    /// Height of what floats over the bottom of the editor once the keyboard has
    /// gone — the timer and play controls — so the last line can scroll clear of
    /// them instead of resting underneath.
    var restingOverlayHeight: CGFloat = 0 {
        didSet {
            guard restingOverlayHeight != oldValue else { return }
            updateBottomInset()
        }
    }

    /// Breathing room left between the caret and whatever sits below it.
    private static let caretPadding: CGFloat = 8
    /// In a card, room for the rest of the card below the caret as well.
    private static let cardCaretPadding: CGFloat = 28

    private var keyboardScreenFrame: CGRect = .null
    private var appliedBottomInset: CGFloat?

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
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    /// A card's list only makes room for the keyboard once it is up, so the
    /// caret is brought clear of it then.
    @objc private func keyboardDidShow(_ notification: Notification) {
        guard !isScrollEnabled else { return }
        scrollCaretIntoView(animated: true)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        keyboardScreenFrame = frame?.cgRectValue ?? .null
        updateBottomInset(travellingWith: KeyboardAnimation(notification))
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardScreenFrame = .null
        updateBottomInset(travellingWith: KeyboardAnimation(notification))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBottomInset()
    }

    /// Keep clear whatever covers the bottom of the editor: the keyboard and the
    /// cue bar on top of it while it's up, the home controls once it's gone.
    private func updateBottomInset(travellingWith animation: KeyboardAnimation? = nil) {
        // A card's editor grows with its text and leaves scrolling to the list
        // it sits in.
        guard isScrollEnabled else { return }
        let overlap = keyboardOverlap()
        let inset = overlap > 0 ? overlap + keyboardOverlayHeight : restingOverlayHeight
        guard inset != appliedBottomInset else { return }
        appliedBottomInset = inset

        let apply = { [self] in
            contentInset.bottom = inset
            verticalScrollIndicatorInsets.bottom = inset

            // Bring the line being written out from behind the keyboard, and — as the
            // keyboard leaves — pull the text back down over the room it gave up,
            // which UIScrollView would otherwise leave blank until the next touch.
            scrollCaretIntoView()
            pullContentBackFromEnd()
        }

        if let animation {
            UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options, animations: apply)
        } else {
            apply()
        }
    }

    /// How much of the editor the keyboard covers.
    private func keyboardOverlap() -> CGFloat {
        guard !keyboardScreenFrame.isNull, let window else { return 0 }

        let keyboard = window.convert(keyboardScreenFrame, from: nil)
        let editor = convert(bounds, to: window)
        return max(0, editor.maxY - keyboard.minY)
    }

    /// Scroll so the caret sits inside the part of the editor nothing is covering.
    func scrollCaretIntoView(animated: Bool = false) {
        guard isFirstResponder, let caret = selectedTextRange?.end else { return }
        guard isScrollEnabled else {
            // After SwiftUI has grown the card to fit what was just typed.
            DispatchQueue.main.async { [weak self] in self?.scrollCaretIntoList(animated: animated) }
            return
        }

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

        setContentOffsetY(target)
    }

    /// A card's editor doesn't scroll, the list of cards does. Scroll that so
    /// the caret sits clear of the keyboard and the cue bar riding on it.
    private func scrollCaretIntoList(animated: Bool) {
        guard isFirstResponder, let caret = selectedTextRange?.end, let window,
              let list = enclosingScrollView else { return }

        let rect = convert(caretRect(for: caret), to: window)
            .insetBy(dx: 0, dy: -Self.cardCaretPadding)
        guard rect.minY.isFinite, rect.maxY.isFinite else { return }

        let listFrame = list.convert(list.bounds, to: window)
        var visibleBottom = listFrame.maxY - list.safeAreaInsets.bottom
        if !keyboardScreenFrame.isNull {
            let keyboard = window.convert(keyboardScreenFrame, from: nil)
            visibleBottom = min(visibleBottom, keyboard.minY)
        }
        visibleBottom -= keyboardOverlayHeight
        let visibleTop = listFrame.minY + list.safeAreaInsets.top

        var target = list.contentOffset.y
        if rect.maxY > visibleBottom {
            target += rect.maxY - visibleBottom
        } else if rect.minY < visibleTop {
            target -= visibleTop - rect.minY
        } else {
            return
        }

        let lowest = -list.adjustedContentInset.top
        let highest = max(lowest, list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height)
        let offset = min(max(target, lowest), highest)
        guard offset != list.contentOffset.y else { return }
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: offset), animated: animated)
    }

    /// The nearest scroll view this one sits in.
    private var enclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }

    /// Scroll back down to the end of the text if the content has been left past it.
    private func pullContentBackFromEnd() {
        // Leave a scroll the user is driving alone; the rubber band is theirs.
        guard !isTracking, !isDecelerating else { return }
        setContentOffsetY(contentOffset.y)
    }

    /// Scroll to `y`, clamped to the ends of the text.
    private func setContentOffsetY(_ y: CGFloat) {
        let lowest = -adjustedContentInset.top
        let highest = max(lowest, contentSize.height + adjustedContentInset.bottom - bounds.height)
        let offset = min(max(y, lowest), highest)
        guard offset != contentOffset.y else { return }
        contentOffset.y = offset
    }
}

/// A handle on the editor's text view, so the cue bar can insert at the caret.
///
/// Inserting through the text binding instead would rewrite the whole document,
/// which parks the caret at the end — the cue has to go in the same way typing
/// does, or it lands in the right place and the caret doesn't.
@MainActor
final class CueEditorController: ObservableObject {
    fileprivate weak var coordinator: CueTextEditor.Coordinator?

    /// Drop an empty cue at the caret and leave the caret inside it.
    func insertCue() {
        coordinator?.insertEmptyCue()
    }

    /// Select the whole script. Dragging a selection out to the end is awkward
    /// here: the editor runs on under the keyboard and the cue bar, so the edge
    /// that would scroll a drag along is out of reach.
    func selectAll() {
        coordinator?.selectAll()
    }
}

/// Script editor that renders `[cue …]` tags in the cue color while you type, and
/// writes the brackets for you: pressing `[` drops in a whole empty cue with the
/// caret inside it, so a cue is never left half-open — except inside a cue, where
/// there is nothing left for it to open.
///
/// A card's editor is given the card's limit, and whatever runs past it is
/// marked in red.
struct CueTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let controller: CueEditorController
    let cueColor: CueColor
    let colorScheme: ColorScheme
    /// The text size the script is set in, from Settings.
    let fontSize: CGFloat
    /// In a card, the characters it holds before the rest is marked.
    var cardLimit: Int?
    /// Sized to its text, without scrolling, for a card in a list of them.
    var growsWithText = false
    /// Height of the cue bar floating over the bottom of the editor, if it's showing.
    var keyboardOverlayHeight: CGFloat = 0
    /// Height of whatever floats over the bottom of the editor with the keyboard away.
    var restingOverlayHeight: CGFloat = 0
    /// How far down the script starts. More than `edgeFade` where the editor
    /// reaches up under the top bar and the fade starts inside it.
    var topInset: CGFloat = Self.edgeFade

    /// How far the script fades into the background at the top and bottom edges.
    /// The text starts and ends this far in, so no line sits inside a fade.
    static let edgeFade: CGFloat = 28

    func makeUIView(context: Context) -> CueTextView {
        let textView = CueTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        if growsWithText {
            textView.isScrollEnabled = false
            textView.textContainerInset = .zero
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        } else {
            textView.textContainerInset = UIEdgeInsets(top: topInset, left: 16, bottom: Self.edgeFade, right: 16)
            textView.alwaysBounceVertical = true
            textView.keyboardDismissMode = .interactive
            // The room under the top bar is in `topInset` already, and the
            // fade stands in for the bar's own edge effect.
            textView.contentInsetAdjustmentBehavior = .never
            if #available(iOS 26.0, *) {
                textView.topEdgeEffect.isHidden = true
            }
        }
        textView.text = text
        applyHighlighting(to: textView)
        return textView
    }

    func updateUIView(_ textView: CueTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = textView
        // With a card editor for every card, the cue bar writes into the one
        // being typed in.
        if controller.coordinator == nil || textView.isFirstResponder {
            controller.coordinator = context.coordinator
        }
        textView.keyboardOverlayHeight = keyboardOverlayHeight
        textView.restingOverlayHeight = restingOverlayHeight
        if !growsWithText, textView.textContainerInset.top != topInset {
            textView.textContainerInset.top = topInset
        }

        let styleChanged = context.coordinator.appliedColorScheme != colorScheme
            || context.coordinator.appliedCueColor != cueColor
            || context.coordinator.appliedFontSize != fontSize
            || context.coordinator.appliedCardLimit != cardLimit

        if textView.text != text {
            textView.text = text
            applyHighlighting(to: textView)
        } else if styleChanged {
            applyHighlighting(to: textView)
        }
        context.coordinator.appliedColorScheme = colorScheme
        context.coordinator.appliedCueColor = cueColor
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedCardLimit = cardLimit

        // SwiftUI's .focused() doesn't reach into a UIViewRepresentable, so drive
        // first responder status from the binding instead — but after this update
        // has finished. Becoming first responder calls the delegate straight back,
        // and writing the binding from inside SwiftUI's own update is what the
        // AttributeGraph cycles are made of.
        guard isFocused != textView.isFirstResponder else { return }
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }

            // Read the binding again — the intent may have changed while we waited.
            if coordinator.parent.isFocused {
                textView.becomeFirstResponder()
            } else {
                textView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        if controller.coordinator == nil {
            controller.coordinator = coordinator
        }
        return coordinator
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CueTextView, context: Context) -> CGSize? {
        guard growsWithText, let width = proposal.width, width.isFinite else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }

    // MARK: - Highlighting

    func applyHighlighting(to textView: UITextView) {
        Self.applyHighlighting(to: textView, cueColor: cueColor, colorScheme: colorScheme,
                               fontSize: fontSize, cardLimit: cardLimit)
    }

    static func applyHighlighting(to textView: UITextView, cueColor: CueColor, colorScheme: ColorScheme,
                                  fontSize: CGFloat, cardLimit: Int?) {
        // Recoloring mid-composition would drop the in-progress marked text.
        guard textView.markedTextRange == nil else { return }

        let isDarkMode = colorScheme == .dark
        let baseAttributes = baseAttributes(isDarkMode: isDarkMode, fontSize: fontSize)
        let tagColor = cueColor.uiColor(isDarkMode: isDarkMode)
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let cues = TeleprompterParser.cueMatches(in: textView.text)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)

        // Separators show in either mode, quieter than the words, so a script
        // written as cards reads as one in the teleprompter's editor too.
        for separator in CueCards.separatorRanges(in: textView.text) {
            storage.addAttributes([
                .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textSecondary : AppColors.UIColors.Light.textSecondary,
                .font: UIFont.systemFont(ofSize: fontSize * 0.8, weight: .bold)
            ], range: separator)
        }

        // Only closed tags are colored, so a cue being typed stays plain text
        // until its bracket lands.
        for match in cues {
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

        // What a card holds past its limit, marked so it's plain where the
        // card has to end and a new one begin.
        if let cardLimit {
            let red = isDarkMode ? AppColors.UIColors.Dark.red : AppColors.UIColors.Light.red
            let nsText = textView.text as NSString
            for card in CueCards.cardRanges(in: textView.text) {
                guard let overflow = CueCards.measure(card, in: nsText, cues: cues, limit: cardLimit).overflow else {
                    continue
                }
                storage.addAttributes([
                    .foregroundColor: red,
                    .backgroundColor: red.withAlphaComponent(0.14)
                ], range: overflow)
            }
        }
        storage.endEditing()

        textView.typingAttributes = baseAttributes
    }

    private static func baseAttributes(isDarkMode: Bool, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CueTextEditor
        weak var textView: CueTextView?
        var appliedColorScheme: ColorScheme?
        var appliedCueColor: CueColor?
        var appliedFontSize: CGFloat?
        var appliedCardLimit: Int?

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
                // Cues don't nest, and in here both brackets are already written,
                // so `[` has nothing left to do.
                guard TeleprompterParser.cueTag(containing: range.location, in: textView.text) == nil else {
                    return false
                }

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

        /// Write an empty cue in at the caret, as if it had been typed there.
        func insertEmptyCue() {
            guard let textView else { return }

            // Past the end of a selection, so a cue never eats the words it's next
            // to — and past the end of the cue the caret is in, since cues don't nest.
            var location = NSMaxRange(textView.selectedRange)
            if let enclosing = TeleprompterParser.cueTag(containing: location, in: textView.text) {
                location = NSMaxRange(enclosing.range)
            }
            let insertion = (textView.text as NSString).emptyCueInsertion(at: location)

            replace(
                NSRange(location: location, length: 0),
                with: insertion.text,
                caret: location + insertion.caretOffset,
                in: textView
            )

            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        func selectAll() {
            guard let textView else { return }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            textView.selectAll(nil)
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
            parent.applyHighlighting(to: textView)

            textView.selectedRange = NSRange(location: caret, length: 0)
            textView.inputDelegate?.textDidChange(textView)

            parent.text = textView.text
            (textView as? CueTextView)?.scrollCaretIntoView()
        }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            parent.applyHighlighting(to: textView)
            textView.selectedRange = selection

            parent.text = textView.text

            // UITextView's own scroll-to-caret ignores the bottom inset, so the
            // last line would slide under the cue bar as it's typed.
            (textView as? CueTextView)?.scrollCaretIntoView()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.controller.coordinator = self
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

extension NSString {
    /// The text to splice in for an empty cue at `location`, spaced so it doesn't
    /// collide with the words either side of it, and how far into that text the
    /// caret belongs — between the brackets, ready for the cue to be typed.
    func emptyCueInsertion(at location: Int) -> (text: String, caretOffset: Int) {
        let previous = location > 0 ? substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < length ? substring(with: NSRange(location: location, length: 1)) : ""

        let needsLeadingSpace = !previous.isEmpty && previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let needsTrailingSpace = !next.isEmpty && next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil

        let leading = needsLeadingSpace ? " " : ""
        let text = leading + TeleprompterParser.emptyCueTag + (needsTrailingSpace ? " " : "")
        let caretOffset = (leading as NSString).length
            + (TeleprompterParser.cueTagPrefix as NSString).length

        return (text, caretOffset)
    }
}

// MARK: - Cue bar

/// The strip above the keyboard while a script is being written: buttons to drop
/// a cue in at the caret and to select the whole script, and one to get the
/// keyboard out of the way.
struct CueBar: View {
    /// The bar's height. The editor keeps this much room clear at the bottom so
    /// the line being typed never hides behind it.
    static let height: CGFloat = 54

    let colorScheme: ColorScheme
    var onAddCue: () -> Void
    var onSelectAll: () -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Three buttons don't fit a small phone with their full names, so
            // the adds drop their verb when they have to.
            ViewThatFits(in: .horizontal) {
                buttons(short: false)
                buttons(short: true)
            }

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

    private func buttons(short: Bool) -> some View {
        HStack(spacing: 10) {
            addButton(short ? "Cue" : "Add Cue", accessibilityLabel: "Add Cue", action: onAddCue)

            Button(action: onSelectAll) {
                Text("Select All")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .glassedEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
    }

    private func addButton(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassedEffect(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
