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

/// Every take of the script, newest first. A take opens in Photos.
struct TakesView: View {
    @ObservedObject var library: TakesLibrary
    /// The saved note's title, while the script is one.
    let scriptTitle: String?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows fan out of the stack they were opened from.
    @State private var hasAppeared = false

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
                    Button {
                        AnalyticsEvents.logButtonClick("open_take", screen: "takes")
                        TakesLibrary.openPhotos()
                    } label: {
                        row(for: take)
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : -24 * CGFloat(min(index, 6)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.85)
                        .delay(reduceMotion ? 0 : 0.03 * Double(min(index, 6))), value: hasAppeared)
                }
            } footer: {
                VStack(spacing: 8) {
                    if library.status == .limited { limitedAccessNote }
                    Text("Tap a take to open Photos. Your videos stay there, and nothing leaves this device.")
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
        }
    }

    private func row(for take: Take) -> some View {
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Take \(take.number)")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text(dateFormatter.string(from: take.recordedAt))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.forward.app")
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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

// MARK: - Opening the Takes

/// The stack on Home and the list opened from it share this, so the list
/// grows out of the stack.
private let takesTransitionID = "takes"

extension View {
    @ViewBuilder
    func takesTransitionSource(in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: takesTransitionID, in: namespace)
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
