import Foundation

/// Canonical set of ticket-mutating actions the assistant can propose.
/// Each action serializes to/from JSON exchanged with Claude.
enum AgentAction: Identifiable, Hashable {
    case addTicket(id: String, title: String, priority: String, status: String, estimate: Double, assignee: String, labels: [String], project: String?, sprint: String?, description: String)
    case updateTicket(id: String, fields: [String: String])
    case moveTicket(id: String, toStatus: String)
    case reprioritize(id: String, toPriority: String, reason: String)
    case addComment(ticketId: String, body: String)
    case deleteTicket(id: String)  // destructive, always requires confirm

    var id: String { summary }
    var isDestructive: Bool { if case .deleteTicket = self { return true } else { return false } }

    /// Human-readable one-line description of the action.
    var summary: String {
        switch self {
        case .addTicket(let id, let title, let p, let s, _, _, _, _, _, _):
            return "Add [\(p)] \(id) '\(title)' → \(s)"
        case .updateTicket(let id, let fields):
            let keys = fields.keys.sorted().joined(separator: ", ")
            return "Update \(id) fields: \(keys)"
        case .moveTicket(let id, let to):
            return "Move \(id) → \(to)"
        case .reprioritize(let id, let to, let reason):
            return "Reprioritize \(id) → \(to)\(reason.isEmpty ? "" : " (\(reason))")"
        case .addComment(let tid, let body):
            let preview = body.prefix(60)
            return "Comment on \(tid): \(preview)\(body.count > 60 ? "…" : "")"
        case .deleteTicket(let id):
            return "DELETE ticket \(id)"
        }
    }

    static func fromJSON(_ obj: [String: Any]) -> AgentAction? {
        guard let kind = obj["kind"] as? String,
              let args = obj["args"] as? [String: Any] else { return nil }
        switch kind {
        case "add_ticket":
            guard let id = args["id"] as? String,
                  let title = args["title"] as? String else { return nil }
            return .addTicket(
                id: id, title: title,
                priority: args["priority"] as? String ?? "P3",
                status: args["status"] as? String ?? "Backlog",
                estimate: (args["estimate"] as? Double) ?? Double(args["estimate"] as? Int ?? 0),
                assignee: args["assignee"] as? String ?? "",
                labels: (args["labels"] as? [String]) ?? [],
                project: args["project"] as? String,
                sprint: args["sprint"] as? String,
                description: args["description"] as? String ?? ""
            )
        case "update_ticket":
            guard let id = args["id"] as? String else { return nil }
            let fields = (args["fields"] as? [String: Any])?.compactMapValues { "\($0)" } ?? [:]
            return .updateTicket(id: id, fields: fields)
        case "move_ticket":
            guard let id = args["id"] as? String,
                  let to = args["to_status"] as? String else { return nil }
            return .moveTicket(id: id, toStatus: to)
        case "reprioritize":
            guard let id = args["id"] as? String,
                  let to = args["to_priority"] as? String else { return nil }
            return .reprioritize(id: id, toPriority: to, reason: args["reason"] as? String ?? "")
        case "add_comment":
            guard let tid = args["ticket_id"] as? String,
                  let body = args["body"] as? String else { return nil }
            return .addComment(ticketId: tid, body: body)
        case "delete_ticket":
            guard let id = args["id"] as? String else { return nil }
            return .deleteTicket(id: id)
        default:
            return nil
        }
    }
}

@MainActor
enum AgentDispatcher {
    /// Apply one action to the file store via AppState. Returns error string on failure.
    static func apply(_ action: AgentAction, appState: AppState) async -> String? {
        do {
            switch action {
            case .addTicket(let id, let title, let priority, let status, let est, let assignee, let labels, let project, let sprint, let desc):
                let ticket = Ticket(
                    id: id, title: title, description: desc,
                    status: TicketStatus(rawValue: status) ?? .backlog,
                    priority: Priority(rawValue: priority) ?? .p3,
                    estimate: est, assignee: assignee, labels: labels,
                    project: project, sprint: sprint ?? appState.currentSprint?.id,
                    results: "", blockers: "", verification: "", notes: "", timeLog: "",
                    created: "", updated: ""
                )
                try appState.store.save(ticket)
                await appState.refresh()

            case .updateTicket(let id, let fields):
                let clean: [String: Any] = fields.reduce(into: [:]) { acc, kv in
                    if kv.key == "estimate", let d = Double(kv.value) { acc[kv.key] = d }
                    else if kv.key == "labels" { acc[kv.key] = kv.value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
                    else { acc[kv.key] = kv.value }
                }
                try appState.store.updateFields(id: id, fields: clean)
                await appState.refresh()

            case .moveTicket(let id, let to):
                guard let t = appState.tickets.first(where: { $0.id == id }) else { throw AgentError.notFound(id) }
                guard let target = TicketStatus(rawValue: to) else { throw AgentError.badArg("status \(to)") }
                await appState.moveTicket(t, to: target)

            case .reprioritize(let id, let to, let reason):
                guard let t = appState.tickets.first(where: { $0.id == id }) else { throw AgentError.notFound(id) }
                guard let target = Priority(rawValue: to) else { throw AgentError.badArg("priority \(to)") }
                await appState.reprioritize(t, to: target, reason: reason)

            case .addComment(let tid, let body):
                await appState.addComment(ticketId: tid, body: body, attachments: [])

            case .deleteTicket(let id):
                try appState.store.delete(id: id)
                await appState.refresh()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum AgentError: LocalizedError {
    case notFound(String)
    case badArg(String)
    case notImplemented(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let s): return "Not found: \(s)"
        case .badArg(let s): return "Bad arg: \(s)"
        case .notImplemented(let s): return "Not implemented: \(s)"
        }
    }
}

/// One turn of proposed actions the user must approve.
struct ProposedTurn: Identifiable {
    let id = UUID()
    let userMessage: String
    let claudeReply: String
    let actions: [AgentAction]
    let at: Date
}
