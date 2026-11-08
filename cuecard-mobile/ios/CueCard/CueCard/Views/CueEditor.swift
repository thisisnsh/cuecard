import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// Keep the active line above the fade leading into the keyboard toolbar.
    private static let caretPadding: CGFloat = CueTextEditor.edgeFade + 8
    /// In a card, room for the rest of the card below the caret as well.
    private static let cardCaretPadding: CGFloat = 28

    private var keyboardScreenFrame: CGRect = .null
    private var appliedBottomInset: CGFloat?

    /// Bold and Italic — from the edit menu or ⌘B, ⌘I — write their markers
    /// into the script rather than styling it, which would be lost.
    var onToggleStyle: ((EmphasisStyle) -> Void)?
    /// Images pasted in, to keep and place at the caret.
    var onPasteImages: (([UIImage]) -> Void)?
    /// Script pasted in with images in it, copied from an editor here.
    var onPasteScript: ((String) -> Void)?

    override func toggleBoldface(_ sender: Any?) { onToggleStyle?(.bold) }
    override func toggleItalics(_ sender: Any?) { onToggleStyle?(.italic) }

    /// A script has no underline to write, so it's left out of the menu.
    /// An image can be pasted in as well as text.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
        if action == #selector(paste(_:)), isEditable, UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    /// An image on its own — copied from Photos, or with the link to where it
    /// came from — goes in as an image. Text copied here with images in it
    /// brings them along; any other text is pasted as UIKit pastes it.
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages, !pasteboard.hasStrings || pasteboard.hasURLs,
           let images = pasteboard.images, !images.isEmpty, let onPasteImages {
            onPasteImages(images)
            return
        }
        if let string = pasteboard.string, !TeleprompterParser.imageMatches(in: string).isEmpty,
           let onPasteScript {
            onPasteScript(string)
            return
        }
        super.paste(sender)
    }

    /// Copied with an image in it, the selection goes out as script, its
    /// images as `[image …]` tags, so pasting it back here brings them along.
    /// A lone image goes out as the picture too, for pasting anywhere else.
    override func copy(_ sender: Any?) {
        guard let selection = selectedImageText else {
            super.copy(sender)
            return
        }
        var item: [String: Any] = [UTType.utf8PlainText.identifier: ScriptImageAttachment.script(from: selection)]
        if selection.length == 1,
           let attachment = selection.attribute(.attachment, at: 0, effectiveRange: nil) as? ScriptImageAttachment,
           let data = ScriptImages.data(named: attachment.name) {
            let type = UTType(filenameExtension: (attachment.name as NSString).pathExtension) ?? .jpeg
            item[type.identifier] = data
        }
        UIPasteboard.general.items = [item]
    }

    override func cut(_ sender: Any?) {
        guard selectedImageText != nil else {
            super.cut(sender)
            return
        }
        copy(sender)
        deleteBackward()
    }

    /// The selection, if there's an image in it.
    private var selectedImageText: NSAttributedString? {
        let selection = selectedRange
        guard selection.length > 0, NSMaxRange(selection) <= textStorage.length else { return nil }
        let text = textStorage.attributedSubstring(from: selection)
        var hasImage = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value is ScriptImageAttachment {
                hasImage = true
                stop.pointee = true
            }
        }
        return hasImage ? text : nil
    }

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

    private var laidOutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new width lays every line out again, images to their new size —
        // once UIKit has given the text its new width, or it's thrown away.
        if textContainer.size.width != laidOutWidth {
            laidOutWidth = textContainer.size.width
            layOutWholeText()
        }
        updateBottomInset()
    }

    /// Lay out the whole script, not just what's on screen. TextKit 2 guesses
    /// at the height of lines it hasn't laid out yet, and guesses an image
    /// as one line of text: the script came out shorter than it is, and
    /// grew under the finger as it scrolled.
    func layOutWholeText() {
        guard isScrollEnabled, let textLayoutManager else { return }
        let document = textLayoutManager.documentRange
        textLayoutManager.ensureLayout(for: document)
        textLayoutManager.enumerateTextLayoutFragments(from: document.location, options: [.ensuresLayout]) { _ in true }
        textLayoutManager.textViewportLayoutController.layoutViewport()
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
        // From the frame, not the bounds: the bounds move with the scroll, and
        // a scroll between pixels made the overlap waver in its last digits.
        let editor = superview?.convert(frame, to: window) ?? convert(bounds, to: window)
        // Whole pixels, so a sliver of rounding never reads as the keyboard moving.
        let scale = window.screen.scale
        return max(0, ((editor.maxY - keyboard.minY) * scale).rounded() / scale)
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
    func setContentOffsetY(_ y: CGFloat) {
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

    /// Drop a new `[cue]` at the caret with its text selected to type over.
    func insertCue() {
        coordinator?.insertNewCue()
    }

    /// Drop an `[anchor]` at the caret, for the teleprompter to jump to.
    func insertAnchor() {
        coordinator?.insertAnchor()
    }

    /// Bold or italicize the selection — or the word at the caret —
    /// or take that style back off if it has it.
    func toggle(_ style: EmphasisStyle) {
        coordinator?.toggle(style)
    }

    /// The editor showing a spinner for images still on their way in.
    private weak var loadingCoordinator: CueTextEditor.Coordinator?

    /// Show a spinner on the line images will go on, until they're inserted.
    func beginAddingImages() {
        loadingCoordinator = coordinator
        coordinator?.showImageProgress()
    }

    /// Place images from the store at the caret, each on a line of its own.
    func insertImages(_ names: [String]) {
        loadingCoordinator?.hideImageProgress()
        loadingCoordinator = nil
        coordinator?.insertImages(names)
    }
}

/// Script editor that renders `[…]` cues in the cue color while you type, and
/// writes the brackets for you: pressing `[` drops in a whole empty cue with the
/// caret inside it, so a cue is never left half-open — except inside a cue, where
/// there is nothing left for it to open.
///
/// An `[image …]` tag shows as the image itself. The text view holds a
/// `ScriptImageAttachment` there, and writes the tag back into the script.
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
    /// Suggestions being reviewed, shown in the text as they'd change it.
    /// The text can't be typed in meanwhile; a tap on one offers to accept
    /// or reject it.
    var suggestionMarks: SuggestionMarks?

    /// How far the script fades into the background at the top and bottom edges.
    /// The text starts and ends this far in, so no line sits inside a fade.
    static let edgeFade: CGFloat = 28

    /// The tallest an image is shown while writing: enough to tell what it
    /// is, without pushing the words around it out of view.
    var imageMaxHeight: CGFloat { growsWithText ? 200 : 260 }

    func makeUIView(context: Context) -> CueTextView {
        let textView = CueTextView()
        textView.delegate = context.coordinator
        // Puts Bold and Italic in the edit menu; they write markers.
        textView.allowsEditingTextAttributes = true
        textView.onToggleStyle = { [weak coordinator = context.coordinator] in coordinator?.toggle($0) }
        textView.onPasteImages = { [weak coordinator = context.coordinator] in coordinator?.pasteImages($0) }
        textView.onPasteScript = { [weak coordinator = context.coordinator] in coordinator?.pasteScript($0) }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tap.isEnabled = false
        textView.addGestureRecognizer(tap)
        context.coordinator.suggestionTap = tap
        let menu = UIEditMenuInteraction(delegate: context.coordinator)
        textView.addInteraction(menu)
        context.coordinator.suggestionMenu = menu
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
        textView.attributedText = ScriptImageAttachment.editorText(for: text, maxHeight: imageMaxHeight)
        applyHighlighting(to: textView)
        textView.layOutWholeText()
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

        let isReviewing = suggestionMarks != nil
        let wasReviewing = context.coordinator.appliedSuggestions != nil
        if textView.isEditable == isReviewing { textView.isEditable = !isReviewing }
        // No selecting either, so a tap only ever picks a suggestion.
        if textView.isSelectable == isReviewing { textView.isSelectable = !isReviewing }
        context.coordinator.suggestionTap?.isEnabled = isReviewing
        if !isReviewing, wasReviewing { context.coordinator.suggestionMenu?.dismissMenu() }

        let styleChanged = context.coordinator.appliedColorScheme != colorScheme
            || context.coordinator.appliedCueColor != cueColor
            || context.coordinator.appliedFontSize != fontSize
            || context.coordinator.appliedCardLimit != cardLimit
            || context.coordinator.appliedSuggestions != suggestionMarks?.suggestions
            || context.coordinator.appliedFocus != suggestionMarks?.focused

        // The suggestions shown in the text come and go as they're decided
        // on; the script stays where it's scrolled to.
        let scrollY = textView.contentOffset.y
        let script = ScriptImageAttachment.script(from: textView.textStorage)
        if script != text {
            // A suggestion taken in is changed in place, which keeps the
            // images as they are.
            if !(isReviewing && Self.splice(textView.textStorage, from: script, to: text)) {
                textView.attributedText = ScriptImageAttachment.editorText(for: text, maxHeight: imageMaxHeight)
            }
            applyHighlighting(to: textView)
            textView.layOutWholeText()
        } else if styleChanged {
            applyHighlighting(to: textView)
            textView.layOutWholeText()
        }
        if isReviewing || wasReviewing, script != text || styleChanged {
            textView.setContentOffsetY(scrollY)
        }
        context.coordinator.appliedColorScheme = colorScheme
        context.coordinator.appliedCueColor = cueColor
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedCardLimit = cardLimit
        context.coordinator.appliedSuggestions = suggestionMarks?.suggestions
        context.coordinator.appliedFocus = suggestionMarks?.focused
        textView.accessibilityCustomActions = suggestionMarks.map(Self.accessibilityActions)

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

    /// Styles the script, and while reviewing, shows each suggestion in it.
    /// Whatever was shown for the last ones is taken out first.
    func applyHighlighting(to textView: UITextView) {
        // Recoloring mid-composition would drop the in-progress marked text.
        guard textView.markedTextRange == nil else { return }
        Self.removeSuggestionPreviews(from: textView.textStorage)
        Self.applyHighlighting(to: textView, cueColor: cueColor, colorScheme: colorScheme,
                               fontSize: fontSize, cardLimit: cardLimit)
        if let suggestionMarks {
            Self.showSuggestions(suggestionMarks, in: textView, cueColor: cueColor,
                                 colorScheme: colorScheme, fontSize: fontSize)
        }
    }

    /// Make the change from `old` to `new` where it happened in the editor's
    /// text, rather than setting the whole text again, so the images in it
    /// stay as they are. False, with nothing changed, where it touches one.
    static func splice(_ storage: NSTextStorage, from old: String, to new: String) -> Bool {
        let a = old as NSString
        let b = new as NSString
        let shortest = min(a.length, b.length)
        var prefix = 0
        while prefix < shortest, a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix,
              a.character(at: a.length - 1 - suffix) == b.character(at: b.length - 1 - suffix) { suffix += 1 }
        let changed = NSRange(location: prefix, length: a.length - prefix - suffix)
        let replacement = b.substring(with: NSRange(location: prefix, length: b.length - prefix - suffix))

        let touchesImage = TeleprompterParser.imageMatches(in: old).contains {
            NSIntersectionRange($0.range, changed).length > 0
                || ($0.range.location < changed.location && changed.location < NSMaxRange($0.range))
        }
        guard !touchesImage, TeleprompterParser.imageMatches(in: replacement).isEmpty,
              !replacement.contains(CueCards.imageCharacter) else { return false }
        removeSuggestionPreviews(from: storage)
        storage.replaceCharacters(in: editorRange(for: changed, in: old), with: replacement)
        return true
    }

    /// Where `range` of the script is in the editor's text, which holds each
    /// `[image …]` tag as a single character.
    static func editorRange(for range: NSRange, in script: String) -> NSRange {
        var location = range.location
        for image in TeleprompterParser.imageMatches(in: script) where NSMaxRange(image.range) <= range.location {
            location -= image.range.length - 1
        }
        return NSRange(location: location, length: range.length)
    }

    /// Styles the script as it reads: cues apart from the words, and emphasis
    /// applied with its markers left showing, quieter, so they can be edited.
    static func applyHighlighting(to textView: UITextView, cueColor: CueColor, colorScheme: ColorScheme,
                                  fontSize: CGFloat, cardLimit: Int?) {
        // Recoloring mid-composition would drop the in-progress marked text.
        guard textView.markedTextRange == nil else { return }

        let isDarkMode = colorScheme == .dark
        let baseAttributes = baseAttributes(isDarkMode: isDarkMode, fontSize: fontSize,
                                            isWide: textView.text.hasWideScript)
        let secondary = isDarkMode ? AppColors.UIColors.Dark.textSecondary : AppColors.UIColors.Light.textSecondary
        let tagColor = cueColor.uiColor(isDarkMode: isDarkMode)
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let cues = TeleprompterParser.cueMatches(in: textView.text)
        let emphases = RichText.emphases(in: textView.text, skipping: cues.map(\.range))

        // Restyling the text would take its images out with everything else.
        var images: [(range: NSRange, attachment: NSTextAttachment)] = []
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            if let attachment = value as? NSTextAttachment { images.append((range, attachment)) }
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)
        for image in images {
            storage.addAttribute(.attachment, value: image.attachment, range: image.range)
        }

        // Separators show in either mode, quieter than the words, so a script
        // written as cards reads as one in the teleprompter's editor too.
        for tag in CueCards.separatorRanges(in: textView.text) {
            storage.addAttributes([
                .foregroundColor: secondary,
                .font: UIFont.systemFont(ofSize: fontSize * 0.8, weight: .bold)
            ], range: tag)
        }

        // Anchors are set like cues, in grey rather than the cue color: marks
        // in the script, not words of it.
        let anchors = TeleprompterParser.anchorRanges(in: textView.text)
        for tag in anchors {
            storage.addAttributes([
                .foregroundColor: secondary.withAlphaComponent(0.45),
                .font: UIFont.cue(ofSize: fontSize * 0.85, weight: .medium)
            ], range: tag)

            storage.addAttributes([
                .foregroundColor: secondary,
                .font: UIFont.cue(ofSize: fontSize * 0.85)
            ], range: NSRange(location: tag.location + 1, length: tag.length - 2))
        }

        // Each stretch takes every style written around it; an emphasis still
        // open shows its style already, as far as it has been typed.
        if !emphases.isEmpty {
            var styles = [EmphasisStyle](repeating: [], count: fullRange.length)
            for emphasis in emphases {
                for index in Range(emphasis.content)! { styles[index].formUnion(emphasis.style) }
            }
            var start = 0
            while start < styles.count {
                var end = start + 1
                while end < styles.count, styles[end] == styles[start] { end += 1 }
                let style = styles[start]
                if !style.isEmpty {
                    let range = NSRange(location: start, length: end - start)
                    storage.addAttribute(.font, value: UIFont.script(ofSize: fontSize, style: style), range: range)
                }
                start = end
            }

            for emphasis in emphases {
                for marker in [emphasis.open, emphasis.close].compactMap({ $0 }) {
                    storage.addAttribute(.foregroundColor, value: secondary, range: marker)
                }
            }
        }

        // Only closed tags are colored, so a cue being typed stays plain text
        // until its bracket lands. Cues are set smaller and narrower than the
        // script, so they never read as part of it.
        for match in cues {
            // The tag syntax stays visible — and editable — but recedes.
            storage.addAttributes([
                .foregroundColor: tagColor.withAlphaComponent(0.45),
                .font: UIFont.cue(ofSize: fontSize * 0.85, weight: .medium)
            ], range: match.range)

            storage.addAttributes([
                .foregroundColor: tagColor,
                .font: UIFont.cue(ofSize: fontSize * 0.85)
            ], range: match.contentRange)
        }

        // What a card holds past its limit, marked so it's plain where the
        // card has to end and a new one begin.
        if let cardLimit {
            let red = isDarkMode ? AppColors.UIColors.Dark.red : AppColors.UIColors.Light.red
            let nsText = textView.text as NSString
            let markers = emphases.filter(\.isClosed).flatMap { [$0.open, $0.close!] }
            for card in CueCards.cardRanges(in: textView.text) {
                guard let overflow = CueCards.measure(card, in: nsText, cues: cues, markers: markers,
                                                      anchors: anchors, limit: cardLimit).overflow else {
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

    // MARK: - Suggestions in the text

    /// Each suggestion shown where it is, as it would change the script,
    /// tinted so it stands out from the script itself: a misspelling struck
    /// through with the fix or rewrite after it, missing words in green, a cue or an anchor faint where it would
    /// go, a line break as a return mark, words to emphasize already set that
    /// way. What's shown that isn't in the script is marked as a preview, so
    /// it's never read back as part of it. The one tapped is tinted deeper
    /// and underlined.
    static func showSuggestions(_ marks: SuggestionMarks, in textView: UITextView, cueColor: CueColor,
                                colorScheme: ColorScheme, fontSize: CGFloat) {
        let storage = textView.textStorage
        let script = ScriptImageAttachment.script(from: storage)
        let isDarkMode = colorScheme == .dark
        let base = baseAttributes(isDarkMode: isDarkMode, fontSize: fontSize, isWide: textView.text.hasWideScript)
        let tint = isDarkMode ? AppColors.UIColors.Dark.purple : AppColors.UIColors.Light.purple
        let green = isDarkMode ? AppColors.UIColors.Dark.green : AppColors.UIColors.Light.green
        let red = isDarkMode ? AppColors.UIColors.Dark.red : AppColors.UIColors.Light.red
        let secondary = isDarkMode ? AppColors.UIColors.Dark.textSecondary : AppColors.UIColors.Light.textSecondary
        let tagColor = cueColor.uiColor(isDarkMode: isDarkMode)
        let cueFont = UIFont.cue(ofSize: fontSize * 0.85)

        // Back to front, so putting a preview in leaves the ones still to
        // come where they are. Of two at the same spot, the longer goes
        // first, so a cue ending a sentence lands ahead of a break after it.
        let ordered = marks.suggestions.sorted {
            ($0.range.location, $0.range.length) > ($1.range.location, $1.range.length)
        }

        storage.beginEditing()
        for suggestion in ordered {
            let range = editorRange(for: suggestion.range, in: script)
            guard NSMaxRange(range) <= storage.length else { continue }
            let id = suggestion.id.uuidString
            let isFocused = suggestion.id == marks.focused
            var mark: [NSAttributedString.Key: Any] = [
                .cueSuggestion: id,
                .backgroundColor: tint.withAlphaComponent(isFocused ? 0.3 : 0.12)
            ]
            if isFocused {
                mark[.underlineStyle] = NSUnderlineStyle.thick.rawValue
                mark[.underlineColor] = tint
            }

            let preview = NSMutableAttributedString()
            var previewLocation = range.location
            /// Set like the script, in its own font and color.
            func addPreview(_ text: String, _ attributes: [NSAttributedString.Key: Any]) {
                preview.append(NSAttributedString(string: text, attributes: base.merging(attributes) { $1 }))
            }

            switch suggestion.kind {
            case .spelling, .missingWords, .rewrite:
                // Words only put in bring their own space; a fix sits a
                // little apart from the words it replaces.
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: red,
                    .foregroundColor: red
                ], range: range)
                previewLocation = NSMaxRange(range)
                addPreview((range.length > 0 ? "\u{2009}" : "") + suggestion.replacement,
                           [.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: green])

            case .bold, .italic:
                storage.addAttributes([
                    .font: UIFont.script(ofSize: fontSize, style: suggestion.kind == .bold ? .bold : .italic),
                    .foregroundColor: green
                ], range: range)

            case .cue:
                addPreview(suggestion.replacement, [.font: cueFont, .foregroundColor: tagColor])

            case .anchor, .lineBreak:
                let original = suggestion.original as NSString
                let replacement = suggestion.replacement as NSString
                if suggestion.replacement.hasPrefix("\n") {
                    // A new paragraph from these words on: a return mark where
                    // the line would break, past the space it takes the place of.
                    var leading = 0
                    while leading < original.length, original.character(at: leading) == 0x20 { leading += 1 }
                    previewLocation = range.location + leading
                    addPreview("\u{21B5} ", [.font: UIFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: green])
                    if suggestion.kind == .anchor {
                        addPreview(TeleprompterParser.anchorTag + " ", [.font: cueFont, .foregroundColor: secondary])
                    }
                } else if replacement.length > original.length, suggestion.replacement.hasSuffix(suggestion.original) {
                    // An anchor at the start of a line: put in ahead of the words.
                    addPreview(replacement.substring(to: replacement.length - original.length),
                               [.font: cueFont, .foregroundColor: secondary])
                }
            }

            if range.length > 0 { storage.addAttributes(mark, range: range) }
            if preview.length > 0 {
                let whole = NSRange(location: 0, length: preview.length)
                preview.addAttributes(mark, range: whole)
                preview.addAttribute(.cueSuggestionPreview, value: id, range: whole)
                storage.insert(preview, at: previewLocation)
            }
        }
        storage.endEditing()
    }

    /// With VoiceOver, which can't tap on a suggestion in the text, Accept
    /// and Reject for each one from the editor's actions.
    static func accessibilityActions(for marks: SuggestionMarks) -> [UIAccessibilityCustomAction] {
        marks.suggestions.flatMap { suggestion -> [UIAccessibilityCustomAction] in
            let change = suggestion.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            let about = "\(suggestion.kind.actionName), \(change.isEmpty ? suggestion.original : change)"
            return [
                UIAccessibilityCustomAction(name: "\(String(localized: "Accept")): \(about)") { _ in
                    marks.onAccept(suggestion.id)
                    return true
                },
                UIAccessibilityCustomAction(name: "\(String(localized: "Reject")): \(about)") { _ in
                    marks.onReject(suggestion.id)
                    return true
                }
            ]
        }
    }

    /// Takes out everything shown for suggestions that isn't in the script.
    static func removeSuggestionPreviews(from text: NSMutableAttributedString) {
        let ranges = text.suggestionPreviewRanges
        guard !ranges.isEmpty else { return }
        text.beginEditing()
        for range in ranges.reversed() { text.deleteCharacters(in: range) }
        text.endEditing()
    }

    /// Typing takes these too, so text still being composed is set like the
    /// rest before it's styled.
    private static func baseAttributes(isDarkMode: Bool, fontSize: CGFloat,
                                       isWide: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.script(ofSize: fontSize),
            .paragraphStyle: NSParagraphStyle.script(ofSize: fontSize, isWide: isWide),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
        var parent: CueTextEditor
        weak var textView: CueTextView?
        var appliedColorScheme: ColorScheme?
        var appliedCueColor: CueColor?
        var appliedFontSize: CGFloat?
        var appliedCardLimit: Int?
        var appliedSuggestions: [ScriptSuggestion]?
        var appliedFocus: ScriptSuggestion.ID?
        weak var suggestionTap: UITapGestureRecognizer?
        weak var suggestionMenu: UIEditMenuInteraction?

        init(parent: CueTextEditor) {
            self.parent = parent
        }

        /// Writes both brackets on `[`, and takes the closing one back away again
        /// on the backspace that follows, so a `[` meant literally costs one extra
        /// keystroke.
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

        /// Where a tag goes in at the caret: past the end of a selection, so it
        /// never eats the words it's next to — and past the end of the cue the
        /// caret is in, since nothing goes inside a cue.
        private func tagLocation(in textView: UITextView) -> Int {
            let location = NSMaxRange(textView.selectedRange)
            if let enclosing = TeleprompterParser.cueTag(containing: location, in: textView.text) {
                return NSMaxRange(enclosing.range)
            }
            return location
        }

        /// Write a new cue in at the caret, as if it had been typed there, with
        /// its placeholder text selected so typing replaces it.
        func insertNewCue() {
            guard let textView else { return }

            let location = tagLocation(in: textView)
            let insertion = (textView.text as NSString).newCueInsertion(at: location)

            replace(
                NSRange(location: location, length: 0),
                with: insertion.text,
                selecting: NSRange(location: location + insertion.placeholder.location,
                                   length: insertion.placeholder.length),
                in: textView
            )

            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        /// Write an anchor in at the caret, with the caret left after it.
        func insertAnchor() {
            guard let textView else { return }

            let location = tagLocation(in: textView)
            let insertion = (textView.text as NSString).spacedInsertion(of: TeleprompterParser.anchorTag, at: location)

            replace(
                NSRange(location: location, length: 0),
                with: insertion.text,
                caret: location + (insertion.text as NSString).length,
                in: textView
            )

            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        /// The range of an untouched `[]` the caret is sitting inside, if this
        /// backspace is the one deleting its opening bracket. A cue with anything
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
            replace(range, with: replacement, selecting: NSRange(location: caret, length: 0), in: textView)
        }

        private func replace(_ range: NSRange, with replacement: String, selecting selection: NSRange,
                             in textView: UITextView) {
            replace(range, with: NSAttributedString(string: replacement), selecting: selection, in: textView)
        }

        private func replace(_ range: NSRange, with replacement: NSAttributedString, selecting selection: NSRange,
                             in textView: UITextView) {
            // The keyboard has to be told about an edit it didn't make itself, or it
            // keeps autocorrecting against the text it still thinks is there.
            textView.inputDelegate?.textWillChange(textView)
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = selection
            parent.applyHighlighting(to: textView)
            textView.inputDelegate?.textDidChange(textView)

            parent.text = ScriptImageAttachment.script(from: textView.textStorage)
            (textView as? CueTextView)?.layOutWholeText()
            (textView as? CueTextView)?.scrollCaretIntoView()
        }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            adoptPastedImages(in: textView)
            parent.applyHighlighting(to: textView)
            textView.selectedRange = selection

            parent.text = ScriptImageAttachment.script(from: textView.textStorage)

            // UITextView's own scroll-to-caret ignores the bottom inset, so the
            // last line would slide under the cue bar as it's typed.
            (textView as? CueTextView)?.layOutWholeText()
            (textView as? CueTextView)?.scrollCaretIntoView()
        }

        /// Wrap the selection — or the word at the caret — in `style`'s
        /// Markdown, or unwrap it if it's already set that way. With no word
        /// at the caret, the markers go in with the caret between them.
        func toggle(_ style: EmphasisStyle) {
            guard let textView, textView.markedTextRange == nil else { return }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }

            let text = textView.text as NSString
            let selection = textView.selectedRange
            let cues = TeleprompterParser.cueMatches(in: textView.text)
            let styled = RichText.emphases(in: textView.text, skipping: cues.map(\.range))
                .filter { $0.isClosed && $0.style == style }

            // Already set that way: take the markers back off.
            if let existing = styled.first(where: { $0.isAround(selection) }) {
                let content = text.substring(with: existing.content)
                let shifted = NSRange(location: max(existing.content.location, selection.location) - existing.open.length,
                                      length: min(selection.length, existing.content.length))
                replace(existing.range, with: content, selecting: shifted, in: textView)
                return
            }

            var target = selection.length > 0 ? selection : wordRange(at: selection.location, in: textView)
            target = text.trimmingWhitespace(in: target)
            let marker = style.marker
            let markerLength = (marker as NSString).length

            guard target.length > 0 else {
                // Nothing to wrap: open and close it at the caret, ready to type into.
                replace(selection, with: marker + marker,
                        selecting: NSRange(location: selection.location + markerLength, length: 0), in: textView)
                return
            }

            // Cues are drawn apart from the script and take no emphasis, and
            // emphasis doesn't run across lines.
            guard !cues.contains(where: { NSIntersectionRange($0.range, target).length > 0 }),
                  text.substring(with: target).rangeOfCharacter(from: .newlines) == nil else { return }

            // Partly set that way already: take that emphasis in and set the lot.
            let overlapping = styled.filter { NSIntersectionRange($0.range, target).length > 0 }
            let span = overlapping.reduce(target) { NSUnionRange($0, $1.range) }
            var inner = text.substring(with: span) as NSString
            for emphasis in overlapping.sorted(by: { $0.open.location > $1.open.location }) {
                let close = emphasis.close!
                inner = inner.replacingCharacters(
                    in: NSRange(location: close.location - span.location, length: close.length), with: ""
                ) as NSString
                inner = inner.replacingCharacters(
                    in: NSRange(location: emphasis.open.location - span.location, length: emphasis.open.length), with: ""
                ) as NSString
            }

            // A selection stays on the words; a caret at the end of its word
            // carries on after the closing marker, ready for plain text.
            let wrapped = marker + (inner as String) + marker
            let caret = selection.location >= NSMaxRange(target)
                ? span.location + (wrapped as NSString).length
                : selection.location + markerLength
            replace(span, with: wrapped,
                    selecting: selection.length > 0
                        ? NSRange(location: span.location + markerLength, length: inner.length)
                        : NSRange(location: caret, length: 0),
                    in: textView)
        }

        // MARK: Suggestions

        /// A tap on a suggestion while they're open offers Accept and Reject
        /// right above it. A tap anywhere else puts that away.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let textView, let marks = parent.suggestionMarks else { return }
            let point = gesture.location(in: textView)
            guard let id = suggestion(at: point, in: textView) else {
                suggestionMenu?.dismissMenu()
                return
            }
            marks.onFocus(id)
            suggestionMenu?.presentEditMenu(with: UIEditMenuConfiguration(identifier: id.uuidString as NSString,
                                                                          sourcePoint: point))
        }

        /// The suggestion drawn right where `point` is, if there is one.
        private func suggestion(at point: CGPoint, in textView: UITextView) -> ScriptSuggestion.ID? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            let storage = textView.textStorage
            // The closest spot is between two characters: either can be the one tapped.
            for index in [offset, offset - 1] where index >= 0 && index < storage.length {
                guard let id = storage.attribute(.cueSuggestion, at: index, effectiveRange: nil) as? String,
                      let range = textRange(NSRange(location: index, length: 1), in: textView),
                      textView.firstRect(for: range).insetBy(dx: -8, dy: -6).contains(point) else { continue }
                return UUID(uuidString: id)
            }
            return nil
        }

        private func textRange(_ range: NSRange, in textView: UITextView) -> UITextRange? {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length) else { return nil }
            return textView.textRange(from: start, to: end)
        }

        private func suggestionID(of configuration: UIEditMenuConfiguration) -> ScriptSuggestion.ID? {
            (configuration.identifier as? NSString).flatMap { UUID(uuidString: $0 as String) }
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let id = suggestionID(of: configuration) else { return nil }
            let accept = UIAction(title: String(localized: "Accept"), image: UIImage(systemName: "checkmark")) { [weak self] _ in
                self?.parent.suggestionMarks?.onAccept(id)
            }
            let reject = UIAction(title: String(localized: "Reject"), image: UIImage(systemName: "xmark")) { [weak self] _ in
                self?.parent.suggestionMarks?.onReject(id)
            }
            return UIMenu(children: [accept, reject])
        }

        /// Above the whole suggestion, not just where it was tapped.
        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
            guard let textView, let id = suggestionID(of: configuration)?.uuidString else { return .null }
            let storage = textView.textStorage
            var rect = CGRect.null
            storage.enumerateAttribute(.cueSuggestion, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value as? String == id, let textRange = textRange(range, in: textView) else { return }
                rect = rect.union(textView.firstRect(for: textRange))
            }
            return rect
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 willDismissMenuFor configuration: UIEditMenuConfiguration,
                                 animator: any UIEditMenuInteractionAnimating) {
            guard let id = suggestionID(of: configuration) else { return }
            parent.suggestionMarks?.onUnfocus(id)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Images

        /// Place images from the store after the selection — or after the cue
        /// the caret is in — each on a line of its own, and leave the caret on
        /// the line after them.
        func insertImages(_ names: [String]) {
            guard let textView, !names.isEmpty, textView.markedTextRange == nil else { return }

            let text = textView.text as NSString
            let location = imageLocation(in: textView)
            let newline = NSAttributedString(string: "\n")
            let insertion = NSMutableAttributedString()
            if location > 0, !isNewline(text.character(at: location - 1)) {
                insertion.append(newline)
            }
            for (index, name) in names.enumerated() {
                if index > 0 { insertion.append(newline) }
                insertion.append(NSAttributedString(
                    attachment: ScriptImageAttachment(name: name, maxHeight: parent.imageMaxHeight)))
            }
            // A line break already there does for the one after the images.
            let endsLine = location < text.length && isNewline(text.character(at: location))
            if !endsLine { insertion.append(newline) }
            let caret = location + insertion.length + (endsLine ? 1 : 0)

            replace(NSRange(location: location, length: 0), with: insertion,
                    selecting: NSRange(location: caret, length: 0), in: textView)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        /// Where images go: after the selection, or after the cue the caret is in.
        private func imageLocation(in textView: UITextView) -> Int {
            let location = NSMaxRange(textView.selectedRange)
            if let enclosing = TeleprompterParser.cueTag(containing: location, in: textView.text) {
                return NSMaxRange(enclosing.range)
            }
            return location
        }

        private var imageProgress: UIActivityIndicatorView?

        /// A small spinner at the start of the line images are on their way
        /// to — the line below, when the caret is partway along one.
        func showImageProgress() {
            guard let textView, imageProgress == nil else { return }
            let location = imageLocation(in: textView)
            guard let position = textView.position(from: textView.beginningOfDocument, offset: location) else { return }

            let caret = textView.caretRect(for: position)
            let text = textView.text as NSString
            let startsLine = location == 0 || isNewline(text.character(at: location - 1))
            let lineHeight = UIFont.script(ofSize: parent.fontSize).lineHeight

            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = parent.colorScheme == .dark ? .white : .black
            spinner.sizeToFit()
            spinner.center = CGPoint(
                x: textView.textContainerInset.left + spinner.bounds.width / 2,
                y: startsLine ? caret.midY : caret.maxY + lineHeight / 2
            )
            spinner.startAnimating()
            // A card is only as tall as its text, and the new line isn't there yet.
            if parent.growsWithText { textView.clipsToBounds = false }
            textView.addSubview(spinner)
            imageProgress = spinner
        }

        func hideImageProgress() {
            imageProgress?.removeFromSuperview()
            imageProgress = nil
            if parent.growsWithText { textView?.clipsToBounds = true }
        }

        func pasteImages(_ images: [UIImage]) {
            insertImages(images.compactMap(ScriptImages.add))
        }

        /// Script copied from an editor here, pasted in place of the selection
        /// with its images shown as images.
        func pasteScript(_ script: String) {
            guard let textView, textView.markedTextRange == nil else { return }
            let insertion = ScriptImageAttachment.editorText(for: script, maxHeight: parent.imageMaxHeight)
            let selection = textView.selectedRange
            replace(selection, with: insertion,
                    selecting: NSRange(location: selection.location + insertion.length, length: 0), in: textView)
        }

        /// Images UIKit put in itself — pasted with rich text, or dropped
        /// in — are kept in the store and held as the script's own, in the same
        /// place. One with no picture to keep is left for `script(from:)` to drop.
        /// UIKit's own placeholders, as for dictation, are subclasses, and are
        /// left alone.
        private func adoptPastedImages(in textView: UITextView) {
            let storage = textView.textStorage
            var adopted: [(range: NSRange, attachment: ScriptImageAttachment)] = []
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let attachment = value as? NSTextAttachment, type(of: attachment) == NSTextAttachment.self,
                      let image = attachment.pastedImage, let name = ScriptImages.add(image) else { return }
                adopted.append((range, ScriptImageAttachment(name: name, maxHeight: parent.imageMaxHeight)))
            }
            for image in adopted {
                storage.addAttribute(.attachment, value: image.attachment, range: image.range)
            }
        }

        private func isNewline(_ character: unichar) -> Bool {
            Unicode.Scalar(character).map(CharacterSet.newlines.contains) ?? false
        }

        /// The word the caret is in or just after, if any.
        private func wordRange(at location: Int, in textView: UITextView) -> NSRange {
            guard let position = textView.position(from: textView.beginningOfDocument, offset: location),
                  let word = textView.tokenizer.rangeEnclosingPosition(
                    position, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.backward.rawValue)
                  ) else {
                return NSRange(location: location, length: 0)
            }
            let start = textView.offset(from: textView.beginningOfDocument, to: word.start)
            return NSRange(location: start, length: textView.offset(from: word.start, to: word.end))
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

/// The suggestions being reviewed, as the editor shows them.
struct SuggestionMarks {
    /// Each with its range in this editor's script.
    var suggestions: [ScriptSuggestion]
    /// The one tapped on, with Accept and Reject showing above it.
    var focused: ScriptSuggestion.ID?
    var onFocus: (ScriptSuggestion.ID) -> Void
    /// Accept and Reject were put away from over this one.
    var onUnfocus: (ScriptSuggestion.ID) -> Void
    var onAccept: (ScriptSuggestion.ID) -> Void
    var onReject: (ScriptSuggestion.ID) -> Void
}

extension ScriptSuggestion.Kind {
    /// What it does, to name it out loud.
    var actionName: String {
        switch self {
        case .spelling: String(localized: "Fix Spelling")
        case .missingWords: String(localized: "Add Missing Words")
        case .rewrite: String(localized: "Rewrite")
        case .cue: String(localized: "Add Cue")
        case .anchor: String(localized: "Add Anchor")
        case .lineBreak: String(localized: "Add Line Break")
        case .bold: String(localized: "Make Bold")
        case .italic: String(localized: "Make Italic")
        }
    }
}

extension NSAttributedString.Key {
    /// On everything shown for a suggestion, its ID: the words it changes,
    /// and what it would put in.
    static let cueSuggestion = NSAttributedString.Key("CueCardSuggestion")
    /// On what a suggestion would put in, shown but not in the script.
    static let cueSuggestionPreview = NSAttributedString.Key("CueCardSuggestionPreview")
}

extension NSAttributedString {
    /// Where suggestions' previews are, front to back.
    var suggestionPreviewRanges: [NSRange] {
        var ranges: [NSRange] = []
        enumerateAttribute(.cueSuggestionPreview, in: NSRange(location: 0, length: length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }
}

// MARK: - Script fonts

extension UIFont {
    /// The script's face, heavier for bold and slanted for italic.
    static func script(ofSize size: CGFloat, style: EmphasisStyle = []) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: style.contains(.bold) ? .heavy : .medium)
        guard style.contains(.italic),
              let italic = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic))
        else { return font }
        return UIFont(descriptor: italic, size: size)
    }

    /// A cue's face: condensed, so it never reads as part of the script.
    static func cue(ofSize size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight, width: .condensed)
    }
}

