import AVFoundation
import Photos
import UIKit

/// A video in the photo library that was being recorded, for any part of it,
/// while the teleprompter was open on a script.
struct Take: Identifiable {
    let asset: PHAsset
    /// 1 for the script's first take, counting up.
    let number: Int

    var id: String { asset.localIdentifier }
    var recordedAt: Date { asset.creationDate ?? .distantPast }
    var duration: TimeInterval { asset.duration }
    /// Marked as a favorite in Photos.
    var isFavorite: Bool { asset.isFavorite }
}

/// The takes of one script, found in the photo library by when they were
/// recorded, and kept current as videos come and go.
@MainActor
final class TakesLibrary: NSObject, ObservableObject {
    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Oldest first.
    @Published private(set) var takes: [Take] = []
    /// The teleprompter has been open on the script, so it may have takes.
    @Published private(set) var hasSessions = false
    /// The tags and notes of each take, by take ID.
    @Published private(set) var details: [String: TakeDetails] = [:]

    private var scriptID: UUID?
    private var isObservingLibrary = false
    private var pendingReload: Task<Void, Never>?

    /// The longest a recording is taken to run. A video started further back
    /// than this before the teleprompter opened isn't looked at.
    private static let longestRecording: TimeInterval = 6 * 60 * 60

    var canRead: Bool { status == .authorized || status == .limited }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func load(scriptID: UUID) {
        self.scriptID = scriptID
        reload()
    }

    /// Look again, for a session just ended or a video just recorded.
    func reload() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard let scriptID else { return }
        let sessions = TakeStore.shared.sessions(for: scriptID)
        hasSessions = !sessions.isEmpty
        details = TakeStore.shared.details(for: scriptID)
        guard canRead, hasSessions else {
            takes = []
            return
        }

        if !isObservingLibrary {
            isObservingLibrary = true
            PHPhotoLibrary.shared().register(self)
        }
        takes = Self.videos(recordedDuring: sessions).enumerated().map { index, asset in
            Take(asset: asset, number: index + 1)
        }
    }

    func details(of take: Take) -> TakeDetails {
        details[take.id] ?? TakeDetails()
    }

    func setDetails(_ newDetails: TakeDetails, of take: Take) {
        guard let scriptID, newDetails != details(of: take) else { return }
        details[take.id] = newDetails.isEmpty ? nil : newDetails
        TakeStore.shared.setDetails(newDetails, ofTake: take.id, scriptID: scriptID)
    }

    /// Tags already given to the script's takes, the most used first.
    var usedTags: [String] {
        var counts: [String: Int] = [:]
        for tag in details.values.flatMap(\.tags) {
            counts[tag, default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        reload()
    }

    /// Mark the take as a favorite in Photos, or take the mark off.
    func setFavorite(_ isFavorite: Bool, of take: Take) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: take.asset).isFavorite = isFavorite
        }
        reload()
    }

    /// The user's own albums in Photos that a video can be put in, by name.
    func albums() -> [PHAssetCollection] {
        var albums: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { album, _, _ in
                if album.canPerform(.addContent) { albums.append(album) }
            }
        return albums.sorted {
            ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending
        }
    }

    /// The IDs of the albums the take is in.
    func albumIDs(holding take: Take) -> Set<String> {
        var ids: Set<String> = []
        PHAssetCollection.fetchAssetCollectionsContaining(take.asset, with: .album, options: nil)
            .enumerateObjects { album, _, _ in ids.insert(album.localIdentifier) }
        return ids
    }

    /// The names of the albums the take is in, in order.
    func albumTitles(holding take: Take) -> [String] {
        var titles: [String] = []
        PHAssetCollection.fetchAssetCollectionsContaining(take.asset, with: .album, options: nil)
            .enumerateObjects { album, _, _ in
                if let title = album.localizedTitle { titles.append(title) }
            }
        return titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Put the take in an album, or take it out.
    func setTake(_ take: Take, isIn: Bool, album: PHAssetCollection) async {
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest(for: album)
            if isIn {
                request?.addAssets([take.asset] as NSArray)
            } else {
                request?.removeAssets([take.asset] as NSArray)
            }
        }
    }

    /// Make a new album in Photos with the take in it.
    func addTake(_ take: Take, toNewAlbumNamed name: String) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .addAssets([take.asset] as NSArray)
        }
    }

    /// Videos whose recording overlaps a session, oldest first.
    private static func videos(recordedDuring sessions: [TeleprompterSession]) -> [PHAsset] {
        // A recording that overlaps a session started before it ended, and no
        // longer than the longest recording before it began. Overlapping
        // stretches are merged to keep the query short.
        var windows: [(start: Date, end: Date)] = []
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let start = session.start.addingTimeInterval(-longestRecording)
            if let last = windows.last, start <= last.end {
                windows[windows.count - 1].end = max(last.end, session.end)
            } else {
                windows.append((start, session.end))
            }
        }

        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: windows.map { window in
            NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                        window.start as NSDate, window.end as NSDate)
        })
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var videos: [PHAsset] = []
        PHAsset.fetchAssets(with: .video, options: options).enumerateObjects { asset, _, _ in
            guard let start = asset.creationDate else { return }
            let end = start.addingTimeInterval(max(asset.duration, 0))
            if sessions.contains(where: { $0.overlaps(start: start, end: end) }) {
                videos.append(asset)
            }
        }
        return videos
    }
}

extension TakesLibrary: PHPhotoLibraryChangeObserver {
    /// Changes come in bursts, a video being saved or iCloud catching up, so
    /// a burst is looked at once it settles.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            pendingReload?.cancel()
            pendingReload = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                reload()
            }
        }
    }
}

extension PHAsset {
    /// The video's first frame, or as near as the library has, at `size` points.
    func thumbnail(size: CGSize, scale: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        // A take kept only in iCloud still shows its picture.
        options.isNetworkAccessAllowed = true
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: self, targetSize: pixels, contentMode: .aspectFill,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// The video ready to play, once enough of it is on the device.
    func playerItem() async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        // A take kept only in iCloud comes down to play.
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: self, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
