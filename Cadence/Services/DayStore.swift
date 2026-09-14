import Foundation

/// File-based persistence for day plans. One file per day under AppSupport/days/:
///   days/2026-09-14.json
/// Pure filesystem, synchronous, atomic writes — mirrors WorkflowStore / IssueStore.
final class DayStore {
    private let fm = FileManager.default

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func file(_ date: String) -> URL {
        CadencePaths.daysDir.appendingPathComponent("\(date).json")
    }

    // MARK: read

    func load(_ date: String) -> DayPlan? {
        guard let data = try? Data(contentsOf: file(date)),
              let plan = try? Self.decoder.decode(DayPlan.self, from: data) else { return nil }
        return plan
    }

    /// Most recent days first.
    func recent(limit: Int = 14) -> [DayPlan] {
        guard let files = try? fm.contentsOfDirectory(at: CadencePaths.daysDir,
                                                      includingPropertiesForKeys: nil) else { return [] }
        var out: [DayPlan] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let plan = try? Self.decoder.decode(DayPlan.self, from: data) else { continue }
            out.append(plan)
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    // MARK: write

    /// Best-effort — called on every edit, so it must never throw into the UI.
    func save(_ plan: DayPlan) {
        guard let data = try? Self.encoder.encode(plan) else { return }
        try? data.write(to: file(plan.date), options: .atomic)
    }

    // MARK: today

    /// Today's plan: load it, or carry yesterday's shape forward, or seed from scratch.
    func today(now: Date = Date()) -> DayPlan {
        let key = DayPlan.key(for: now)
        if let existing = load(key) { return existing }

        let fresh: DayPlan
        if let previous = recent(limit: 1).first {
            fresh = previous.rolledOver(to: key)
        } else {
            fresh = DayPlan.seed(date: key)
        }
        save(fresh)
        return fresh
    }

    /// Trim anything older than `keep` days so the folder doesn't grow forever.
    func prune(keep: Int = 90) {
        guard let files = try? fm.contentsOfDirectory(at: CadencePaths.daysDir,
                                                      includingPropertiesForKeys: nil) else { return }
        let cutoff = DayPlan.key(for: Date().addingTimeInterval(-Double(keep) * 86_400))
        for f in files where f.pathExtension == "json" {
            if f.deletingPathExtension().lastPathComponent < cutoff {
                try? fm.removeItem(at: f)
            }
        }
    }
}
