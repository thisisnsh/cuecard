import SwiftUI
import Photos

/// A take's picture, filled in once the library hands it over.
struct TakeThumbnail: View {
    let asset: PHAsset
    let size: CGSize
    var cornerRadius: CGFloat = 8
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: min(size.width, size.height) * 0.3))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: asset.localIdentifier) {
            image = await asset.thumbnail(size: size, scale: displayScale)
        }
    }
}

/// The script's takes beside the Play button: a small stack of their
/// pictures with the newest on top, or, before Photos can be read, a button
/// to go and find them.
struct TakeStack: View {
    let takes: [Take]
    let colorScheme: ColorScheme
    /// The Takes list grows out of the newest tile, or the button before
    /// there are any.
    let transition: Namespace.ID

    private static let tileSize = CGSize(width: 36, height: 48)
    /// The most tiles drawn; more takes than this only raise the count.
    private static let shownTiles = 3

    var body: some View {
        if takes.isEmpty {
            Image(systemName: "film.stack")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                .frame(width: 52, height: 52)
                .glassedEffect(in: Circle())
                .takesTransitionSource(in: transition, cornerRadius: 26)
                .accessibilityLabel("Takes")
        } else {
            stack
        }
    }

    private var stack: some View {
        let shown = Array(takes.suffix(Self.shownTiles))
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, take in
                // 0 for the newest, on top; each one under it tips further out.
                let depth = CGFloat(shown.count - 1 - index)
                TakeThumbnail(asset: take.asset, size: Self.tileSize)
                    // Only the top tile, the one not tipped, so the list closes
                    // into a tile its own shape and the ones under it stay put.
                    .takesTransitionSource(in: transition, cornerRadius: 8, isEnabled: depth == 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppColors.background(for: colorScheme), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .rotationEffect(.degrees(-8 * depth), anchor: .bottom)
                    .offset(x: -5 * depth)
            }
        }
        .frame(width: 52, height: 52)
        .overlay(alignment: .topTrailing) {
            if takes.count > 1 {
                Text("\(takes.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(AppColors.green(for: colorScheme)))
                    .offset(x: 2, y: -4)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(takes.count) Takes", comment: "How many videos were recorded with a script"))
    }
}

/// Every take of the script, newest first, to rate and tag. A take plays
/// right here.
struct TakesView: View {
    @ObservedObject var library: TakesLibrary
    /// The saved note's title, while the script is one.
    let scriptTitle: String?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows fan out of the stack they were opened from.
    @State private var hasAppeared = false
    /// The take whose tags and notes are open.
    @State private var editingTakeID: String?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if !library.canRead {
                    accessPrompt
                } else if library.takes.isEmpty {
                    message(title: "No Takes Yet",
                            detail: "Record a video while the teleprompter is open, even with it floating over the camera, and it shows up here.") {
                        if library.status == .limited { limitedAccessNote }
                    }
                } else {
                    list
                }
            }
            .navigationDestination(item: $editingTakeID) { id in
                if let take = library.takes.first(where: { $0.id == id }) {
                    TakeDetailsView(take: take, library: library)
                }
            }
            .navigationTitle("Takes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Takes")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        if let scriptTitle {
                            Text(scriptTitle)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: "takes")
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            library.reload()
            hasAppeared = true
        }
    }

    private var list: some View {
        let takes = Array(library.takes.reversed())
        return List {
            Section {
                ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                    row(for: take)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared || reduceMotion ? 0 : -24 * CGFloat(min(index, 6)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.85)
                            .delay(reduceMotion ? 0 : 0.03 * Double(min(index, 6))), value: hasAppeared)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                edit(take)
                            } label: {
                                Label("Tags and Notes", systemImage: "square.and.pencil")
                            }
                            .tint(AppColors.blue(for: colorScheme))
                        }
                        .contextMenu {
                            Button {
                                play(take)
                            } label: {
                                Label("Play", systemImage: "play")
                            }
                            Button {
                                edit(take)
                            } label: {
                                Label("Tags and Notes", systemImage: "square.and.pencil")
                            }
                        }
                }
            } footer: {
                VStack(spacing: 8) {
                    if library.status == .limited { limitedAccessNote }
                    Text("Tap a take to play it, or a star to rate it. Your videos stay in Photos, and nothing leaves this device.")
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
        }
    }

    private func play(_ take: Take) {
        AnalyticsEvents.logButtonClick("play_take", screen: "takes")
        TakesLibrary.play(take)
    }

    private func edit(_ take: Take) {
        AnalyticsEvents.logButtonClick("edit_take", screen: "takes")
        editingTakeID = take.id
    }

    /// The take's rating, set right here with a tap on a star.
    private func rating(of take: Take) -> Binding<Int> {
        Binding(
            get: { library.details(of: take).rating },
            set: { rating in
                AnalyticsEvents.logButtonClick("rate_take", screen: "takes")
                var details = library.details(of: take)
                details.rating = rating
                library.setDetails(details, of: take)
            }
        )
    }

    private func row(for take: Take) -> some View {
        let details = library.details(of: take)
        return HStack(alignment: .top, spacing: 12) {
            TakeThumbnail(asset: take.asset, size: CGSize(width: 54, height: 72))
                .overlay(alignment: .bottomTrailing) {
                    Text(TeleprompterParser.formatTime(Int(take.duration.rounded())))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take \(take.number)")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    Text(dateFormatter.string(from: take.recordedAt))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }

                StarRating(rating: rating(of: take), size: 15, colorScheme: colorScheme)

                if !details.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(details.tags, id: \.self) { tag in
                            TagLabel(tag: tag, colorScheme: colorScheme)
                        }
                    }
                }

                if !details.note.isEmpty {
                    Text(details.note)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button {
                edit(take)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Tags and Notes")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // The stars and the edit button take their own taps; anywhere else
        // plays the take.
        .onTapGesture { play(take) }
        .accessibilityAction(named: Text("Play")) { play(take) }
    }

    /// Before the videos can be looked through: why, and the way to allow it.
    @ViewBuilder
    private var accessPrompt: some View {
        if library.status == .notDetermined {
            message(title: "Find Your Takes",
                    detail: "CueCard can find the videos you record while the teleprompter is open, and keep each one with its script. They stay in Photos.") {
                Button {
                    AnalyticsEvents.logButtonClick("allow_photos", screen: "takes")
                    Task { await library.requestAccess() }
                } label: {
                    Text("Allow Access to Photos")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.green(for: colorScheme))
                .foregroundStyle(colorScheme == .dark ? .black : .white)
            }
        } else {
            message(title: "Find Your Takes",
                    detail: "CueCard can't see your photos, so it can't find the videos you recorded with this script. Allow access in Settings.") {
                settingsButton("Open Settings")
            }
        }
    }

    private var limitedAccessNote: some View {
        VStack(spacing: 8) {
            Text("CueCard can only see the videos you've chosen, so some takes may be missing.")
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            settingsButton("Change in Settings")
                .font(.caption.weight(.semibold))
        }
    }

    private func settingsButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            AnalyticsEvents.logButtonClick("photos_settings", screen: "takes")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func message<Actions: View>(title: LocalizedStringKey, detail: LocalizedStringKey,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))

            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)

            actions()
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// A take's rating, tags and notes, kept as they're changed.
private struct TakeDetailsView: View {
    let take: Take
    @ObservedObject var library: TakesLibrary
    @Environment(\.colorScheme) var colorScheme
    @State private var details = TakeDetails()
    @State private var hasLoaded = false
    @State private var newTag = ""
    @FocusState private var isAddingTag: Bool

