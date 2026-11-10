import SwiftUI
import FirebaseAnalytics

// MARK: - Pages

/// The screens with a help button. Every one shows the same help; the page
/// only tells analytics where it was opened.
enum HelpPage: String {
    case library
    case writingTeleprompter = "home_teleprompter"
    case writingCards = "home_cards"
    case settings
    case teleprompter
    case cards

    /// The editor's page for the mode it's writing in.
    static func writing(_ mode: ScriptMode) -> HelpPage {
        mode == .cards ? .writingCards : .writingTeleprompter
    }
}

struct HelpTopic: Identifiable {
    let title: String
    let detail: String

    var id: String { title }

    init(_ title: LocalizedStringResource, detail: LocalizedStringResource) {
        self.title = String(localized: title)
        self.detail = String(localized: detail)
    }

    /// How many of `words` are in the title or the explanation, ignoring
    /// case and accents.
    func matchCount(of words: [String]) -> Int {
        words.filter { title.localizedStandardContains($0) || detail.localizedStandardContains($0) }.count
    }
}

private struct HelpSection: Identifiable {
    /// Names the section in analytics, the same in every language.
    let id: String
    let title: String
    /// What's in it, under the title on the front page.
    let summary: String
    let systemImage: String
    var topics: [HelpTopic]

    init(_ id: String, title: LocalizedStringResource, summary: LocalizedStringResource,
         systemImage: String, topics: [HelpTopic]) {
        self.id = id
        self.title = String(localized: title)
        self.summary = String(localized: summary)
        self.systemImage = systemImage
        self.topics = topics
    }
}

// MARK: - Topics

private enum AllHelp {
    /// Suggestions are left out on an iPhone with no Apple Intelligence.
    /// Turned off in Settings, they stay, so help can say how to turn them on.
    static var writing: HelpSection {
        var section = allWriting
        if OnDeviceModelAvailability.onDevice == .unsupported {
            section.topics.removeAll { $0.id == suggestionsTopic.id }
        }
        return section
    }

    private static let suggestionsTopic = HelpTopic("Suggestions AI (Beta)",
                  detail: "Tap the sparkles button at the bottom left of the editor to have Apple Intelligence read your script or deck on this iPhone. It suggests spelling fixes, missing words, rewrites, cues, anchors, line breaks that split long lines into short paragraphs, and bold or italic words, shown right in your script. In a deck it leaves out anchors, and only adds a cue where a card has room. Tap a suggestion to accept or reject it, and tap the sparkles button again when you're done. Needs an iPhone with Apple Intelligence turned on, and Suggestions AI on in Settings.")

    private static let allWriting = HelpSection("writing", title: "Writing",
                                    summary: "Modes, cues, formatting, images and cards",
                                    systemImage: "pencil", topics: [
        HelpTopic("Pick a Mode",
                  detail: "In your library, choose Teleprompter or Cards from the menu at the top left, then tap + at the bottom. Teleprompter scrolls your whole script. Cards shows it one card at a time."),
        HelpTopic("Add Cues",
                  detail: "Cues are reminders like [pause], shown in color and not read out. Type [ or tap + Cue above the keyboard."),
        HelpTopic("Bold and Italic",
                  detail: "Select words and tap B or I above the keyboard. Or type *bold* or _italic_."),
        HelpTopic("Add Anchors",
                  detail: "Anchors mark spots in your script, like [anchor]. Type one or tap + Anchor above the keyboard. In the teleprompter, the buttons at the far left and right jump to the anchor before or after."),
        HelpTopic("Add Images",
                  detail: "Tap the photo button above the keyboard, or paste an image in. The Lock Screen and Apple Watch show a photo symbol in their place."),
        HelpTopic("Add Cards",
                  detail: "Each box in the editor is one card. Tap Create New Card to add another."),
        suggestionsTopic
    ])