extension NSParagraphStyle {
    /// A script's lines, `lineSpacing` apart. A script with any Chinese,
    /// Japanese or Korean in it sets every line taller, all the same height, so
    /// a line doesn't shift as those words are typed or composed into it.
    static func script(ofSize size: CGFloat, isWide: Bool, lineSpacing: CGFloat = 0,
                       paragraphSpacing: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        if isWide { style.minimumLineHeight = WideScript.lineHeight(ofSize: size) }
        return style
    }
}

private extension Emphasis {
    /// Whether `selection` sits within what this styles — a caret touching
    /// either end of the words counts.
    func isAround(_ selection: NSRange) -> Bool {
        if selection.length == 0 {
            return content.location <= selection.location && selection.location <= NSMaxRange(content)
        }
        return range.location <= selection.location && NSMaxRange(selection) <= NSMaxRange(range)
            && NSIntersectionRange(selection, content).length > 0
    }
}

private extension NSString {
    /// `range` without the blank space at either end.
    func trimmingWhitespace(in range: NSRange) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let blank = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = Unicode.Scalar(character(at: start)), blank.contains(scalar) { start += 1 }
        while end > start, let scalar = Unicode.Scalar(character(at: end - 1)), blank.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}

// MARK: - Images in the editor

extension ScriptImageAttachment {
    /// The script as the editor holds it: each `[image …]` tag as the image.
    static func editorText(for script: String, maxHeight: CGFloat) -> NSAttributedString {
        let text = NSMutableAttributedString(string: script)
        for match in TeleprompterParser.imageMatches(in: script).reversed() {
            text.replaceCharacters(in: match.range, with: NSAttributedString(
                attachment: ScriptImageAttachment(name: match.name, maxHeight: maxHeight)))
        }
        return text
    }

