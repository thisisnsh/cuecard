import UIKit

/// Where the reading line sits, as a fraction of the height of the view the
/// script scrolls in. Just above centre: high enough to leave the next few lines
/// in view, low enough to read as the middle of the screen rather than the top.
///
/// It doubles as the script's top inset, so a line's scroll target is its own
/// position in the laid-out text — see `ScriptLayout`.
enum TeleprompterLayout {
    static let readingLineFraction: CGFloat = 0.45
}

// MARK: - Drawing the script

/// A `[pause …]` in the drawn script: the characters its label takes up, and how
/// long it waits.
struct PauseMark {
    /// The label's own characters. Every label is written to the same length, so
    /// this range holds still for the life of the drawn script.
    let range: NSRange
    let seconds: Double
}

/// The script as the teleprompter draws it, and the pauses in it.
struct RenderedScript {
    let attributed: NSAttributedString
    /// Every pause, in reading order.
    let pauses: [PauseMark]
}

/// What a pause reads on screen.
enum PauseState: Equatable {
    /// Ahead of the reader, or holding them here, with this long left to wait.
    case waiting(Double)
    /// Behind the reader, or run down to nothing.
    case expired
}

/// The words a pause is drawn with.
///
/// Both readings are the same number of characters in the same monospaced font,
/// so a pause counting down is always exactly as wide as it was. That is what
/// lets the label be rewritten every second without the script re-wrapping around
/// it — every line stays where it was, and so does the reader.
enum PauseLabel {

    /// The widest a label gets, which is what the shorter one is padded out to.
    private static let width = "Paused for 00:00".count

    static func text(_ state: PauseState) -> String {
        switch state {
        case .waiting(let seconds):
            // Rounded down, so the count reaches 00:00 and rests there for its
            // last second rather than skipping from 00:01 to gone.
            return padded("Paused for " + TeleprompterParser.formatTime(Int(max(seconds, 0))))
        case .expired:
            return padded("Expired pause")
        }
    }

    private static func padded(_ text: String) -> String {
        guard text.count < width else { return text }
        return text + String(repeating: " ", count: width - text.count)
    }
}

enum TeleprompterScript {

    /// Draw the script: what is spoken at full size, cues smaller and in the cue
    /// color, with any hold read back as the seconds it was written with.
    ///
    /// The full screen and the overlay both come through here, so the two lay out
    /// the same characters. That's what lets the overlay find its place in the
    /// script by character instead of counting lines of its own, which it wraps
    /// far more of.
    static func render(
        text: String,
        fontSize: CGFloat,
        cueColor: CueColor,
        isDarkMode: Bool
    ) -> RenderedScript {
        let result = NSMutableAttributedString()
        var pauses: [PauseMark] = []

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
        let cueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold),
            .foregroundColor: cueColor.uiColor(isDarkMode: isDarkMode),
            .kern: fontSize * 0.05
        ]
        // Small, grey and monospaced: an instruction to the reader rather than
        // anything to say, and a width that holds still as it counts down.
        let pauseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: max(fontSize * 0.5, 10), weight: .semibold),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textSecondary : AppColors.UIColors.Light.textSecondary
        ]

        for (paragraphIndex, paragraph) in text.components(separatedBy: "\n\n").enumerated() {
            if paragraphIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            for (lineIndex, line) in paragraph.components(separatedBy: "\n").enumerated() {
                if lineIndex > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }

                if line.isEmpty { continue }

                for (segmentIndex, segment) in TeleprompterParser.segments(in: line).enumerated() {
                    if segmentIndex > 0 {
                        result.append(NSAttributedString(string: " ", attributes: textAttrs))
                    }

                    switch segment {
                    case .cue(let cueText):
                        result.append(NSAttributedString(string: cueText, attributes: cueAttrs))
                    case .pause(let seconds):
                        let label = PauseLabel.text(.waiting(seconds))
                        pauses.append(PauseMark(
                            range: NSRange(location: result.length, length: (label as NSString).length),
                            seconds: seconds
                        ))
                        result.append(NSAttributedString(string: label, attributes: pauseAttrs))
                    case .text(let content):
                        result.append(NSAttributedString(string: content, attributes: textAttrs))
                    }
                }
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        if result.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        }

        return RenderedScript(attributed: result, pauses: pauses)
    }

    /// Write the live labels into a script already drawn: how long each pause has
    /// left, or that it has run out.
    ///
    /// Every label is the same length, so nothing shifts and nothing re-wraps —
    /// the countdown costs one paragraph's worth of redraw and leaves the reader's
    /// place in the script exactly where it was.
    static func applyPauseLabels(_ states: [PauseState], to storage: NSTextStorage, pauses: [PauseMark]) {
        guard !pauses.isEmpty, states.count == pauses.count else { return }

        let current = storage.string as NSString
        var changes: [(range: NSRange, label: String)] = []

        for (index, pause) in pauses.enumerated() {
            guard NSMaxRange(pause.range) <= current.length else { return }

            let label = PauseLabel.text(states[index])
            if current.substring(with: pause.range) != label {
                changes.append((pause.range, label))
            }
        }

        guard !changes.isEmpty else { return }

        storage.beginEditing()
        for change in changes {
            // Carry the attributes the label was drawn with rather than trusting
            // what a plain replacement would inherit.
            let attributes = storage.attributes(at: change.range.location, effectiveRange: nil)
            storage.replaceCharacters(
                in: change.range,
                with: NSAttributedString(string: change.label, attributes: attributes)
            )
        }
        storage.endEditing()
    }
}

