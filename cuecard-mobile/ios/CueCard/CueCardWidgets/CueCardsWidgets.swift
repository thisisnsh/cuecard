import ActivityKit
import SwiftUI
import WidgetKit

struct CueCardsEntry: TimelineEntry {
    let date: Date
    let state: CueCardsWidgetState?
}

struct CueCardsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CueCardsEntry {
        CueCardsEntry(date: .now, state: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CueCardsEntry) -> Void) {
        completion(CueCardsEntry(date: .now, state: context.isPreview ? .preview : CueCardsWidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CueCardsEntry>) -> Void) {
        completion(Timeline(entries: [CueCardsEntry(date: .now, state: CueCardsWidgetStore.read())], policy: .never))
    }
}

struct CueCardsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CueCardsWidgetStore.kind, provider: CueCardsProvider()) { entry in
            if #available(iOS 17.0, *) {
                CueCardsWidgetView(state: entry.state)
                    .containerBackground(.background, for: .widget)
            } else {
                CueCardsWidgetView(state: entry.state)
                    .padding()
            }
        }
        .configurationDisplayName("Cards")
        .description("Read your open deck and turn cards from your Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private struct CueCardsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let state: CueCardsWidgetState?

    var body: some View {
        if let state {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cards · \(state.progress)").font(.caption.weight(.semibold))
                    Text(state.text).font(.caption).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CueCardsSurface(state: state, lineLimit: family == .systemLarge ? 10 : 3,
                                textFont: family == .systemLarge ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("CueCard", systemImage: "rectangle.stack")
                    .font(.headline)
                Text("Open a deck in Cards mode to read it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Shared layout for Home Screen cards and the larger Lock Screen surface.
private struct CueCardsSurface: View {
    let state: CueCardsWidgetState
    var lineLimit = 3
    var textFont: Font = .body.weight(.semibold)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.title.isEmpty ? "Cards" : state.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.progress).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(state.text)
                .font(textFont)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if #available(iOS 17.0, *) {
                CueCardsButtons(state: state)
            } else {
                Text("Open CueCard to turn the card")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct CueCardsButtons: View {
    let state: CueCardsWidgetState

    var body: some View {
        HStack {
            Button(intent: MoveCueCardIntent(state: state, targetIndex: state.index - 1)) {
                Label("Back", systemImage: "chevron.left")
                    .frame(minHeight: 28)
            }
            .disabled(state.index == 0)
            Spacer(minLength: 8)
            Button(intent: MoveCueCardIntent(state: state, targetIndex: state.isFinished ? 0 : state.index + 1)) {
                Label(state.isFinished ? "Start Over" : (state.index == state.count - 1 ? "Finish" : "Next"),
                      systemImage: state.isFinished ? "arrow.counterclockwise" : "chevron.right")
                    .frame(minHeight: 28)
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.green)
    }
}

struct CueCardsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CueCardsActivityAttributes.self) { context in
            CueCardsSurface(state: context.state)
                .padding(12)
                .frame(height: 160)
                .activityBackgroundTint(Color(white: 0.12))
                .activitySystemActionForegroundColor(.white)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Cards", systemImage: "rectangle.stack")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress).font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.text).font(.body).lineLimit(3)
                        if #available(iOS 17.0, *) {
                            CueCardsButtons(state: context.state)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "rectangle.stack")
            } compactTrailing: {
                Text(context.state.isFinished ? "✓" : "\(context.state.index + 1)/\(context.state.count)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "rectangle.stack")
            }
        }
    }
}