    static let notes = HelpSection("notes", title: "Library & Saving",
                                    summary: "Collections, saving, import, versions and sharing",
                                    systemImage: "rectangle.stack", topics: [
        HelpTopic("Open a Script",
                  detail: "CueCard opens on your library, with every script and deck you saved. Tap one to write in it, and tap back to return. Switch between Teleprompter and Cards at the top."),
        HelpTopic("Save Your Work",
                  detail: "When there are changes to save, the bottom of the editor says Unsaved and Save appears at the bottom left. Tap it to save. To keep your changes as a separate script, open ••• at the top of the editor, then Save as New. A new script you haven't saved shows in the library as a draft."),
        HelpTopic("Rename, Duplicate or Delete",
                  detail: "In your library, touch and hold a script, or swipe it. In the editor, tap the title at the top to rename it."),
        HelpTopic("Organize in Collections",
                  detail: "In your library, tap + after your collections, or ••• › New Collection. Tap a collection at the top to show only its scripts, or All to show every one. To add a script to one, swipe it right or touch and hold it, then tap Add to Collection. A script you start or import goes in the collection you're in. Touch and hold a collection to rename or delete it. Tap ••• › Sort By to change the order."),
        HelpTopic("Import a Text File",
                  detail: "In your library, tap ••• › Import File to add a text file or a TextPack as a script."),
        HelpTopic("Go Back to an Older Version",
                  detail: "Every save is a new version. Tap the version number at the bottom of the editor to compare changes and restore one. Once a note has more than one, it's also under ••• at the top, in Version History."),
        HelpTopic("Keep Scripts if the App Is Removed",
                  detail: "Until you choose a storage folder, scripts are kept only in CueCard and are deleted with the app. In your library, tap ••• › Choose Storage Folder. Each script is kept there as a text file, with a list of the collections they're in. Pick one in iCloud Drive to keep them there too."),
        HelpTopic("Your Privacy",
                  detail: "There's no account, and CueCard doesn't upload your scripts. They're kept on this iPhone, and in the storage folder if you choose one."),
        HelpTopic("Share a Script",
                  detail: "In your library, touch and hold a script and tap Share. It's sent as text, cues included. A script with images is sent as a TextPack, with its images.")
    ])

    static let settings = HelpSection("settings", title: "Settings & Timer",
                                    summary: "Text size, colors, camera, timer and language",
                                    systemImage: "gearshape", topics: [
        HelpTopic("Change Text Size and Colors",
                  detail: "Tap the gear in your library, the editor, the teleprompter or your cards. Text sizes and cue color are under Teleprompter and Cards, and each keeps its own."),
        HelpTopic("Choose How Videos Record",
                  detail: "In Settings, under Camera, pick the resolution, frame rate, dynamic range, codec and stabilization. Each camera records as close to them as it can, and a change made while recording starts with the next take. Turn on Mirror Front Camera to record the front camera as you see it."),
        HelpTopic("Set a Timer",
                  detail: "Tap the timer at the bottom of the editor to set how long you have, when it warns you, and the colors it turns."),
        HelpTopic("Count Down Before Scrolling",
                  detail: "In the teleprompter's timer, set a Countdown to get a few seconds before the script starts scrolling."),
        HelpTopic("Change the Language",
                  detail: "Tap the gear, then Language. CueCard is in English, French, Portuguese, Russian and Spanish.")
    ])

    private static let followVoiceTopic = HelpTopic("Follow Me AI (Beta)",
                  detail: "Tap the waveform at the top of the teleprompter. If it isn't there, turn on Follow Me AI in Settings, under Apple Intelligence. It's off each time the teleprompter opens. The script moves as you read it aloud, instead of at a set speed, and the timer starts with your first words. Tap Pause to stop listening and Play to listen again. Your voice is understood on this iPhone and never leaves it.")

    /// Follow Me AI stays while it's turned off, so help can say how to turn it on.
    static let teleprompter = HelpSection("teleprompter", title: "Teleprompter",
                                    summary: "Scrolling, recording, mirroring and the floating window",
                                    systemImage: "text.alignleft", topics: [
        HelpTopic("Play and Pause",
                  detail: "The buttons fade while the script scrolls so they stay out of the way. Tap the screen to show them again."),
        HelpTopic("Scroll by Hand",
                  detail: "Drag the script to go back or skip ahead. It keeps scrolling from where you leave it."),
        HelpTopic("Change Speed",
                  detail: "Scroll Speed in Settings sets how many lines pass each minute."),
        HelpTopic("Record in CueCard",
                  detail: "Tap the camera at the top, tapping the screen first if the buttons are hidden. The camera opens in a small window over your script. Tap the red button to record and again to pause, then tap stop to save the video to Photos. Your script stays out of the video."),
        HelpTopic("Record in Step with the Script",
                  detail: "With the camera open, Play starts recording and Pause pauses it. Recording or pausing on the camera plays or pauses the script, and stopping pauses it. Turn off Sync with Teleprompter in Settings to use them separately."),
        HelpTopic("Mirror",
                  detail: "Turn on Flip Horizontally or Flip Vertically under Mirror in Settings to flip the text for a teleprompter's glass. The floating window uses the same settings. Both are off by default."),
        HelpTopic("Keep Your Place",
                  detail: "The pointer at the side of the script marks the line to read. Drag it up or down to read where it suits your eyes, and the script lines up with it. Turn off Reading Guide Line in Settings to hide it."),
        HelpTopic("Use Over Other Apps",
                  detail: "Leave CueCard while the teleprompter is open and your script keeps going in a floating window, handy on video calls. It doesn't open while the camera is on."),
        HelpTopic("Know When Time Is Running Out",
                  detail: "The timer changes color when you're near the end and again once you're over time. Pick the colors in the timer."),
        followVoiceTopic
    ])

