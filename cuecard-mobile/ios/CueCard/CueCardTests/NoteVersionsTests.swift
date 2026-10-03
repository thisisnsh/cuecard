import Foundation
import Testing
@testable import CueCard

/// Runs against the host app's own version store, so every test works on a
/// note of its own and removes it when done.
@Suite("Note versions")
@MainActor
struct NoteVersionsTests {
    private let versions = NoteVersions()

    private func note(_ id: UUID, _ content: String, at seconds: TimeInterval = 0) -> SavedNote {
        SavedNote(id: id, title: "Test", content: content, mode: .teleprompter,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func recordsEachNewTextOnce() {
        let id = UUID()
        defer { versions.remove(id: id) }

        #expect(versions.record(note(id, "One")) == 1)
        #expect(versions.record(note(id, "One")) == 1)
        #expect(versions.record(note(id, "Two")) == 2)
        #expect(versions.versions(of: id).map(\.content) == ["One", "Two"])
        #expect(versions.versions(of: id).map(\.number) == [1, 2])
    }

    @Test func noteSavedBeforeVersionsStartsWithWhatItHeld() {
        let id = UUID()
        defer { versions.remove(id: id) }

        let count = versions.record(note(id, "New", at: 20), previous: note(id, "Old", at: 10))
        #expect(count == 2)
        #expect(versions.versions(of: id).map(\.content) == ["Old", "New"])
        #expect(versions.versions(of: id).first?.createdAt == Date(timeIntervalSince1970: 10))
    }

    @Test func previousWithTheSameTextAddsNothingExtra() {
        let id = UUID()
        defer { versions.remove(id: id) }

        #expect(versions.record(note(id, "Same"), previous: note(id, "Same")) == 1)
    }

    @Test func restoreAddsACopyOnTop() {
        let id = UUID()
        defer { versions.remove(id: id) }

        versions.record(note(id, "One"))
        versions.record(note(id, "Two"))
        #expect(versions.record(note(id, "One"), restoredFrom: 1) == 3)

        let last = versions.versions(of: id).last
        #expect(last?.number == 3)
        #expect(last?.content == "One")
        #expect(last?.restoredFrom == 1)
    }

    @Test func countsAndRemoval() {
        let id = UUID()
        defer { versions.remove(id: id) }

        versions.record(note(id, "One"))
        versions.record(note(id, "Two"))
        #expect(versions.counts()[id] == 2)

        versions.remove(id: id)
        #expect(versions.counts()[id] == nil)
        #expect(versions.versions(of: id).isEmpty)
    }

    @Test func unknownNoteHasNoVersions() {
        #expect(versions.versions(of: UUID()).isEmpty)
    }
}
