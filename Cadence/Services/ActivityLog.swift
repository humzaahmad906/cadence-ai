import Foundation

/// Append-only event log, one JSON object per line at AppSupport/activity.jsonl.
///
/// JSON Lines rather than one array so appending is a single write with no read-modify-write
/// race, and so a truncated tail costs one event instead of the file. Reads parse leniently:
/// a line that won't decode is skipped, not fatal.
final class ActivityLog {
    private let fm = FileManager.default

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]      // no pretty-print: one event must stay one line
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Append one event. Best-effort — logging must never break the thing it's logging.
    func append(_ event: ActivityEvent) {
        guard let data = try? Self.encoder.encode(event) else { return }
        var line = data
        line.append(0x0A)

        let url = CadencePaths.activityFile
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    /// Stored events only, newest first.
    func events(limit: Int = 300) -> [ActivityEvent] {
        guard let text = try? String(contentsOf: CadencePaths.activityFile, encoding: .utf8) else { return [] }
        var out: [ActivityEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let e = try? Self.decoder.decode(ActivityEvent.self, from: data) else { continue }
            out.append(e)
        }
        return Array(out.sorted { $0.at > $1.at }.prefix(limit))
    }

    /// The whole log: stored events merged with every workflow run on disk, newest first.
    func feed(store: WorkflowStore, limit: Int = 300) -> [ActivityEvent] {
        let runs = store.allRuns(limit: limit).map(ActivityEvent.init(run:))
        return Array((events(limit: limit) + runs).sorted { $0.at > $1.at }.prefix(limit))
    }

    /// True if an event with this id was already written — the once-per-day guard for
    /// office arrivals, which survives a relaunch because it reads the file rather than memory.
    func contains(id: String) -> Bool {
        events(limit: 500).contains { $0.id == id }
    }

    /// Drop everything. Used by the log's own Clear button.
    func clear() {
        try? fm.removeItem(at: CadencePaths.activityFile)
    }
}
