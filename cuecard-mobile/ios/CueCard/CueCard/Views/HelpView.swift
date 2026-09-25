import SwiftUI
import FirebaseAnalytics

// MARK: - Pages

/// The screens with a help button. Each one's help leads with its own topics,
/// then the Apple Watch and the Action button as they work there.
enum HelpPage: String {
    case writingTeleprompter = "home_teleprompter"
    case writingCards = "home_cards"
    case settings
    case savedContent = "saved_notes"
    case teleprompter
    case cards

    /// The editor's page for the mode it's writing in.
    static func writing(_ mode: ScriptMode) -> HelpPage {
        mode == .cards ? .writingCards : .writingTeleprompter
    }

    var title: String {
        switch self {
        case .writingTeleprompter: return "Writing a Script"
        case .writingCards: return "Writing Cards"
        case .settings: return "Settings"
        case .savedContent: return "Saved Content"
        case .teleprompter: return "Teleprompter"
        case .cards: return "Cards"
        }
    }

    /// Which mode the page is about, if only one.
    private var mode: ScriptMode? {
        switch self {
        case .writingTeleprompter, .teleprompter: return .teleprompter
        case .writingCards, .cards: return .cards
        case .settings, .savedContent: return nil
        }
    }

    var topics: [HelpTopic] {
        switch self {
        case .writingTeleprompter:
            return [
                WritingHelp.pickMode,
                HelpTopic("Add Cues",
                          detail: "Type [ or tap + above the keyboard to add a cue, like [cue pause]. "
                              + "Cues show in color, as reminders rather than words to say."),
                HelpTopic("Set a Timer",
                          detail: "Tap the timer beside Play to set how long you have. "
                              + "It turns yellow near the end and red once you're over."),
                HelpTopic("Save and Open",
                          detail: "The ••• menu saves your script, opens saved ones, "
                              + "and imports or exports text files.")
            ]
        case .writingCards:
            return [
                WritingHelp.pickMode,
                HelpTopic("Write Cards",
                          detail: "Each box is one card. Tap Create New Card for another."),
                HelpTopic("Add Cues",
                          detail: "Type [ or tap + above the keyboard to add a cue, like [cue pause]. "
                              + "Cues show in color, as reminders rather than words to say."),
                HelpTopic("Set a Timer",
                          detail: "Tap the timer beside Play to set how long you have. "
                              + "The time on your cards counts it down."),
                HelpTopic("Save and Open",
                          detail: "The ••• menu saves your deck, opens saved ones, "
                              + "and imports or exports text files.")
            ]
        case .settings:
            return [
                HelpTopic("Settings for Each Mode",
                          detail: "Settings show the mode you're writing in. "
                              + "Teleprompter and Cards each keep their own sizes and colors."),
                HelpTopic("Start Delay and Scroll Speed",
                          detail: "Start Delay counts down before the script moves. "
                              + "Scroll Speed is how many lines pass each minute."),
                HelpTopic("Exact Sizes",
                          detail: "Tap Show Advanced Settings to type a text size the presets don't offer.")
            ]
        case .savedContent:
            return [
                HelpTopic("Open",
                          detail: "Tap a script or deck to open it in the editor."),
                HelpTopic("Rename or Delete",
                          detail: "Swipe right to rename, or swipe left to delete.")
            ]
        case .teleprompter:
            return [
                HelpTopic("Play and Pause",
                          detail: "The buttons fade while the script scrolls. Tap the screen to bring them back."),
                HelpTopic("Scroll by Hand",
                          detail: "Drag the script to go back or ahead. It carries on from where you leave it."),
                HelpTopic("Floating Window",
                          detail: "Keeps your script over other apps, like a video call. "
                              + "It opens by itself when you leave CueCard.")
            ]
        case .cards:
            return [
                HelpTopic("Turn Cards",
                          detail: "Swipe, or tap Back and Next. The dots at the top show where you are."),
                HelpTopic("Read from the Lock Screen",
                          detail: "With Show on Lock Screen on in Settings, lock your iPhone "
                              + "and turn cards from the Live Activity."),
                HelpTopic("Timer",
                          detail: "The time at the top counts down your timer, "
                              + "or up from when the deck opened.")
            ]
        }
    }

    /// The watch topics for this page's mode, or all of them on a page for both.
    fileprivate var appleWatch: HelpSection {
        switch mode {
        case .teleprompter: return SharedHelp.appleWatchTeleprompter
        case .cards: return SharedHelp.appleWatchCards
        case nil: return SharedHelp.appleWatch
        }
    }

