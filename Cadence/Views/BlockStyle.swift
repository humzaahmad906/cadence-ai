import SwiftUI

/// Presentation for a workflow block on the canvas / palette — category, accent, tag — derived
/// from `WorkflowBlockKind` so the canvas and palette style consistently. Colors come from the
/// app's own design system (DS), not any external token set.
enum BlockCategory: String, CaseIterable, Identifiable {
    case trigger, ai, action, gate
    var id: String { rawValue }

    var label: String {
        switch self {
        case .trigger: return "Trigger"
        case .ai:      return "AI"
        case .action:  return "Action"
        case .gate:    return "Gate"
        }
    }

    var accent: Color {
        switch self {
        case .trigger: return DS.accent   // indigo
        case .ai:      return DS.purple
        case .action:  return DS.ok       // green
        case .gate:    return DS.warn      // amber
        }
    }
}

extension WorkflowBlockKind {
    var category: BlockCategory {
        switch self {
        case .input:                          return .trigger
        case .manualReview:                   return .gate
        case .createTickets, .code, .viewer:  return .action
        case .agentPrompt, .createDescription, .createSolution, .docQA, .summarize, .repoReport:
            return .ai
        }
    }
    var accent: Color { category.accent }
    var tag: String { category.label.uppercased() }

    /// Short subtitle under the node title.
    var subtitle: String {
        switch self {
        case .input:             return "Seed text"
        case .agentPrompt:       return "Claude agent"
        case .createTickets:     return "Save tickets"
        case .manualReview:      return "Human approve"
        case .summarize:         return "Markdown digest"
        case .createDescription: return "Wizard · description"
        case .createSolution:    return "Wizard · solution"
        case .viewer:            return "Read-only view"
        case .docQA:             return "Doc Q&A"
        case .repoReport:        return "Git activity"
        case .code:              return "Python"
        }
    }
}