    /// The script the editor's text holds, each image written back as its
    /// `[image …]` tag. Anything else held as an attachment is left out.
    static func script(from text: NSAttributedString) -> String {
        // Suggestions shown in the text aren't part of the script.
        var text = text
        if !text.suggestionPreviewRanges.isEmpty {
            let copy = NSMutableAttributedString(attributedString: text)
            CueTextEditor.removeSuggestionPreviews(from: copy)
            text = copy
        }
        let script = NSMutableString(string: text.string)
        var location = script.range(of: CueCards.imageCharacter, options: .backwards)
        // Back to front, so writing a tag doesn't move the ones still to come.
        while location.location != NSNotFound {
            let attachment = text.attribute(.attachment, at: location.location, effectiveRange: nil)
            let tag = (attachment as? ScriptImageAttachment).map { TeleprompterParser.imageTag(name: $0.name) } ?? ""
            script.replaceCharacters(in: location, with: tag)
            location = script.range(of: CueCards.imageCharacter, options: .backwards,
                                    range: NSRange(location: 0, length: location.location))
        }
        return script as String
    }
}

private extension NSTextAttachment {
    /// The picture held by an attachment UIKit made itself, as for an image
    /// pasted in with rich text.
    var pastedImage: UIImage? {
        if let image { return image }
        if let data = fileWrapper?.regularFileContents ?? contents { return UIImage(data: data) }
        return nil
    }
}

