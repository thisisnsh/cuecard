import SwiftUI
import FirebaseAnalytics

// MARK: - Pages

/// The screens with a help button. Each one's help leads with its own topics,
/// then what works across the app: the Apple Watch and the Action button.
enum HelpPage: String {
    case home
    case settings
    case savedContent = "saved_notes"
    case teleprompter
    case cards

    var title: String {
        switch self {
        case .home: return "Writing"
        case .settings: return "Settings"
        case .savedContent: return "Saved Content"
        case .teleprompter: return "Teleprompter"
        case .cards: return "Cards"
        }
    }

    var topics: [HelpTopic] {
        switch self {
        case .home:
            return [
                HelpTopic("Pick a Mode", systemImage: "rectangle.stack",
                          detail: "Tap the icon at the top left. Teleprompter scrolls your script; "
                              + "Cards shows it one card at a time."),
                HelpTopic("Add Cues", systemImage: "plus",
                          detail: "Type [ or tap + above the keyboard to add a cue, like [cue pause]. "
                              + "Cues show in color, as reminders rather than words to say."),
                HelpTopic("Write Cards", systemImage: "rectangle.stack.badge.plus",
                          detail: "In Cards mode, each box is one card. Tap Create New Card for another."),
                HelpTopic("Set a Timer", systemImage: "timer",
                          detail: "Tap the timer beside Play to set how long you have. "
                              + "It turns yellow near the end and red once you're over."),
                HelpTopic("Save and Open", systemImage: "ellipsis.circle",
                          detail: "The ••• menu saves your script, opens saved ones, "
                              + "and imports or exports text files.")
            ]
        case .settings:
            return [
                HelpTopic("Settings for Each Mode", systemImage: "slider.horizontal.3",
                          detail: "Settings show the mode you're writing in. "
                              + "Teleprompter and Cards each keep their own sizes and colors."),
                HelpTopic("Start Delay and Scroll Speed", systemImage: "speedometer",
                          detail: "Start Delay counts down before the script moves. "
                              + "Scroll Speed is how many lines pass each minute."),
                HelpTopic("Exact Sizes", systemImage: "textformat.size",
                          detail: "Tap Show Advanced Settings to type a text size the presets don't offer.")
            ]
        case .savedContent:
            return [
                HelpTopic("Open", systemImage: "folder",
                          detail: "Tap a script or deck to open it in the editor."),
                HelpTopic("Rename or Delete", systemImage: "hand.draw",
                          detail: "Swipe right to rename, or swipe left to delete.")
            ]
        case .teleprompter:
            return [
                HelpTopic("Play and Pause", systemImage: "playpause",
                          detail: "The buttons fade while the script scrolls. Tap the screen to bring them back."),
                HelpTopic("Scroll by Hand", systemImage: "hand.draw",
                          detail: "Drag the script to go back or ahead. It carries on from where you leave it."),
                HelpTopic("Floating Window", systemImage: "pip",
                          detail: "Keeps your script over other apps, like a video call. "
                              + "It opens by itself when you leave CueCard.")
            ]
        case .cards:
            return [
                HelpTopic("Turn Cards", systemImage: "hand.draw",
                          detail: "Swipe, or tap Back and Next. The dots at the top show where you are."),
                HelpTopic("Read from the Lock Screen", systemImage: "lock",
                          detail: "With Show on Lock Screen on in Settings, lock your iPhone "
                              + "and turn cards from the Live Activity."),
                HelpTopic("Timer", systemImage: "timer",
                          detail: "The time at the top counts down your timer, "
                              + "or up from when the deck opened.")
            ]
        }
    }
}

struct HelpTopic: Identifiable {
    let title: String
    let systemImage: String
    let detail: String

    var id: String { title }

    init(_ title: String, systemImage: String, detail: String) {
        self.title = title
        self.systemImage = systemImage
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
    static let appleWatch = HelpSection(title: "Apple Watch", topics: [
        HelpTopic("Install on Apple Watch", systemImage: "applewatch",
                  detail: "Open the Watch app on your iPhone. Under Available Apps, tap Install next to CueCard."),
        HelpTopic("Teleprompter Remote", systemImage: "playpause",
                  detail: "While a script is open on your iPhone, the watch shows its timer "
                      + "and can play, pause or go back 10 seconds."),
        HelpTopic("Cards on Your Wrist", systemImage: "rectangle.stack",
                  detail: "A deck open on your iPhone shows on the watch too, "
                      + "and turning a card on either moves both."),
        HelpTopic("Keep Decks on the Watch", systemImage: "applewatch.radiowaves.left.and.right",
                  detail: "Open a saved deck and choose Keep on Apple Watch from the ••• menu "
                      + "to read it even without your iPhone."),
        HelpTopic("Stay on Screen", systemImage: "clock.arrow.circlepath",
                  detail: WatchTips.returnToClock)
    ])

    /// The Play or Pause control needs iOS 18, and the Action button an
    /// iPhone that has one.
    static var controls: HelpSection? {
        guard #available(iOS 18.0, *) else { return nil }
        var topics: [HelpTopic] = []
        if DeviceModel.hasActionButton {
            topics.append(HelpTopic("Play or Pause with the Action Button", systemImage: "button.vertical.left.press",
                                    detail: "In the Settings app, go to Action Button, choose Controls, "
                                        + "and pick Play or Pause under CueCard."))
        }
        topics.append(HelpTopic("Control Center", systemImage: "switch.2",
                                detail: "Add CueCard's Play or Pause to Control Center or the Lock Screen. "
                                    + "It works while a script is open in the teleprompter."))
        return HelpSection(title: DeviceModel.hasActionButton ? "Action Button" : "Controls", topics: topics)
    }
}

// MARK: - Help Sheet

/// A few lines on the page it was opened from and on what works across the
/// app. Searching looks through every page's help, not only this one's.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let page: HelpPage

    @State private var query = ""

    private static let screen = "help"

    private static let allPages: [HelpPage] = [.home, .teleprompter, .cards, .savedContent, .settings]

    private var sections: [HelpSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let shared = [SharedHelp.appleWatch] + (SharedHelp.controls.map { [$0] } ?? [])

        guard !trimmed.isEmpty else {
            return [HelpSection(title: page.title, topics: page.topics)] + shared
        }

        let pages = [page] + Self.allPages.filter { $0 != page }
        return (pages.map { HelpSection(title: $0.title, topics: $0.topics) } + shared)
            .map { HelpSection(title: $0.title, topics: $0.topics.filter { $0.matches(trimmed) }) }
            .filter { !$0.topics.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
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
        .presentationDetents([.medium, .large])
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: Self.screen,
                AnalyticsParameterScreenClass: "HelpView",
                "page": page.rawValue
            ])
        }
    }

    private func row(_ topic: HelpTopic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: topic.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text(topic.detail)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
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
