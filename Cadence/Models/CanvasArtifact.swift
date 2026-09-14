import Foundation

/// One-canvas-at-a-time model. The chat drives it; the canvas renders it.
enum CanvasArtifact: Hashable, Identifiable {
    case kickoff                            // empty home: single prompt input, no chrome
    case taskSplit                          // review agent-generated task list before wizard
    case wizard                             // multi-step per-task workflow
    case sprintStatus                       // once tickets exist: risk-first sprint view
    case kanban                             // full board, drag-drop intact
    case ticketsList(status: TicketStatus?) // filtered table view
    case ticketDetail(id: String)           // single ticket editor
    case draftStack                         // ticket draft review stack (signature flow A)
    case digest                             // today's Slack draft
    case doctrines                          // findings list
    case workflows                          // block-based workflow library
    case workflowBuilder(id: String)        // compose/edit one workflow
    case workflowRun(id: String)            // live run progress for one workflow
    case day                                // today's time blocks
    case settings                           // paths + schedule
    case empty(reason: String)              // first-run / recovered from error

    var id: String {
        switch self {
        case .kickoff: return "kickoff"
        case .taskSplit: return "task_split"
        case .wizard: return "wizard"
        case .sprintStatus: return "sprint_status"
        case .kanban: return "kanban"
        case .ticketsList(let s): return "tickets_list_\(s?.rawValue ?? "all")"
        case .ticketDetail(let i): return "ticket_\(i)"
        case .draftStack: return "draft_stack"
        case .digest: return "digest"
        case .doctrines: return "doctrines"
        case .workflows: return "workflows"
        case .workflowBuilder(let i): return "workflow_builder_\(i)"
        case .workflowRun(let i): return "workflow_run_\(i)"
        case .day: return "day"
        case .settings: return "settings"
        case .empty(let r): return "empty_\(r)"
        }
    }

    var title: String {
        switch self {
        case .kickoff: return "Start"
        case .taskSplit: return "Review tasks"
        case .wizard: return "Wizard"
        case .sprintStatus: return "Sprint status"
        case .kanban: return "Kanban"
        case .ticketsList(let s): return s.map { "Tickets · \($0.rawValue)" } ?? "Tickets"
        case .ticketDetail(let i): return "Ticket \(i)"
        case .draftStack: return "Review drafts"
        case .digest: return "Digest"
        case .doctrines: return "Doctrines"
        case .workflows: return "Workflows"
        case .workflowBuilder: return "Edit workflow"
        case .workflowRun: return "Workflow run"
        case .day: return "Day"
        case .settings: return "Settings"
        case .empty: return "Cadence"
        }
    }

    /// Icon for header + ambient references
    var icon: String {
        switch self {
        case .kickoff: return "sparkles"
        case .taskSplit: return "list.bullet.rectangle"
        case .wizard: return "wand.and.rays"
        case .sprintStatus: return "flag.checkered"
        case .kanban: return "rectangle.split.3x1"
        case .ticketsList: return "list.bullet.rectangle"
        case .ticketDetail: return "doc.text"
        case .draftStack: return "square.stack"
        case .digest: return "text.badge.checkmark"
        case .doctrines: return "book.closed"
        case .workflows: return "flowchart"
        case .workflowBuilder: return "slider.horizontal.3"
        case .workflowRun: return "play.circle"
        case .day: return "calendar.day.timeline.left"
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