    /// The Action button plays and pauses the teleprompter, so only its pages
    /// bring it up.
    fileprivate var controls: HelpSection? {
        mode == .cards ? nil : SharedHelp.actionButton
    }
}

private enum WritingHelp {
    static let pickMode = HelpTopic("Pick a Mode",
                                    detail: "Tap the mode's name at the top left. Teleprompter scrolls your script; "
                                        + "Cards shows it one card at a time.")
}

struct HelpTopic: Identifiable {
    let title: String
    let detail: String

    var id: String { title }

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) || detail.localizedCaseInsensitiveContains(query)
    }
}

private struct HelpSection: Identifiable {
    let title: String
    let topics: [HelpTopic]

    var id: String { title }
}

// MARK: - Topics Across the App

private enum SharedHelp {
    private static let install = HelpTopic("Install on Apple Watch",
                                           detail: "Open the Watch app on your iPhone. Under Available Apps, tap Install next to CueCard.")
    private static let remote = HelpTopic("Teleprompter Remote",
                                          detail: "While a script is open on your iPhone, the watch shows its timer "
                                              + "and can play, pause or go back 10 seconds.")
    private static let cardsOnWrist = HelpTopic("Cards on Your Wrist",
                                                detail: "A deck open on your iPhone shows on the watch too, "
                                                    + "and turning a card on either moves both.")
    private static let keepDecks = HelpTopic("Keep Decks on the Watch",
                                             detail: "Open a saved deck and choose Keep on Apple Watch from the ••• menu "
                                                 + "to read it even without your iPhone.")
    private static let stayOnScreen = HelpTopic("Stay on Screen",
                                                detail: WatchTips.returnToClock)

    static let appleWatch = HelpSection(title: "Apple Watch",
                                        topics: [install, remote, cardsOnWrist, keepDecks, stayOnScreen])
    static let appleWatchTeleprompter = HelpSection(title: "Apple Watch",
                                                    topics: [install, remote, stayOnScreen])
    static let appleWatchCards = HelpSection(title: "Apple Watch",
                                             topics: [install, cardsOnWrist, keepDecks, stayOnScreen])

    /// The Play or Pause control needs iOS 18 and an iPhone with an Action button.
    static var actionButton: HelpSection? {
        guard #available(iOS 18.0, *), DeviceModel.hasActionButton else { return nil }
        return HelpSection(title: "Action Button", topics: [
            HelpTopic("Play or Pause with the Action Button",
                      detail: "In the Settings app, go to Action Button, choose Controls, "
                          + "and pick Play or Pause under CueCard.")
        ])
    }
}

// MARK: - Help Sheet

/// A few lines on the page it was opened from and on what works across the
/// app. Searching looks through every page's help, not only this one's.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var whatsNew = WhatsNewService.shared

    let page: HelpPage

    @State private var query = ""

    private static let screen = "help"

    private static let allPages: [HelpPage] = [
        .writingTeleprompter, .writingCards, .teleprompter, .cards, .savedContent, .settings
    ]

    private var sections: [HelpSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return [HelpSection(title: page.title, topics: page.topics), page.appleWatch]
                + (page.controls.map { [$0] } ?? [])
        }

        // Every topic once: the watch and Action button in full, not per page.
        let pages = [page] + Self.allPages.filter { $0 != page }
        let shared = [SharedHelp.appleWatch] + (SharedHelp.actionButton.map { [$0] } ?? [])
        // Both editors share some topics; list each under the first page with it.
        var seen = Set<String>()
        return (pages.map { HelpSection(title: $0.title, topics: $0.topics) } + shared)
            .map { section in
                HelpSection(title: section.title, topics: section.topics.filter {
                    $0.matches(trimmed) && seen.insert($0.title).inserted
                })
            }
            .filter { !$0.topics.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty && whatsNew.release != nil {
                    Section {
                        Button {
                            AnalyticsEvents.logButtonClick("whats_new", screen: Self.screen)
                            whatsNew.show()
                        } label: {
                            HStack {
                                Text("What's New in \(whatsNew.version)")
                                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }

                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.topics) { topic in
                            row(topic)
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search Help")
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: Self.screen)
                        dismiss()
                    }
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

    private func row(_ topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.title)
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            Text(topic.detail)
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 2)
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
