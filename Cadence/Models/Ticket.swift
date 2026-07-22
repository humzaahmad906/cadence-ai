import Foundation

enum TicketStatus: String, CaseIterable, Codable, Identifiable {
    case backlog = "Backlog"
    case todo = "Todo"
    case inProgress = "In Progress"
    case inReview = "In Review"
    case done = "Done"
    var id: String { rawValue }
    var short: String {
        switch self {
        case .backlog: return "BL"
        case .todo: return "TD"
        case .inProgress: return "IP"
        case .inReview: return "RV"
        case .done: return "DN"
        }
    }
}

enum Priority: String, CaseIterable, Codable, Identifiable {
    case p0 = "P0", p1 = "P1", p2 = "P2", p3 = "P3", p4 = "P4"
    var id: String { rawValue }
    var rank: Int {
        switch self { case .p0: 0; case .p1: 1; case .p2: 2; case .p3: 3; case .p4: 4 }
    }
    var urgent: Bool { self == .p0 || self == .p1 }
}

struct Ticket: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var description: String
    var status: TicketStatus
    var priority: Priority
    var estimate: Double
    var assignee: String
    var labels: [String]
    var project: String?
    var sprint: String?
    var results: String
    var blockers: String
    var verification: String
    var notes: String
    var timeLog: String
    var created: String
    var updated: String

    static func fromRow(_ row: [String: Any]) -> Ticket {
        Ticket(
            id: row["id"] as? String ?? "",
            title: row["title"] as? String ?? "",
            description: row["description"] as? String ?? "",
            status: TicketStatus(rawValue: row["status"] as? String ?? "Backlog") ?? .backlog,
            priority: Priority(rawValue: row["priority"] as? String ?? "P3") ?? .p3,
            estimate: (row["estimate"] as? Double) ?? Double(row["estimate"] as? Int ?? 0),
            assignee: row["assignee"] as? String ?? "",
            labels: (row["labels"] as? String ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            project: row["project"] as? String,
            sprint: row["sprint"] as? String,
            results: row["results"] as? String ?? "",
            blockers: row["blockers"] as? String ?? "",
            verification: row["verification"] as? String ?? "",
            notes: row["notes"] as? String ?? "",
            timeLog: row["time_log"] as? String ?? "",
            created: row["created"] as? String ?? "",
            updated: row["updated"] as? String ?? ""
        )
    }

    func editableFields() -> [String: Any] {
        [
            "title": title, "description": description,
            "priority": priority.rawValue, "estimate": estimate,
            "assignee": assignee, "labels": labels,
            "results": results, "blockers": blockers,
            "verification": verification, "notes": notes,
            "time_log": timeLog,
        ]
    }

    func toJSON() -> [String: Any] {
        [
            "id": id, "title": title, "description": description,
            "status": status.rawValue, "priority": priority.rawValue,
            "estimate": estimate, "assignee": assignee, "labels": labels,
            "project": project ?? NSNull(), "sprint": sprint ?? NSNull(),
            "results": results, "blockers": blockers,
            "verification": verification, "notes": notes, "time_log": timeLog,
        ]
    }
}

struct Project: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var key: String
    var description: String
}

struct Sprint: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var startDate: String
    var endDate: String

    var startDateObj: Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: startDate)
    }
    var endDateObj: Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: endDate)
    }
    var daysLeft: Int {
        guard let end = endDateObj else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }
}