    static let cards = HelpSection("cards", title: "Cards",
                                    summary: "Turning cards, recording and the Lock Screen",
                                    systemImage: "rectangle.on.rectangle", topics: [
        HelpTopic("Turn Cards",
                  detail: "Swipe, or tap Back and Next. The dots at the top show which card you're on."),
        HelpTopic("Record with Cards",
                  detail: "Tap the camera at the top. The camera opens in a small window over your cards. Tap the red button to record and again to pause, then tap stop to save the video to Photos. Keep turning cards while you record."),
        HelpTopic("Read from the Lock Screen",
                  detail: "Turn on Show on Lock Screen in Settings. Then lock your iPhone and turn cards right from the Lock Screen."),
        HelpTopic("Count Up Without a Timer",
                  detail: "The time at the top counts down your timer. With no timer set, it counts up from when you started.")
    ])

    static let takes = HelpSection("takes", title: "Takes",
                                    summary: "The videos you record with a script",
                                    systemImage: "film.stack", topics: [
        HelpTopic("Find Your Takes",
                  detail: "Videos you record in CueCard with a script or deck open are kept as its takes, and so are videos you record in another app while the teleprompter floats over it. Tap Takes above the reading controls to see them, or the takes count beside a script in your library."),
        HelpTopic("Move the Camera Window",
                  detail: "Drag the camera window to any corner. Pinch or double-tap it to change its size, and tap it to hide or show its buttons. Use the buttons to zoom or flip the camera."),
        HelpTopic("Read Over the Camera",
                  detail: "Your script or cards are drawn over the camera window, so you can read every line. Turn off Text Above Camera in Settings, under Camera, to show the camera on top instead. Either way, the text stays out of the video."),
        HelpTopic("Play a Take",
                  detail: "Tap a take to play it right in CueCard. Below the video, add tags and notes, like what worked and what to change next time."),
        HelpTopic("Favorite a Take",
                  detail: "Tap the heart on a take. It's a favorite in Photos too."),
        HelpTopic("Add to an Album",
                  detail: "Touch and hold a take, or play it, and tap Add to Album to put it in a Photos album."),
        HelpTopic("Delete a Take",
                  detail: "Swipe left on a take, or play it and tap Delete. It's deleted from Photos too."),
        HelpTopic("Where Takes Are Kept",
                  detail: "Your videos stay in Photos, and nothing leaves this device.")
    ])

    static let appleWatch = HelpSection("apple_watch", title: "Apple Watch",
                                    summary: "Control the teleprompter and read cards",
                                    systemImage: "applewatch", topics: [
        HelpTopic("Install on Apple Watch",
                  detail: "Open the Watch app on your iPhone. Under Available Apps, tap Install next to CueCard."),
        HelpTopic("Control the Teleprompter",
                  detail: "Open a script on your iPhone. The watch shows its timer and can play, pause or go back 10 seconds."),
        HelpTopic("Read Cards on Your Wrist",
                  detail: "Open a deck on your iPhone and it shows on the watch too. Turning a card on either one moves both."),
        HelpTopic("Keep Decks on the Watch",
                  detail: "Touch and hold a saved deck in your library and tap Keep on Apple Watch. Then you can read it without your iPhone."),
        HelpTopic("Stay on Screen",
                  detail: "The watch goes back to the clock after a while. In the Watch app, go to General › Return to Clock › CueCard and set it to 1 hour.")
    ])

    /// The Play or Pause control needs iOS 18 and an iPhone with an Action button.
    static var actionButton: HelpSection? {
        guard #available(iOS 18.0, *), DeviceModel.hasActionButton else { return nil }
        return HelpSection("action_button", title: "Action Button",
                           summary: "Play or pause without touching the screen",
                           systemImage: "button.programmable", topics: [
            HelpTopic("Play or Pause the Teleprompter",
                      detail: "Start and stop scrolling without touching the screen. In the Settings app, go to Action Button › Controls and pick Play or Pause under CueCard.")
        ])
    }

