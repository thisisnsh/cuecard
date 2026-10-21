import SwiftUI
import FirebaseAnalytics

// MARK: - Pages

/// The screens with a help button. Every one shows the same help; the page
/// only tells analytics where it was opened.
enum HelpPage: String {
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

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) || detail.localizedCaseInsensitiveContains(query)
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

    /// The same section with only the topics that match `query`.
    func filtered(by query: String) -> HelpSection {
        var section = self
        section.topics = topics.filter { $0.matches(query) }
        return section
    }
}

// MARK: - Topics

private enum AllHelp {
    static let writing = HelpSection("writing", title: "Writing",
                                    summary: "Modes, cues, formatting and cards",
                                    systemImage: "pencil", topics: [
        HelpTopic("Pick a Mode",
                  detail: "Tap the mode name at the top. Teleprompter scrolls your whole script. Cards shows it one card at a time."),
        HelpTopic("Add Cues",
                  detail: "Cues are reminders like [cue pause], shown in color and not read out. Type [ or tap Add Cue above the keyboard."),
        HelpTopic("Bold and Italic",
                  detail: "Select words and tap B or I above the keyboard. Or type *bold* or _italic_."),
        HelpTopic("Add Cards",
                  detail: "Each box in the editor is one card. Tap Create New Card to add another.")
    ])

    static let notes = HelpSection("notes", title: "Notes & Saving",
                                    summary: "Save, open, import, versions and sharing",
                                    systemImage: "folder", topics: [
        HelpTopic("Save Your Work",
                  detail: "Unsaved above Play means there are changes to save. Tap it to save, or tap ••• › Save."),
        HelpTopic("Open Saved Notes",
                  detail: "Tap ••• › Open to see everything you saved. Swipe to rename or delete."),
        HelpTopic("Import a Text File",
                  detail: "Tap ••• › Import. The file opens in the editor and is kept as a saved note."),
        HelpTopic("Go Back to an Older Version",
                  detail: "Every save is a new version. Once a note has more than one, tap the clock at the top to compare changes and restore one."),
        HelpTopic("Keep Notes if the App Is Removed",
                  detail: "Notes stay on this device and are deleted with the app. In Saved Notes, choose a notes folder from ••• to keep them as files."),
        HelpTopic("Share a Script",
                  detail: "Tap ••• › Share to send it as text, cues included.")
    ])

    static let settings = HelpSection("settings", title: "Settings & Timer",
                                    summary: "Text size, colors, timer and countdown",
                                    systemImage: "gearshape", topics: [
        HelpTopic("Change Text Size and Colors",
                  detail: "Tap the gear at the top. Each mode keeps its own sizes and cue color."),
        HelpTopic("Set a Timer",
                  detail: "Tap the timer next to Play to set how long you have, when it warns you, and the colors it turns."),
        HelpTopic("Count Down Before Scrolling",
                  detail: "In the teleprompter's timer, set a Countdown to get a few seconds before the script starts scrolling.")
    ])

    static let teleprompter = HelpSection("teleprompter", title: "Teleprompter",
                                    summary: "Scrolling, speed and the floating window",
                                    systemImage: "text.alignleft", topics: [
        HelpTopic("Play and Pause",
                  detail: "The buttons fade while the script scrolls so they stay out of the way. Tap the screen to show them again."),
        HelpTopic("Scroll by Hand",
                  detail: "Drag the script to go back or skip ahead. It keeps scrolling from where you leave it."),
        HelpTopic("Change Speed",
                  detail: "Scroll Speed in Settings sets how many lines pass each minute."),
        HelpTopic("Use Over Other Apps",
                  detail: "Leave CueCard while the teleprompter is open and your script keeps going in a floating window, handy on video calls."),
        HelpTopic("Know When Time Is Running Out",
                  detail: "The timer changes color when you're near the end and again once you're over time. Pick the colors in the timer.")
    ])

    static let cards = HelpSection("cards", title: "Cards",
                                    summary: "Turning cards and the Lock Screen",
                                    systemImage: "rectangle.on.rectangle", topics: [
        HelpTopic("Turn Cards",
                  detail: "Swipe, or tap Back and Next. The dots at the top show which card you're on."),
        HelpTopic("Read from the Lock Screen",
                  detail: "Turn on Show on Lock Screen in Settings. Then lock your iPhone and turn cards right from the Lock Screen."),
        HelpTopic("Count Up Without a Timer",
                  detail: "The time at the top counts down your timer. With no timer set, it counts up from when you started.")
    ])

    static let takes = HelpSection("takes", title: "Takes",
                                    summary: "The videos you record with a script",
                                    systemImage: "film.stack", topics: [
        HelpTopic("Find Your Takes",
                  detail: "Videos you record while the teleprompter is open, even floating over the camera, are kept as takes of the script. Tap the film button next to Play to see them."),
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
                  detail: "Open a saved deck and tap ••• › Keep on Apple Watch. Then you can read it without your iPhone."),
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

// MARK: - Help Sheet

/// The same help on every page: a front page of sections, each opening to
/// its topics, with a search across all of them.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var whatsNew = WhatsNewService.shared

    let page: HelpPage

    @State private var query = ""

    fileprivate static let screen = "help"

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The sections with a topic that matches the search.
    private var results: [HelpSection] {
        AllHelp.sections
            .map { $0.filtered(by: trimmedQuery) }
            .filter { !$0.topics.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    frontPage
                } else {
                    ForEach(results) { section in
                        Section(section.title) {
                            ForEach(section.topics) { topic in
                                HelpTopicRow(topic: topic, isExpanded: true)
                            }
                        }
                    }
                }
            }
            .overlay {
                if !trimmedQuery.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .searchable(text: $query, prompt: "Search Help")
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: close)
                }
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

    @ViewBuilder
    private var frontPage: some View {
        Section {
            ForEach(AllHelp.sections) { section in
                NavigationLink {
                    HelpSectionView(section: section, close: close)
                } label: {
                    sectionRow(section)
                }
            }
        }

        Section {
            if whatsNew.release != nil {
                Button {
                    AnalyticsEvents.logButtonClick("whats_new", screen: Self.screen)
                    whatsNew.show()
                } label: {
                    linkRow("What's New in \(whatsNew.version)", systemImage: "sparkles")
                }
            }
        }

        Section("Email Support") {
            Button {
                AnalyticsEvents.logButtonClick("report_bug", screen: Self.screen)
                openURL(AppLinks.bugReport)
            } label: {
                linkRow("Report a Bug", systemImage: "ladybug")
            }

            Button {
                AnalyticsEvents.logButtonClick("request_feature", screen: Self.screen)
                openURL(AppLinks.featureRequest)
            } label: {
                linkRow("Request a Feature", systemImage: "lightbulb")
            }
        }
    }

    /// Closes the whole sheet, from the front page or a section.
    private func close() {
        AnalyticsEvents.logButtonClick("done", screen: Self.screen)
        dismiss()
    }

    private func sectionRow(_ section: HelpSection) -> some View {
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

/// One section's topics, each closed to its title until it's tapped.
private struct HelpSectionView: View {
    let section: HelpSection
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
                Button("Done", action: close)
            }
        }
        .onAppear {
            AnalyticsEvents.logButtonClick("section_\(section.id)", screen: HelpView.screen)
        }
    }
}

/// A topic's title, and its explanation once opened. Search results start
/// open, so the match shows.
private struct HelpTopicRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let topic: HelpTopic
    @State var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
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
            AnalyticsEvents.logButtonClick("help", screen: page.rawValue)
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
        sheet(isPresented: isPresented) {
            HelpView(page: page)
        }
    }
}