// MARK: - Lines and characters

/// Where each rendered line of the script begins, in characters.
///
/// The full screen and the overlay wrap the same script into different numbers of
/// lines, so a place in the script travels between them as a character: one side
/// asks which character it is reading, the other which of its own lines that
/// character is on.
struct ScriptLineMap: Equatable {
    /// First character of each rendered line, ascending. Empty until the script
    /// has laid out.
    var starts: [Int] = []

    var count: Int { starts.count }

    /// The last line there is to scroll to.
    var lastLine: Double { Double(max(starts.count - 1, 0)) }

    /// The character, fractionally, at `line`.
    func character(forLine line: Double) -> Double {
        guard starts.count > 1 else { return 0 }

        let clamped = min(max(line, 0), lastLine)
        let index = min(Int(clamped), starts.count - 2)
        let fraction = clamped - Double(index)
        return Double(starts[index]) + Double(starts[index + 1] - starts[index]) * fraction
    }

    /// The line, fractionally, that `character` falls on.
    func line(forCharacter character: Double) -> Double {
        guard starts.count > 1 else { return 0 }
        guard character > Double(starts[0]) else { return 0 }
        guard character < Double(starts[starts.count - 1]) else { return lastLine }

        var low = 0
        var high = starts.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if Double(starts[mid]) <= character {
                low = mid
            } else {
                high = mid
            }
        }

        let span = Double(starts[low + 1] - starts[low])
        guard span > 0 else { return Double(low) }
        return Double(low) + (character - Double(starts[low])) / span
    }
}

/// A script laid out in a text view: which characters each rendered line holds,
/// and the scroll offset that brings each line to the reading line.
struct ScriptLayout {
    var map = ScriptLineMap()
    /// One offset per line. Line fragments are measured inside the text container,
    /// which is inset from the top by exactly the reading line's height — so a
    /// line's own position in the text is already the offset to scroll to.
    var offsets: [CGFloat] = []

    var isEmpty: Bool { offsets.count < 2 }

    /// Measure the script as the text view has it laid out right now.
    static func measure(_ textView: UITextView) -> ScriptLayout {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        layoutManager.ensureLayout(for: container)

        var layout = ScriptLayout()
        var starts: [Int] = []
        let glyphRange = layoutManager.glyphRange(for: container)
        var glyphIndex = glyphRange.location

        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange(location: 0, length: 0)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            layout.offsets.append(fragment.origin.y)
            starts.append(layoutManager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil).location)

            guard lineRange.length > 0 else { break }
            glyphIndex = NSMaxRange(lineRange)
        }

        layout.map = ScriptLineMap(starts: starts)
        return layout
    }

    /// The scroll offset that puts `line` on the reading line, interpolating
    /// between lines rather than stepping between them.
    func offset(forLine line: Double) -> CGFloat {
        guard offsets.count > 1 else { return 0 }

        let clamped = min(max(line, 0), Double(offsets.count - 1))
        let index = min(Int(clamped), offsets.count - 2)
        let fraction = CGFloat(clamped - Double(index))
        return offsets[index] + (offsets[index + 1] - offsets[index]) * fraction
    }

    /// The inverse: which line, fractionally, sits on the reading line at this
    /// scroll offset.
    func line(forOffset offset: CGFloat) -> Double {
        guard offsets.count > 1 else { return 0 }
        guard offset > offsets[0] else { return 0 }
        guard offset < offsets[offsets.count - 1] else { return Double(offsets.count - 1) }

        var low = 0
        var high = offsets.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if offsets[mid] <= offset {
                low = mid
            } else {
                high = mid
            }
        }

        let span = offsets[low + 1] - offsets[low]
        guard span > 0 else { return Double(low) }
        return Double(low) + Double((offset - offsets[low]) / span)
    }
}

// MARK: - Playback

