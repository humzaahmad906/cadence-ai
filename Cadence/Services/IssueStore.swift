import Foundation

/// File-based persistence: one folder per issue under AppSupport/issues/<ID>/.
///   issue.md               — YAML frontmatter + ## Description + ## Solution (the ticket)
///   exploration.md         — raw agent findings from the description phase
///   solution-exploration.md — raw agent findings from the solution phase
///   comments.json          — [{author, body, created, attachments}]
/// Replaces the Kuzu graph DB. Pure filesystem, no subprocess, synchronous.
final class IssueStore {
    private let fm = FileManager.default

    private func folder(_ id: String) -> URL {
        CadencePaths.issuesDir.appendingPathComponent(id)
    }
    private func issueFile(_ id: String) -> URL {
        folder(id).appendingPathComponent("issue.md")
    }
    private func ensureFolder(_ id: String) throws {
        try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
    }

    // MARK: read

    /// Scan issues/*/issue.md and parse each into a Ticket.
    func list() -> [Ticket] {
        guard let dirs = try? fm.contentsOfDirectory(at: CadencePaths.issuesDir,
                                                     includingPropertiesForKeys: nil) else { return [] }
        var out: [Ticket] = []
        for dir in dirs {
            let f = dir.appendingPathComponent("issue.md")
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            if let t = Self.parse(text) { out.append(t) }
        }
        return out.sorted { $0.priority.rank < $1.priority.rank }
    }

    func load(_ id: String) -> Ticket? {
        guard let text = try? String(contentsOf: issueFile(id), encoding: .utf8) else { return nil }
        return Self.parse(text)
    }

    /// repo/branch aren't on the Ticket model; expose them from frontmatter when needed.
    func repoBranch(_ id: String) -> (repo: String, branch: String) {
        guard let text = try? String(contentsOf: issueFile(id), encoding: .utf8) else { return ("", "") }
        let (fm, _) = Self.split(text)
        return (fm["repo"] ?? "", fm["branch"] ?? "")
    }

    // MARK: write

    /// Write issue.md. `repo`/`branch` nil → preserve whatever is already on disk.
    func save(_ ticket: Ticket, repo: String? = nil, branch: String? = nil) throws {
        try ensureFolder(ticket.id)
        let existing = try? String(contentsOf: issueFile(ticket.id), encoding: .utf8)
        let prior = existing.map { Self.split($0).front } ?? [:]

        let now = ISO8601DateFormatter().string(from: Date())
        let created = prior["created"] ?? (ticket.created.isEmpty ? now : ticket.created)

        var fm: [(String, String)] = [
            ("id", ticket.id),
            ("title", ticket.title),
            ("status", ticket.status.rawValue),
            ("priority", ticket.priority.rawValue),
            ("estimate", String(ticket.estimate)),
            ("assignee", ticket.assignee),
            ("repo", repo ?? prior["repo"] ?? ""),
            ("branch", branch ?? prior["branch"] ?? ""),
            ("sprint", ticket.sprint ?? prior["sprint"] ?? ""),
            ("labels", "[" + ticket.labels.joined(separator: ", ") + "]"),
            ("created", created),
            ("updated", now),
        ]

        var lines = ["---"]
        for (k, v) in fm { lines.append("\(k): \(v)") }
        lines.append("---")
        lines.append("")
        lines.append(ticket.description)
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: issueFile(ticket.id), atomically: true, encoding: .utf8)
    }

    /// phase: "description" → exploration.md, "solution" → solution-exploration.md.
    func writeExploration(id: String, phase: String, markdown: String) {
        guard !markdown.isEmpty else { return }
        try? ensureFolder(id)
        let name = phase == "solution" ? "solution-exploration.md" : "exploration.md"
        try? markdown.write(to: folder(id).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func readExploration(id: String, phase: String) -> String? {
        let name = phase == "solution" ? "solution-exploration.md" : "exploration.md"
        return try? String(contentsOf: folder(id).appendingPathComponent(name), encoding: .utf8)
    }

    func move(id: String, to status: TicketStatus) throws {
        guard var t = load(id) else { return }
        t.status = status
        try save(t)
    }

    func reprioritize(id: String, to priority: Priority) throws {
        guard var t = load(id) else { return }
        t.priority = priority
        try save(t)
    }

    func updateFields(id: String, fields: [String: Any]) throws {
        guard var t = load(id) else { return }
        if let v = fields["title"] as? String { t.title = v }
        if let v = fields["description"] as? String { t.description = v }
        if let v = fields["priority"] as? String, let p = Priority(rawValue: v) { t.priority = p }
        if let v = fields["assignee"] as? String { t.assignee = v }
        if let v = fields["estimate"] as? Double { t.estimate = v }
        else if let v = fields["estimate"] as? Int { t.estimate = Double(v) }
        if let v = fields["labels"] as? [String] { t.labels = v }
        try save(t)
    }

    func delete(id: String) throws {
        try fm.removeItem(at: folder(id))
    }

    // MARK: comments

    struct Comment: Codable { var author: String; var body: String; var created: String; var attachments: [String] }

    func comments(_ id: String) -> [Comment] {
        let url = folder(id).appendingPathComponent("comments.json")
        guard let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode([Comment].self, from: data) else { return [] }
        return c
    }

    func addComment(id: String, body: String, author: String = "me", attachments: [String] = []) throws {
        try ensureFolder(id)
        var all = comments(id)
        all.append(Comment(author: author, body: body,
                           created: ISO8601DateFormatter().string(from: Date()),
                           attachments: attachments))
        let data = try JSONEncoder().encode(all)
        try data.write(to: folder(id).appendingPathComponent("comments.json"), options: .atomic)
    }

    // MARK: parsing

    /// Split a frontmatter doc into (frontmatter dict, body). Tolerant of missing fences.
    static func split(_ text: String) -> (front: [String: String], body: String) {
        var front: [String: String] = [:]
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], text)
        }
        var i = 1
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces) != "---" {
            let line = lines[i]
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                front[key] = val
            }
            i += 1
        }
        let body = i + 1 < lines.count ? lines[(i + 1)...].joined(separator: "\n") : ""
        return (front, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func parse(_ text: String) -> Ticket? {
        let (fm, body) = split(text)
        guard let id = fm["id"], !id.isEmpty else { return nil }
        let labels = (fm["labels"] ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Ticket(
            id: id,
            title: fm["title"] ?? "",
            description: body,
            status: TicketStatus(rawValue: fm["status"] ?? "Backlog") ?? .backlog,
            priority: Priority(rawValue: fm["priority"] ?? "P3") ?? .p3,
            estimate: Double(fm["estimate"] ?? "0") ?? 0,
            assignee: fm["assignee"] ?? "",
            labels: labels,
            project: nil,
            sprint: (fm["sprint"]?.isEmpty == false) ? fm["sprint"] : nil,
            results: "", blockers: "", verification: "", notes: "", timeLog: "",
            created: fm["created"] ?? "",
            updated: fm["updated"] ?? ""
        )
    }
}