// MARK: - Cue insertion

extension NSString {
    /// The text to splice in for a new cue at `location`, spaced so it doesn't
    /// collide with the words either side of it, and where in that text its
    /// placeholder is — to be selected, ready for the cue to be typed over it.
    func newCueInsertion(at location: Int) -> (text: String, placeholder: NSRange) {
        let placeholder = TeleprompterParser.placeholderCueText
        let insertion = spacedInsertion(of: TeleprompterParser.cueTag(text: placeholder), at: location)
        let start = insertion.tagOffset + (TeleprompterParser.cueTagPrefix as NSString).length
        return (insertion.text, NSRange(location: start, length: (placeholder as NSString).length))
    }

    /// The text to splice in for `tag` at `location`, spaced so it doesn't
    /// collide with the words either side of it, and how far into that text
    /// the tag starts.
    func spacedInsertion(of tag: String, at location: Int) -> (text: String, tagOffset: Int) {
        let previous = location > 0 ? substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < length ? substring(with: NSRange(location: location, length: 1)) : ""

        let needsLeadingSpace = !previous.isEmpty && previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let needsTrailingSpace = !next.isEmpty && next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil

        let leading = needsLeadingSpace ? " " : ""
        return (leading + tag + (needsTrailingSpace ? " " : ""), (leading as NSString).length)
    }
}