/// A pause written into the script, placed among the lines it wrapped into: the
/// scroll stops with this line on the reading line for `seconds`, and the clock
/// runs on through it.
struct ScriptPause: Equatable {
    let line: Double
    let seconds: Double
}

/// The script as the full-screen teleprompter laid it out. The reader's place is
/// counted in these lines and every pause is placed among them; the overlay wraps
/// the same script into more lines of its own, so it takes its place from here by
/// character.
struct ScriptGeometry: Equatable {
    var map = ScriptLineMap()
    /// Every pause, by the line it landed on, in reading order.
    var pauses: [ScriptPause] = []

    var lineCount: Int { map.count }

    /// Place the pauses among the lines the script wrapped into. A pause holds
    /// when its own line reaches the reading line, wherever in that line it
    /// happens to sit.
    static func from(layout: ScriptLayout, pauses marks: [PauseMark]) -> ScriptGeometry {
        ScriptGeometry(
            map: layout.map,
            pauses: marks.map {
                ScriptPause(
                    line: layout.map.line(forCharacter: Double($0.range.location)).rounded(.down),
                    seconds: $0.seconds
                )
            }
        )
    }

    /// What each pause reads, given where the reader is. Everything the reader has
    /// gone past has run out, whether it was waited through or scrolled straight
    /// over.
    func pauseStates(at position: ScriptPosition) -> [PauseState] {
        pauses.enumerated().map { index, pause in
            if index == position.pauseIndex {
                return .waiting(position.pauseRemaining)
            }
            if pause.line > position.line {
                return .waiting(pause.seconds)
            }
            // Sharing the reader's line: the pauses after the one holding them are
            // still to come. With none holding them, the line's pauses are behind.
            if pause.line == position.line, let holding = position.pauseIndex, index > holding {
                return .waiting(pause.seconds)
            }
            return .expired
        }
    }
}

/// Where the reader is in the script, and whether a pause is holding them there.
struct ScriptPosition {
    var line: Double
    /// The pause holding the reader here, if one is.
    var pauseIndex: Int?
    /// How long that pause has left. Zero when the script is free to scroll.
    var pauseRemaining: Double
}

/// Turns the clock into a place in the script.
///
/// The clock and the script are two different things. The clock only ever runs
/// forward while playing, so it can be trusted to say how long someone has been
/// speaking; dragging the script, or a cue holding it still, moves the reader
/// through it without touching the clock.
///
/// Nothing is accumulated frame by frame: the position is worked out from the
/// clock each time, so the full screen and the overlay stay on the same line
/// however long either of them has been the one counting.
struct ScriptPlayback: Equatable {
    /// The line the script was last put on by hand, and the clock reading when it
    /// was put there. Playback is measured out from here.
    var anchorLine: Double = 0
    var anchorTime: Double = 0

    /// Leave the script on `line`, with the clock reading `time`.
    mutating func place(atLine line: Double, time: Double, lineCount: Int) {
        anchorLine = min(max(line, 0), Double(max(lineCount - 1, 0)))
        anchorTime = time
    }

    /// Where the reader is once the clock reads `time`: the anchor, plus however
    /// many lines fit in the time since it was set, minus the pauses waited
    /// through on the way.
    func position(
        at time: Double,
        linesPerMinute: Double,
        pauses: [ScriptPause],
        lineCount: Int
    ) -> ScriptPosition {
        let lastLine = Double(max(lineCount - 1, 0))
        var line = min(max(anchorLine, 0), lastLine)

        let linesPerSecond = linesPerMinute / 60
        guard linesPerSecond > 0 else {
            return ScriptPosition(line: line, pauseIndex: nil, pauseRemaining: 0)
        }

        // Time left to spend, walking forward from the anchor. A pause on the
        // anchor's own line counts: the anchor is only ever set by a restart or by
        // a drag, and both are a fresh arrival at that line. It can't fire twice,
        // because coming out of a pause moves the clock, not the anchor.
        var remaining = max(time - anchorTime, 0)

        for (index, pause) in pauses.enumerated() where pause.line >= line && pause.line <= lastLine {
            let travel = (pause.line - line) / linesPerSecond
            if remaining < travel {
                return ScriptPosition(
                    line: line + remaining * linesPerSecond,
                    pauseIndex: nil,
                    pauseRemaining: 0
                )
            }

            remaining -= travel
            line = pause.line

            if remaining < pause.seconds {
                return ScriptPosition(
                    line: line,
                    pauseIndex: index,
                    pauseRemaining: pause.seconds - remaining
                )
            }
            remaining -= pause.seconds
        }

        return ScriptPosition(
            line: min(line + remaining * linesPerSecond, lastLine),
            pauseIndex: nil,
            pauseRemaining: 0
        )
    }
}
