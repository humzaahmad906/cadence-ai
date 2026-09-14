import Foundation

/// One-canvas-at-a-time model. The header and the activity log drive it; the canvas renders it.
///
/// Deliberately small: Workflows, Day, and Log are the whole app. Tickets still exist on disk
/// (workflows create them) but live off the home surface — reachable from a log row or from
/// Settings → Archive, never from the header.
enum CanvasArtifact: Hashable, Identifiable {
    case workflows                          // block-based workflow library — home
    case workflowBuilder(id: String)        // compose/edit one workflow
    case workflowRun(id: String)            // live run progress for one workflow
    case day                                // today's time blocks
    case activity                           // everything that ran: workflow runs + day events
    case ticketsList(status: TicketStatus?) // archive: tickets created by workflows
    case ticketDetail(id: String)           // single ticket editor
    case settings                           // paths + schedule + office network
    case empty(reason: String)              // first-run / recovered from error

    var id: String {
        switch self {
        case .workflows: return "workflows"
        case .workflowBuilder(let i): return "workflow_builder_\(i)"
        case .workflowRun(let i): return "workflow_run_\(i)"
        case .day: return "day"
        case .activity: return "activity"
        case .ticketsList(let s): return "tickets_list_\(s?.rawValue ?? "all")"
        case .ticketDetail(let i): return "ticket_\(i)"
        case .settings: return "settings"
        case .empty(let r): return "empty_\(r)"
        }
    }

    var title: String {
        switch self {
        case .workflows: return "Workflows"
        case .workflowBuilder: return "Edit workflow"
        case .workflowRun: return "Workflow run"
        case .day: return "Day"
        case .activity: return "Log"
        case .ticketsList(let s): return s.map { "Archive · \($0.rawValue)" } ?? "Archive"
        case .ticketDetail(let i): return "Ticket \(i)"
        case .settings: return "Settings"
        case .empty: return "Cadence"
        }
    }

    /// Icon for header + ambient references
    var icon: String {
        switch self {
        case .workflows: return "flowchart"
        case .workflowBuilder: return "slider.horizontal.3"
        case .workflowRun: return "play.circle"
        case .day: return "calendar.day.timeline.left"
        case .activity: return "list.bullet.rectangle.portrait"
        case .ticketsList: return "archivebox"
        case .ticketDetail: return "doc.text"
        case .settings: return "gearshape"
        case .empty: return "sparkle"
        }
    }
}

/// Ephemeral notice surfaced in the ambient strip.
struct AmbientEvent: Identifiable, Hashable {
    let id: UUID = UUID()
    let kind: Kind
    let text: String
    let at: Date
    let target: CanvasArtifact?

    enum Kind: String {
        case stale, idle, digest, activity, info, error
    }

    var iconName: String {
        switch kind {
        case .stale: return "exclamationmark.triangle.fill"
        case .idle: return "hourglass"
        case .digest: return "text.badge.checkmark"
        case .activity: return "clock.arrow.circlepath"
        case .info: return "info.circle"
        case .error: return "xmark.octagon.fill"
        }
    }
}