    /// Offered until the script's takes have tags of their own to offer.
    private static let starterTags = [
        String(localized: "Best", comment: "A tag for a recorded take"),
        String(localized: "Usable", comment: "A tag for a recorded take"),
        String(localized: "Retake", comment: "A tag for a recorded take")
    ]
    private static let longestTag = 30

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Tags used on the script's other takes, then the starters, leaving out
    /// any this take already has.
    private var suggestedTags: [String] {
        (library.usedTags + Self.starterTags).reduce(into: [String]()) { tags, tag in
            if !tags.containsIgnoringCase(tag), !details.tags.containsIgnoringCase(tag) {
                tags.append(tag)
            }
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    TakeThumbnail(asset: take.asset, size: CGSize(width: 72, height: 96), cornerRadius: 10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateFormatter.string(from: take.recordedAt))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        Text(TeleprompterParser.formatTime(Int(take.duration.rounded())))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        Button {
                            AnalyticsEvents.logButtonClick("play_take", screen: "take_details")
                            TakesLibrary.play(take)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                    }
                }
            }

            Section("Rating") {
                StarRating(rating: $details.rating, size: 28, colorScheme: colorScheme)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }

            Section {
                if !details.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(details.tags, id: \.self) { tag in
                            TagButton(tag: tag, systemImage: "xmark", colorScheme: colorScheme) {
                                details.tags.removeAll { $0 == tag }
                            }
                            .accessibilityLabel(String(localized: "Remove \(tag)", comment: "Takes a tag off a take"))
                        }
                    }
                    .padding(.vertical, 4)
                }

                TextField("Add a Tag", text: $newTag)
                    .focused($isAddingTag)
                    .submitLabel(.done)
                    .onSubmit {
                        add(newTag)
                    }

                if !suggestedTags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestedTags, id: \.self) { tag in
                            TagButton(tag: tag, systemImage: "plus", isSuggestion: true, colorScheme: colorScheme) {
                                add(tag)
                            }
                            .accessibilityLabel(String(localized: "Add \(tag)", comment: "Puts a tag on a take"))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Tags")
            }

            Section("Notes") {
                TextField("What worked, and what to change next time", text: $details.note, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
        .navigationTitle("Take \(take.number)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            details = library.details(of: take)
        }
        .onChange(of: details) {
            guard hasLoaded else { return }
            library.setDetails(details, of: take)
        }
    }

    private func add(_ tag: String) {
        let tag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestTag))
        newTag = ""
        guard !tag.isEmpty, !details.tags.containsIgnoringCase(tag) else { return }
        AnalyticsEvents.logButtonClick("tag_take", screen: "take_details")
        details.tags.append(tag)
    }
}

