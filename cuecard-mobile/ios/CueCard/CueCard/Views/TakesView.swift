import SwiftUI
import AVKit
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

/// The button beside Play that opens the script's takes.
struct TakesIcon: View {
    let count: Int
    let colorScheme: ColorScheme
    /// The Takes list grows out of this button, and closes back into it.
    let transition: Namespace.ID

    var body: some View {
        Image(systemName: "film.stack")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .frame(width: 52, height: 52)
            .glassedEffect(in: Circle())
            .takesTransitionSource(in: transition)
            .accessibilityLabel(count == 0
                                ? String(localized: "Takes")
                                : String(localized: "\(count) Takes", comment: "How many videos were recorded with a script"))
    }
}

/// Every take of the script, newest first, opening into playback and details.
struct TakesView: View {
    @ObservedObject var library: TakesLibrary
    /// The saved note's title, while the script is one.
    let scriptTitle: String?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows fan out of the stack they were opened from.
    @State private var hasAppeared = false
    /// The take playing.
    @State private var playingTake: Take?
    /// The take being put in albums.
    @State private var albumTake: Take?

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
            .fullScreenCover(item: $playingTake) { take in
                TakePlayerView(take: take, library: library)
            }
            .sheet(item: $albumTake) { take in
                AlbumPicker(take: take, library: library)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // Not a destructive role: that takes the row away at
                            // once, before iOS has asked whether to delete it.
                            Button {
                                AnalyticsEvents.logButtonClick("delete_take", screen: "takes")
                                Task { await library.delete(take) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(AppColors.red(for: colorScheme))
                        }
                        .contextMenu {
                            Button {
                                play(take)
                            } label: {
                                Label("Play", systemImage: "play")
                            }
                            favoriteButton(for: take)
                            Button {
                                addToAlbum(take)
                            } label: {
                                Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                }
            } footer: {
                VStack(spacing: 8) {
                    if library.status == .limited { limitedAccessNote }
                    Text("Tap a take to play it and add tags, notes and albums. Your videos stay in Photos, and nothing leaves this device.")
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
        playingTake = take
    }

    private func addToAlbum(_ take: Take) {
        AnalyticsEvents.logButtonClick("album_take", screen: "takes")
        albumTake = take
    }

    private func favoriteButton(for take: Take) -> some View {
        Button {
            AnalyticsEvents.logButtonClick("favorite_take", screen: "takes")
            Task { await library.setFavorite(!take.isFavorite, of: take) }
        } label: {
            if take.isFavorite {
                Label("Unfavorite", systemImage: "heart.slash")
            } else {
                Label("Favorite", systemImage: "heart")
            }
        }
    }

    private func row(for take: Take) -> some View {
        let details = library.details(of: take)
        return HStack(alignment: .center, spacing: 12) {
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

            FavoriteButton(take: take, library: library, size: 36, screen: "takes", colorScheme: colorScheme)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // The heart takes its own taps; anywhere else plays the take.
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

/// A take's preview and editable details, kept as they're changed.
private struct TakePlayerView: View {
    let take: Take
    @ObservedObject var library: TakesLibrary
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var player = AVPlayer()
    @State private var details = TakeDetails()
    @State private var hasLoaded = false
    @State private var newTag = ""
    @State private var albumTitles: [String] = []
    @State private var isPickingAlbums = false
    @FocusState private var isAddingTag: Bool

    private static let longestTag = 30

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// The take as the library has it now, so the heart keeps up with Photos.
    private var current: Take {
        library.takes.first { $0.id == take.id } ?? take
    }

    /// Tags on the script's other takes, leaving out any this take already
    /// has. A tag no take has any more isn't offered.
    private var suggestedTags: [String] {
        library.usedTags
            .filter { !details.tags.containsIgnoringCase($0) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recordingSummary
                    VideoPlayer(player: player)
                        .frame(height: videoHeight(in: proxy.size))
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    tagsCard
                    notesCard
                    albumsCard
                    deleteButton
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(AppColors.background(for: colorScheme).ignoresSafeArea())
        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        .tint(AppColors.blue(for: colorScheme))
        .sheet(isPresented: $isPickingAlbums, onDismiss: refreshAlbums) {
            AlbumPicker(take: take, library: library)
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            details = library.details(of: take)
            refreshAlbums()
        }
        .task { await startPlaying() }
        .onDisappear { player.pause() }
        .onChange(of: details) {
            guard hasLoaded else { return }
            library.setDetails(details, of: take)
        }
    }

    private var header: some View {
        HStack {
            Button {
                AnalyticsEvents.logButtonClick("close", screen: "take_player")
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            FavoriteButton(take: current, library: library, size: 44,
                           screen: "take_player", colorScheme: colorScheme)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .overlay {
            Text("Take \(take.number)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 60)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var recordingSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                recordingDate
                Spacer(minLength: 0)
                durationBadge
            }
            VStack(alignment: .leading, spacing: 10) {
                recordingDate
                durationBadge
            }
        }
    }

    private var recordingDate: some View {
        Text(dateFormatter.string(from: take.recordedAt))
            .font(.subheadline)
            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var durationBadge: some View {
        Label(TeleprompterParser.formatTime(Int(take.duration.rounded())), systemImage: "clock")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .fixedSize()
    }

    /// Respect the recording's shape while leaving room to discover its details.
    private func videoHeight(in size: CGSize) -> CGFloat {
        let width = min(680, max(0, size.width - 40))
        let aspectRatio = CGFloat(max(take.asset.pixelWidth, 1)) / CGFloat(max(take.asset.pixelHeight, 1))
        return min(width / aspectRatio, max(200, size.height * 0.48))
    }

    private var tagsCard: some View {
        detailCard("Tags", systemImage: "tag", color: AppColors.blue(for: colorScheme)) {
            if !details.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(details.tags, id: \.self) { tag in
                        TagButton(tag: tag, systemImage: "xmark", colorScheme: colorScheme) {
                            details.tags.removeAll { $0 == tag }
                        }
                        .accessibilityLabel(String(localized: "Remove \(tag)", comment: "Takes a tag off a take"))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a Tag", text: $newTag)
                    .focused($isAddingTag)
                    .submitLabel(.done)
                    .onSubmit { add(newTag) }
                    .padding(.leading, 12)

                Button {
                    add(newTag)
                    isAddingTag = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.blue(for: colorScheme))
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Add a Tag")
            }
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

            if !suggestedTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggestedTags, id: \.self) { tag in
                        TagButton(tag: tag, systemImage: "plus", isSuggestion: true, colorScheme: colorScheme) {
                            add(tag)
                        }
                        .accessibilityLabel(String(localized: "Add \(tag)", comment: "Puts a tag on a take"))
                    }
                }
            }
        }
    }

    private var notesCard: some View {
        detailCard("Notes", systemImage: "text.alignleft", color: AppColors.purple(for: colorScheme)) {
            TextField("What worked, and what to change next time", text: $details.note, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
                .accessibilityLabel("Notes")
        }
    }

    private var albumsCard: some View {
        detailCard("Albums", systemImage: "rectangle.stack", color: AppColors.yellow(for: colorScheme)) {
            if !albumTitles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(albumTitles.indices, id: \.self) { index in
                        Label(albumTitles[index], systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                }
                Divider()
            }

            Button {
                AnalyticsEvents.logButtonClick("album_take", screen: "take_player")
                isPickingAlbums = true
            } label: {
                HStack {
                    Label("Add to Album", systemImage: "plus")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.blue(for: colorScheme))
        }
    }

    private func detailCard<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                          color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            AnalyticsEvents.logButtonClick("delete_take", screen: "take_player")
            player.pause()
            Task {
                if await library.delete(take) { dismiss() }
            }
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.red(for: colorScheme))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Play from the start once the video is on hand, heard even with the
    /// ringer off. The audio session is set off the main thread, where it can hang.
    private func startPlaying() async {
        guard player.currentItem == nil, let item = await take.asset.playerItem() else { return }
        await Task.detached {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }.value
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func refreshAlbums() {
        albumTitles = library.albumTitles(holding: take)
    }

    private func add(_ tag: String) {
        let tag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestTag))
        newTag = ""
        guard !tag.isEmpty, !details.tags.containsIgnoringCase(tag) else { return }
        AnalyticsEvents.logButtonClick("tag_take", screen: "take_player")
        details.tags.append(tag)
    }
}

/// A heart that marks the take as a favorite in Photos, or takes the mark off.
private struct FavoriteButton: View {
    let take: Take
    @ObservedObject var library: TakesLibrary
    let size: CGFloat
    let screen: String
    let colorScheme: ColorScheme

    var body: some View {
        Button {
            AnalyticsEvents.logButtonClick("favorite_take", screen: screen)
            Task { await library.setFavorite(!take.isFavorite, of: take) }
        } label: {
            Image(systemName: take.isFavorite ? "heart.fill" : "heart")
                .font(size > 40 ? .title3 : .body)
                .foregroundStyle(take.isFavorite
                                 ? AppColors.red(for: colorScheme)
                                 : AppColors.textSecondary(for: colorScheme))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: take.isFavorite)
        .accessibilityLabel(take.isFavorite ? "Unfavorite" : "Favorite")
    }
}

/// The user's albums in Photos, ticked where the take is in one. A tap puts it
/// in or takes it out, and a new album can be made with it in.
private struct AlbumPicker: View {
    let take: Take
    @ObservedObject var library: TakesLibrary
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var albums: [PHAssetCollection] = []
    @State private var holdingIDs: Set<String> = []
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newName = ""
                        isNaming = true
                    } label: {
                        Label("New Album", systemImage: "plus")
                    }
                }

                if !albums.isEmpty {
                    Section {
                        ForEach(albums, id: \.localIdentifier) { album in
                            row(for: album)
                        }
                    }
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: "albums")
                        dismiss()
                    }
                }
            }
            .alert("New Album", isPresented: $isNaming) {
                TextField("Title", text: $newName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    AnalyticsEvents.logButtonClick("new_album", screen: "albums")
                    Task {
                        await library.addTake(take, toNewAlbumNamed: name)
                        refresh()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: refresh)
    }

    private func row(for album: PHAssetCollection) -> some View {
        let isIn = holdingIDs.contains(album.localIdentifier)
        return Button {
            AnalyticsEvents.logButtonClick(isIn ? "remove_from_album" : "add_to_album", screen: "albums")
            Task {
                await library.setTake(take, isIn: !isIn, album: album)
                refresh()
            }
        } label: {
            HStack {
                Text(album.localizedTitle ?? "")
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Spacer()
                if isIn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.blue(for: colorScheme))
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isIn ? .isSelected : [])
    }

    private func refresh() {
        albums = library.albums()
        holdingIDs = library.albumIDs(holding: take)
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
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
    /// The 52-point button's circle, as the only shape a source takes.
    @ViewBuilder
    fileprivate func takesTransitionSource(in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: takesTransitionID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