// MARK: - Cue bar

/// The strip above the keyboard while a script is being written: buttons to drop
/// a cue or an anchor in at the caret, a group to bold, italicize or add an
/// image, and one to get the keyboard out of the way.
struct CueBar: View {
    /// The bar's height. The editor keeps this much room clear at the bottom so
    /// the line being typed never hides behind it.
    static let height: CGFloat = 60

    let colorScheme: ColorScheme
    var onAddCue: () -> Void
    /// Nil where anchors aren't used, which leaves the button out.
    var onAddAnchor: (() -> Void)?
    var onAddImage: () -> Void
    var onFormat: (EmphasisStyle) -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons(showsLabels: true)
            buttons(showsLabels: false)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(AppColors.background(for: colorScheme))
        .background(alignment: .top) {
            LinearGradient(colors: [.clear, AppColors.background(for: colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: CueTextEditor.edgeFade)
                .offset(y: -CueTextEditor.edgeFade)
                .allowsHitTesting(false)
        }
    }

    private func buttons(showsLabels: Bool) -> some View {
        HStack(spacing: 8) {
            addButton("Cue", systemImage: "text.bubble", accessibilityLabel: "Add Cue",
                      showsLabel: showsLabels, action: onAddCue)

            if let onAddAnchor {
                addButton("Anchor", systemImage: "bookmark", accessibilityLabel: "Add Anchor",
                          showsLabel: showsLabels, action: onAddAnchor)
            }

            HStack(spacing: 0) {
                formatButton("bold", label: "Bold") { onFormat(.bold) }
                formatButton("italic", label: "Italic") { onFormat(.italic) }
                formatButton("photo", label: "Add Image", action: onAddImage)
            }
            .glassedEffect(in: Capsule())

            Spacer(minLength: 0)

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .glassedEffect(in: Circle())
            }
            .accessibilityLabel("Hide keyboard")
        }
    }

    /// "+ Cue" or "+ Anchor", or just the symbol where the words won't fit.
    private func addButton(_ title: LocalizedStringKey, systemImage: String, accessibilityLabel: LocalizedStringKey,
                           showsLabel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if showsLabel {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text(title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .fixedSize()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40)
                }
            }
            .frame(minHeight: 44)
            .glassedEffect(in: Capsule())
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