/// One to five stars. A tap on the star already set clears the rating.
struct StarRating: View {
    @Binding var rating: Int
    let size: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? 0 : star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(star <= rating
                                         ? AppColors.yellow(for: colorScheme)
                                         : AppColors.textSecondary(for: colorScheme).opacity(0.5))
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0
                            ? String(localized: "Not rated")
                            : String(localized: "\(rating) of 5 stars", comment: "A take's rating"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}

/// A tag on a take, as it shows in the list.
private struct TagLabel: View {
    let tag: String
    let colorScheme: ColorScheme

    var body: some View {
        Text(tag)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppColors.blue(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppColors.blue(for: colorScheme).opacity(0.15)))
    }
}

/// A tag to take off, or a suggested one to put on.
private struct TagButton: View {
    let tag: String
    let systemImage: String
    var isSuggestion = false
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        let color = isSuggestion ? AppColors.textSecondary(for: colorScheme) : AppColors.blue(for: colorScheme)
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tag)
                    .lineLimit(1)
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(isSuggestion ? 0.12 : 0.15)))
        }
        // Inside a form row, so each tag takes only its own taps.
        .buttonStyle(.borderless)
    }
}

/// Views in rows, wrapping to a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let arrangement = arrange(subviews, width: proposal.width ?? .infinity)
        return arrangement.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: min(subview.sizeThatFits(.unspecified).width, bounds.width),
                                                     height: nil))
        }
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, min(x - spacing, maxWidth))
        }
        return (origins, CGSize(width: width, height: y + rowHeight))
    }
}

private extension Array where Element == String {
    func containsIgnoringCase(_ string: String) -> Bool {
        contains { $0.caseInsensitiveCompare(string) == .orderedSame }
    }
}

// MARK: - Opening the Takes

/// The stack on Home and the list opened from it share this, so the list
/// grows out of the stack.
private let takesTransitionID = "takes"

extension View {
    @ViewBuilder
    fileprivate func takesTransitionSource(in namespace: Namespace.ID, cornerRadius: CGFloat,
                                           isEnabled: Bool = true) -> some View {
        if #available(iOS 18.0, *), isEnabled {
            matchedTransitionSource(id: takesTransitionID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomsFromTakes(in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: takesTransitionID, in: namespace))
        } else {
            self
        }
    }
}
