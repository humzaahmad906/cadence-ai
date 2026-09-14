import Foundation

/// App-wide defaults for the `claude` CLI: which binary, which model, how hard it thinks.
///
/// A block that names its own model still wins; this is the fallback for every block that
/// leaves the field blank, which is most of them.
struct ClaudeSettings: Codable, Equatable {
    var binary: String = "/opt/homebrew/bin/claude"
    /// Empty means "whatever the CLI is configured to use" — a valid choice, not a missing one.
    var model: String = ModelCatalog.defaultModel
    /// "", low, medium, high, xhigh, max
    var effort: String = ""

    static func load() -> ClaudeSettings {
        guard let data = try? Data(contentsOf: CadencePaths.configFile),
              let c = try? JSONDecoder().decode(ClaudeSettings.self, from: data) else { return ClaudeSettings() }
        return c
    }

    func save() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(self) else { return }
        try? data.write(to: CadencePaths.configFile, options: .atomic)
    }
}

/// Known model ids, newest first.
///
/// This list is a convenience, not a gate — Settings also takes a typed id, and it's passed to
/// `claude --model` verbatim. A model released after this build ships works by typing its id;
/// nothing here needs to change first. The CLI's own aliases (`opus`, `sonnet`, `haiku`) work
/// the same way.
enum ModelCatalog {
    static let defaultModel = "claude-opus-5"

    struct Entry: Identifiable, Hashable {
        let id: String
        let label: String
        let note: String
    }

    static let known: [Entry] = [
        Entry(id: "claude-opus-5",    label: "Opus 5",    note: "Default — 1M context"),
        Entry(id: "claude-fable-5",   label: "Fable 5",   note: "Most capable, highest cost"),
        Entry(id: "claude-opus-4-8",  label: "Opus 4.8",  note: "Previous Opus"),
        Entry(id: "claude-opus-4-7",  label: "Opus 4.7",  note: ""),
        Entry(id: "claude-opus-4-6",  label: "Opus 4.6",  note: ""),
        Entry(id: "claude-sonnet-5",  label: "Sonnet 5",  note: "Cheaper, still 1M context"),
        Entry(id: "claude-sonnet-4-6", label: "Sonnet 4.6", note: ""),
        Entry(id: "claude-haiku-4-5", label: "Haiku 4.5", note: "Fastest — 200K context"),
    ]

    static let efforts: [String] = ["", "low", "medium", "high", "xhigh", "max"]

    static func label(for id: String) -> String {
        if id.isEmpty { return "CLI default" }
        return known.first { $0.id == id }?.label ?? id
    }

    static func isKnown(_ id: String) -> Bool {
        id.isEmpty || known.contains { $0.id == id }
    }
}