    static var sections: [HelpSection] {
        [writing, notes, settings, teleprompter, cards, takes, appleWatch] + (actionButton.map { [$0] } ?? [])
    }
}

/// Every help topic with the section it's in, for answering questions from.
enum HelpLibrary {
    static var topics: [(section: String, topic: HelpTopic)] {
        AllHelp.sections.flatMap { section in section.topics.map { (section.title, $0) } }
    }

    /// The topics with at least one of the words in `query`, those with the
    /// most of them first, and otherwise in the order help lists them.
    static func search(_ query: String) -> [(section: String, topic: HelpTopic)] {
        var seen = Set<String>()
        var words: [String] = []
        for word in query.split(whereSeparator: \.isWhitespace) where seen.insert(word.lowercased()).inserted {
            words.append(String(word))
        }

        typealias Match = (index: Int, count: Int)
        let all = topics
        var matches: [Match] = []
        for (index, entry) in all.enumerated() {
            let count = entry.topic.matchCount(of: words)
            if count > 0 { matches.append((index, count)) }
        }
        matches.sort { a, b in a.count != b.count ? a.count > b.count : a.index < b.index }
        return matches.map { all[$0.index] }
    }
}

// MARK: - Help Sheet

/// The same help on every page. Where Apple Intelligence can answer, it
/// opens on asking a question, with the sections to browse below; otherwise
/// on the sections, with a search across all of them.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    let page: HelpPage

    static let screen = "help"

    private var asksFirst: Bool {
        OnDeviceModelAvailability.forAskAI == .available
    }

    var body: some View {
        NavigationStack {
            if asksFirst {
                HelpAssistantView(browse: AnyView(HelpBrowseCards(close: close)), close: close)
            } else {
                HelpTopicsList(close: close)
            }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: Self.screen,
                AnalyticsParameterScreenClass: "HelpView",
                "page": page.rawValue
            ])
        }
    }

    /// Closes the whole sheet, from the front page or a section.
    private func close() {
        dismiss()
    }
}

/// Help's front page where Apple Intelligence can't answer: every section,
/// with the links to report a bug, ask for a feature and see what's new, and
/// a search across all the topics.
private struct HelpTopicsList: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var whatsNew = WhatsNewService.shared

    let close: () -> Void

    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The topics with any of the words searched for, best match first.
    private var results: [(section: String, topic: HelpTopic)] {
        HelpLibrary.search(trimmedQuery)
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                frontPage
            } else {
                Section {
                    ForEach(results, id: \.topic.id) { result in
                        HelpTopicRow(topic: result.topic, section: result.section, isExpanded: true)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        // The list's own gap above the first group is too much under the
        // search field.
        .contentMargins(.top, 8, for: .scrollContent)
        .overlay {
            if !trimmedQuery.isEmpty && results.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Help")
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    AnalyticsEvents.logButtonClick("help_topics_done", screen: HelpView.screen)
                    close()
                }
            }
        }
    }

    @ViewBuilder
    private var frontPage: some View {
        // Only where the iPhone has Apple Intelligence to answer with. While
        // it isn't ready, the page says why.
        if OnDeviceModelAvailability.forAskAI != .unsupported {
            Section {
                NavigationLink {
                    HelpAssistantView(close: close)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppColors.purple(for: colorScheme))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Help AI")
                                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                BetaBadge()
                            }
                            Text("Answered on this iPhone with Apple Intelligence")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsEvents.logButtonClick("help_ask_ai", screen: HelpView.screen)
                })
            }
        }

        Section {
            Button {
                AnalyticsEvents.logButtonClick("report_bug", screen: HelpView.screen)
                openURL(AppLinks.bugReport)
            } label: {
                linkRow("Report a Bug", systemImage: "ladybug")
            }

            Button {
                AnalyticsEvents.logButtonClick("request_feature", screen: HelpView.screen)
                openURL(AppLinks.featureRequest)
            } label: {
                linkRow("Request a Feature", systemImage: "lightbulb")
            }

            if whatsNew.release != nil {
                Button {
                    AnalyticsEvents.logButtonClick("whats_new", screen: HelpView.screen)
                    whatsNew.show()
                } label: {
                    linkRow("What's New in \(whatsNew.version)", systemImage: "sparkles")
                }
            }
        }

        Section {
            ForEach(AllHelp.sections) { section in
                NavigationLink {
                    HelpSectionView(section: section, event: "section_\(section.id)", close: close)
                } label: {
                    HelpSectionLabel(section: section)
                }
            }
        }
    }

    private func linkRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .contentShape(Rectangle())
    }
}

