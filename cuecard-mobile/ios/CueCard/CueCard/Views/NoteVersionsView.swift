import SwiftUI

/// A line-by-line comparison of two texts.
enum LineDiff {
    enum Kind { case same, added, removed }

    struct Line {
        let kind: Kind
        let text: String
    }

    static func lines(from old: String, to new: String) -> [Line] {
        let oldLines = split(old)
        let newLines = split(new)
        let difference = newLines.difference(from: oldLines)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Lines left alone pair up in order, so walking both sides together
        // puts each change where it belongs.
        var result: [Line] = []
        var i = 0
        var j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count, removed.contains(i) {
                result.append(Line(kind: .removed, text: oldLines[i]))
                i += 1
            } else if j < newLines.count, inserted.contains(j) {
                result.append(Line(kind: .added, text: newLines[j]))
                j += 1
            } else {
                result.append(Line(kind: .same, text: newLines[j]))
                i += 1
                j += 1
            }
        }
        return result
    }

    /// Lines added and removed going from `old` to `new`.
    static func counts(from old: String, to new: String) -> (added: Int, removed: Int) {
        let difference = split(new).difference(from: split(old))
        return (difference.insertions.count, difference.removals.count)
    }

    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

/// Every version of a saved note, newest first, to compare and restore.
struct NoteVersionsView: View {
    let noteID: UUID
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var versions: [NoteVersion] = []
    @State private var changes: [Int: (added: Int, removed: Int)] = [:]

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func reload() {
        versions = settingsService.versions(of: noteID)
        var changes: [Int: (added: Int, removed: Int)] = [:]
        for (previous, version) in zip(versions, versions.dropFirst()) {
            changes[version.number] = LineDiff.counts(from: previous.content, to: version.content)
        }
        self.changes = changes
    }

    private func previous(of version: NoteVersion) -> NoteVersion? {
        versions.last { $0.number < version.number }
    }

    var body: some View {
        NavigationStack {
            List(versions.reversed()) { version in
                NavigationLink(value: version.number) {
                    row(for: version)
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { number in
                if let version = versions.first(where: { $0.number == number }) {
                    VersionDiffView(version: version,
                                    previous: previous(of: version),
                                    isCurrent: version.number == versions.last?.number,
                                    onRestore: {
                                        settingsService.restoreVersion(version, of: noteID)
                                        dismiss()
                                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: "note_versions")
                        dismiss()
                    }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: settingsService.versionCounts[noteID]) {
                reload()
            }
        }
    }

    private func row(for version: NoteVersion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("v\(version.number)")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                if version.number == versions.last?.number {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.green(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.green(for: colorScheme).opacity(0.15)))
                }

                Spacer()

                if let change = changes[version.number] {
                    HStack(spacing: 6) {
                        Text("+\(change.added)")
                            .foregroundStyle(AppColors.green(for: colorScheme))
                        Text("−\(change.removed)")
                            .foregroundStyle(AppColors.red(for: colorScheme))
                    }
                    .font(.caption.monospacedDigit())
                }
            }

            Text(dateFormatter.string(from: version.createdAt))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))

            if let restored = version.restoredFrom {
                Text("Restored from v\(restored)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }
}

/// What a version changed, against the one before it or against the editor,
/// with a way to bring it back.
private struct VersionDiffView: View {
    let version: NoteVersion
    let previous: NoteVersion?
    let isCurrent: Bool
    let onRestore: () -> Void
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme
    @State private var comparison = Comparison.previous
    @State private var expanded = Set<Int>()
    @State private var confirmingRestore = false

    enum Comparison: Hashable { case previous, editor }

    /// Unchanged lines kept on show either side of a change.
    private static let context = 2

    /// A run of lines to show, or a run of unchanged ones folded away.
    private enum Item: Identifiable {
        case line(Int, LineDiff.Line)
        case folded(start: Int, count: Int)

        var id: Int {
            switch self {
            case .line(let index, _): index
            case .folded(let start, _): -start - 1
            }
        }
    }

    private var lines: [LineDiff.Line] {
        switch comparison {
        case .previous: LineDiff.lines(from: previous?.content ?? "", to: version.content)
        case .editor: LineDiff.lines(from: version.content, to: settingsService.notes)
        }
    }

    private func items(for lines: [LineDiff.Line]) -> [Item] {
        let changed = lines.indices.filter { lines[$0].kind != .same }
        var shown = Set<Int>()
        for index in changed {
            shown.formUnion(max(0, index - Self.context)...min(lines.count - 1, index + Self.context))
        }

        var items: [Item] = []
        var index = 0
        while index < lines.count {
            if shown.contains(index) {
                items.append(.line(index, lines[index]))
                index += 1
                continue
            }
            var end = index
            while end < lines.count, !shown.contains(end) { end += 1 }
            let count = end - index
            if count > 1, !expanded.contains(index) {
                items.append(.folded(start: index, count: count))
            } else {
                for i in index..<end { items.append(.line(i, lines[i])) }
            }
            index = end
        }
        return items
    }

    var body: some View {
        let lines = lines
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Compare With", selection: $comparison) {
                    Text(previous.map { "v\($0.number)" } ?? "Nothing Before").tag(Comparison.previous)
                    Text("Editor").tag(Comparison.editor)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                if lines.allSatisfy({ $0.kind == .same }) {
                    Text("No changes")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items(for: lines)) { item in
                            view(for: item)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(AppColors.background(for: colorScheme))
        .navigationTitle("v\(version.number)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: comparison) {
            expanded = []
        }
        .safeAreaInset(edge: .bottom) {
            if !isCurrent {
                Button {
                    AnalyticsEvents.logButtonClick("restore_version", screen: "note_versions")
                    if settingsService.hasUnsavedChanges {
                        confirmingRestore = true
                    } else {
                        onRestore()
                    }
                } label: {
                    Text("Restore This Version")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.green(for: colorScheme))
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .confirmationDialog("Discard Unsaved Changes?", isPresented: $confirmingRestore,
                            titleVisibility: .visible) {
            Button("Restore v\(version.number)", role: .destructive, action: onRestore)
        } message: {
            Text("The editor has changes that aren't saved. Restoring replaces them with this version.")
        }
    }

    @ViewBuilder
    private func view(for item: Item) -> some View {
        switch item {
        case .line(_, let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker(for: line.kind))
                    .foregroundStyle(color(for: line.kind))
                    .frame(width: 12)
                Text(line.text.isEmpty ? " " : line.text)
                    .strikethrough(line.kind == .removed)
                    .foregroundStyle(line.kind == .same
                                     ? AppColors.textSecondary(for: colorScheme)
                                     : AppColors.textPrimary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .background(line.kind == .same ? Color.clear : color(for: line.kind).opacity(0.15))
        case .folded(let start, let count):
            Button {
                expanded.insert(start)
            } label: {
                Text("⋯ \(count) unchanged lines")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private func marker(for kind: LineDiff.Kind) -> String {
        switch kind {
        case .same: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private func color(for kind: LineDiff.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .added: AppColors.green(for: colorScheme)
        case .removed: AppColors.red(for: colorScheme)
        }
    }
}
