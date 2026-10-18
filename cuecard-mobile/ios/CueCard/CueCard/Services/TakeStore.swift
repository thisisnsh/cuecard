import Foundation

/// A stretch of time the teleprompter was open on a script: playing, paused,
/// restarted or floating over another app. A video recorded during any part
/// of one is a take of that script.
struct TeleprompterSession: Codable, Equatable {
    let start: Date
    var end: Date

    /// Whether any of `start..<end` falls inside this session.
    func overlaps(start: Date, end: Date) -> Bool {
        start < self.end && self.start < end
    }
}

/// When the teleprompter was open on each script, kept in the app's own
/// storage on this device, a folder for each script. A script is filed under
/// its saved note's ID, or the ID it will be saved under.
@MainActor
final class TakeStore {
    static let shared = TakeStore()

    private let fileManager = FileManager.default
    private let root: URL?
    /// The script the teleprompter is open on, and its sessions so far, the
    /// last one still going.
    private var open: (scriptID: UUID, sessions: [TeleprompterSession])?
    private var heartbeat: Timer?

    /// How often the open session's end is moved up to now. If the app is
    /// quit with the teleprompter up, the session loses no more than this.
    private static let heartbeatInterval: TimeInterval = 2
    /// A heartbeat this late means the app wasn't running in between: it was
    /// suspended with the teleprompter open but nowhere on screen. That time
    /// isn't counted, and a new session starts from now.
    private static let maxGap: TimeInterval = 10

    private init() {
        root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Takes", isDirectory: true)
    }

    /// Every session the teleprompter was open on a script, oldest first.
    func sessions(for scriptID: UUID) -> [TeleprompterSession] {
        if let open, open.scriptID == scriptID { return open.sessions }
        guard let url = sessionsFile(of: scriptID), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TeleprompterSession].self, from: data)) ?? []
    }

    /// Start counting the teleprompter as open on `scriptID`.
    func begin(scriptID: UUID) {
        end()
        let now = Date()
        open = (scriptID, sessions(for: scriptID) + [TeleprompterSession(start: now, end: now)])
        writeOpenSessions()

        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { _ in
            Task { @MainActor in TakeStore.shared.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// The teleprompter closed. Nothing happens if it wasn't open.
    func end() {
        heartbeat?.invalidate()
        heartbeat = nil
        guard open != nil else { return }
        beat(startingOver: false)
        open = nil
    }

    private func beat() {
        beat(startingOver: true)
    }

    /// Move the open session's end up to now, or, after a gap, leave it where
    /// it was and start another.
    private func beat(startingOver: Bool) {
        guard var open, let last = open.sessions.last else { return }
        let now = Date()
        if now.timeIntervalSince(last.end) > Self.maxGap {
            guard startingOver else { return }
            open.sessions.append(TeleprompterSession(start: now, end: now))
        } else {
            open.sessions[open.sessions.count - 1].end = now
        }
        self.open = open
        writeOpenSessions()
    }

    func remove(scriptID: UUID) {
        guard let folder = folder(of: scriptID) else { return }
        try? fileManager.removeItem(at: folder)
    }

    func removeAll() {
        guard let root else { return }
        try? fileManager.removeItem(at: root)
    }

    // MARK: - Files

    private func folder(of scriptID: UUID) -> URL? {
        root?.appendingPathComponent(scriptID.uuidString, isDirectory: true)
    }

    private func sessionsFile(of scriptID: UUID) -> URL? {
        folder(of: scriptID)?.appendingPathComponent("sessions.json")
    }

    private func writeOpenSessions() {
        guard let open, let folder = folder(of: open.scriptID), let url = sessionsFile(of: open.scriptID),
              let data = try? JSONEncoder().encode(open.sessions) else { return }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
