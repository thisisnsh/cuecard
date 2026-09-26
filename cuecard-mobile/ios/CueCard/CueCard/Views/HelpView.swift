import SwiftUI
import FirebaseAnalytics

// MARK: - Pages

/// The screens with a help button. Every one shows the same help; the page
/// only tells analytics where it was opened.
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

// MARK: - Topics

private enum AllHelp {
    static let general = HelpSection(title: "General", topics: [
        HelpTopic("Pick a Mode",
                  detail: "Tap the mode name at the top left. Teleprompter scrolls your whole script. "
                      + "Cards shows it one card at a time."),
        HelpTopic("Add Cues",
                  detail: "Cues are reminders like [cue pause], shown in color and not meant to be read out. "
                      + "Type [ (square bracket) or tap + above the keyboard to add one."),
        HelpTopic("Set a Timer",
                  detail: "Tap the timer next to Play and choose how long you have to speak "
                      + "and when it warns you. It shows while you present."),
        HelpTopic("Save and Open",
                  detail: "Use the ••• menu to save your script or deck, or open one you saved. "
                      + "Import or export text files there too."),
        HelpTopic("Rename or Delete",
                  detail: "Everything you save is in Saved Content. "
                      + "Swipe right on one to rename it, or swipe left to delete it."),
        HelpTopic("Change Text Size",
                  detail: "Each mode keeps its own text size and colors in Settings. "
                      + "Tap Show Advanced Settings to type an exact size."),
        HelpTopic("Change Colors",
                  detail: "Pick colors that are easy for you to tell apart. "
                      + "Set the cue and timer colors in Settings.")
    ])

    static let teleprompter = HelpSection(title: "Teleprompter", topics: [
        HelpTopic("Play and Pause",
                  detail: "The buttons fade while the script scrolls so they stay out of the way. "
                      + "Tap the screen to show them again."),
        HelpTopic("Scroll by Hand",
                  detail: "Drag the script to go back or skip ahead. "
                      + "It keeps scrolling from where you leave it."),
        HelpTopic("Change Speed",
                  detail: "Scroll Speed in Settings sets how many lines pass each minute. "
                      + "Set a Countdown in the timer to get a few seconds before it starts."),
        HelpTopic("Use Over Other Apps",
                  detail: "Leave CueCard while the teleprompter is open and your script keeps going "
                      + "in a floating window, handy on video calls."),
        HelpTopic("Watch the Timer",
                  detail: "The timer changes color when you're near the end "
                      + "and again once you're over time. Pick the colors in Settings.")
    ])

    static let cards = HelpSection(title: "Cards", topics: [
        HelpTopic("Add Cards",
                  detail: "Each box in the editor is one card. "
                      + "Tap Create New Card to add another."),
        HelpTopic("Turn Cards",
                  detail: "Swipe, or tap Back and Next. "
                      + "The dots at the top show which card you're on."),
        HelpTopic("Read from the Lock Screen",
                  detail: "Turn on Show on Lock Screen in Settings. "
                      + "Then lock your iPhone and turn cards right from the Lock Screen."),
        HelpTopic("Watch the Timer",
                  detail: "The time at the top counts down your timer. "
                      + "With no timer set, it counts up from when you started.")
    ])

    static let appleWatch = HelpSection(title: "Apple Watch", topics: [
        HelpTopic("Install on Apple Watch",
                  detail: "Open the Watch app on your iPhone. "
                      + "Under Available Apps, tap Install next to CueCard."),
        HelpTopic("Control the Teleprompter",
                  detail: "Open a script on your iPhone. The watch shows its timer "
                      + "and can play, pause or go back 10 seconds."),
        HelpTopic("Read Cards on Your Wrist",
                  detail: "Open a deck on your iPhone and it shows on the watch too. "
                      + "Turning a card on either one moves both."),
        HelpTopic("Keep Decks on the Watch",
                  detail: "Open a saved deck and choose Keep on Apple Watch from the ••• menu. "
                      + "Then you can read it without your iPhone."),
        HelpTopic("Stay on Screen",
                  detail: "The watch goes back to the clock after a while. In the Watch app, go to "
                      + "General › Return to Clock › CueCard and set it to 1 hour.")
    ])

    /// The Play or Pause control needs iOS 18 and an iPhone with an Action button.
    static var actionButton: HelpSection? {
        guard #available(iOS 18.0, *), DeviceModel.hasActionButton else { return nil }
        return HelpSection(title: "Action Button", topics: [
            HelpTopic("Play or Pause the Teleprompter",
                      detail: "Start and stop scrolling without touching the screen. In the Settings app, "
                          + "go to Action Button › Controls and pick Play or Pause under CueCard.")
        ])
    }

    static var sections: [HelpSection] {
        [general, teleprompter, cards, appleWatch] + (actionButton.map { [$0] } ?? [])
    }
}

// MARK: - Help Sheet

/// The same help on every page, grouped by part of the app.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var whatsNew = WhatsNewService.shared

    let page: HelpPage

    @State private var query = ""

    private static let screen = "help"

    private var sections: [HelpSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return AllHelp.sections }

        return AllHelp.sections
            .map { HelpSection(title: $0.title, topics: $0.topics.filter { $0.matches(trimmed) }) }
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