/// A section's symbol, title and what's in it.
private struct HelpSectionLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let section: HelpSection

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text(section.summary)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
        .padding(.vertical, 2)
    }
}

/// The help to browse, under the question on the asking page: the links,
/// then the sections, each group on a card of its own. What's typed is a
/// question for AI, so it doesn't narrow them.
private struct HelpBrowseCards: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var whatsNew = WhatsNewService.shared

    let close: () -> Void

    var body: some View {
        sections
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse Help")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .padding(.top, 12)

            card {
                link("Report a Bug", systemImage: "ladybug", event: "report_bug_browse") {
                    openURL(AppLinks.bugReport)
                }
                divider
                link("Request a Feature", systemImage: "lightbulb", event: "request_feature_browse") {
                    openURL(AppLinks.featureRequest)
                }
                if whatsNew.release != nil {
                    divider
                    link("What's New in \(whatsNew.version)", systemImage: "sparkles", event: "whats_new_browse") {
                        whatsNew.show()
                    }
                }
            }

            card {
                ForEach(Array(AllHelp.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 { divider }
                    NavigationLink {
                        HelpSectionView(section: section, event: "section_\(section.id)_browse", close: close)
                    } label: {
                        row { HelpSectionLabel(section: section) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
    }

    private var divider: some View {
        Divider().padding(.leading, 58)
    }

    private func row<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        HStack {
            label()
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func link(_ title: LocalizedStringKey, systemImage: String, event: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            AnalyticsEvents.logButtonClick(event, screen: HelpView.screen)
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One section's topics, each closed to its title until it's tapped.
private struct HelpSectionView: View {
    let section: HelpSection
    /// What opening it is logged as, which says which list it came from.
    let event: String
    /// Closes the sheet. The page's own dismiss would only go back.
    let close: () -> Void

    var body: some View {
        List {
            ForEach(section.topics) { topic in
                HelpTopicRow(topic: topic)
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    AnalyticsEvents.logButtonClick("help_section_done", screen: HelpView.screen)
                    close()
                }
            }
        }
        .onAppear {
            AnalyticsEvents.logButtonClick(event, screen: HelpView.screen)
        }
    }
}

/// A topic's title, and its explanation once opened. Search results start
/// open, so the match shows, with the section they're from above the title.
private struct HelpTopicRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let topic: HelpTopic
    var section: String?
    @State var isExpanded = false

    var body: some View {
        Button {
            AnalyticsEvents.logButtonClick(isExpanded ? "help_topic_close" : "help_topic_open", screen: HelpView.screen)
            withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let section {
                    Text(section)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(topic.title)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                if isExpanded {
                    Text(topic.detail)
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Help Button

/// The question mark at the top right of a page, in a glass of its own rather
/// than grouped with the buttons beside it. Put last among the page's trailing
/// items, so it sits at the edge.
struct HelpToolbarItem: ToolbarContent {
    let page: HelpPage
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HelpButton(page: page, isPresented: $isPresented)
        }
    }
}

private struct HelpButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let page: HelpPage
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            AnalyticsEvents.logButtonClick("help_\(page.rawValue)", screen: page.rawValue)
            isPresented = true
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        }
        .accessibilityLabel("Help")
    }
}

extension View {
    /// The help sheet for `page`, opened by its `HelpToolbarItem`. Kept on the
    /// page rather than the button, so the sheet stays up if the button fades.
    func helpSheet(for page: HelpPage, isPresented: Binding<Bool>) -> some View {
        modifier(HelpSheet(page: page, isPresented: isPresented))
    }
}

/// Help, and once it's closed after questions were asked of Help AI, the
/// question of how helpful the answers were, unless it was already asked.
private struct HelpSheet: ViewModifier {
    let page: HelpPage
    @Binding var isPresented: Bool
    @State private var aiExperience: AIExperience?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                if let metrics = HelpFeedback.shared.finish() {
                    aiExperience = .help(metrics)
                }
            }) {
                HelpView(page: page)
            }
            .sheet(isPresented: Binding(
                get: { aiExperience != nil },
                set: { if !$0 { aiExperience = nil } }
            )) {
                if let aiExperience {
                    AIFeedbackSheet(experience: aiExperience)
                }
            }
    }
}
