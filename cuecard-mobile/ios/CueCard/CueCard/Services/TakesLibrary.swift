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

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        reload()
    }

    /// Photos can't be opened on one video, so this opens it where it was:
    /// on the library, newest videos first.
    static func openPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
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
}
