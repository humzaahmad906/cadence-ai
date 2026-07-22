import SwiftUI

struct PasteSprintView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sprintName: String = "Sprint \(Self.currentSprintNumber())"
    @State private var startDate: String = Self.currentMondayISO()
    @State private var endDate: String = Self.currentSprintEndISO()
    @State private var projectName: String = ""
    @State private var projectKey: String = ""
    @State private var rawText: String = ""
    @State private var parsed: [Ticket] = []
    @State private var parsing = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Paste Sprint").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            HStack {
                TextField("Sprint name", text: $sprintName)
                TextField("Start (YYYY-MM-DD)", text: $startDate).frame(width: 160)
                TextField("End (YYYY-MM-DD)", text: $endDate).frame(width: 160)
            }
            HStack {
                TextField("Project name (optional)", text: $projectName)
                TextField("Key", text: $projectKey).frame(width: 80)
            }
            Text("Paste tasks below (any format — markdown, JSON, plain list). Claude parses.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $rawText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            HStack {
                Button(parsing ? "Parsing…" : "Parse with Claude") { Task { await parse() } }
                    .disabled(parsing || rawText.trimmingCharacters(in: .whitespaces).isEmpty)
                if let e = errorMsg { Text(e).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button("Commit \(parsed.count) tickets") { Task { await commit() } }
                    .disabled(parsed.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            if !parsed.isEmpty {
                Divider()
                Text("Preview").font(.headline)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(parsed) { t in
                            HStack {
                                PriorityChip(priority: t.priority)
                                Text(t.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(t.title).lineLimit(1)
                                Spacer()
                                Text(t.status.rawValue).font(.caption)
                            }
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .frame(width: 720, height: 640)
    }

    private func parse() async {
        parsing = true; errorMsg = nil
        defer { parsing = false }
        let prompt = """
        Parse the following sprint task list into an array of ticket JSON objects.

        Rules:
        - Each ticket must have: id (SHORT-123 style; generate if missing), title, description, status, priority (P0-P4), estimate (hours; 0 if unknown), assignee, labels (array), results, blockers, verification, notes, time_log.
        - Default status Backlog. Default priority P3. Default estimate 0.
        - If input hints at status/priority use it. Preserve verbatim.
        - Empty strings for missing fields except arrays which are [].
        - Return a JSON array only.

        Project key: \(projectKey.isEmpty ? "NONE" : projectKey)

        INPUT:
        \(rawText)
        """
        do {
            let obj = try await appState.claude.promptJSON(prompt, timeout: 120)
            guard let arr = obj as? [[String: Any]] else { throw ClaudeError.badJSON(String(describing: obj)) }
            parsed = arr.map { row in
                var r = row
                if r["status"] == nil { r["status"] = "Backlog" }
                if r["priority"] == nil { r["priority"] = "P3" }
                if r["project"] == nil, !projectKey.isEmpty { r["project"] = projectKey }
                return Ticket.fromRow(r)
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func commit() async {
        let sprintId = "sprint_\(startDate)"
        do {
            for var t in parsed {
                t = Ticket(
                    id: t.id, title: t.title, description: t.description,
                    status: t.status, priority: t.priority, estimate: t.estimate,
                    assignee: t.assignee, labels: t.labels,
                    project: projectKey.isEmpty ? nil : projectKey,
                    sprint: sprintId,
                    results: t.results, blockers: t.blockers, verification: t.verification,
                    notes: t.notes, timeLog: t.timeLog, created: t.created, updated: t.updated
                )
                try appState.store.save(t)
            }
            await appState.refresh()
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    static func currentMondayISO() -> String {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let mon = cal.date(from: comps) ?? today
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: mon)
    }

    static func currentSprintEndISO() -> String {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let mon = cal.date(from: comps) ?? today
        let end = cal.date(byAdding: .day, value: 13, to: mon) ?? today
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: end)
    }

    static func currentSprintNumber() -> Int {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let week = cal.component(.weekOfYear, from: today)
        return (week / 2) + 1
    }
}
