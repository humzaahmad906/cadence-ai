import Foundation

/// One line in the log. Everything the app does unattended lands here: a workflow that ran, a
/// day block that started, the moment the office network appeared.
///
/// Workflow runs are *not* stored as events — they already live in workflows/<ID>/runs/ and are
/// folded into the feed at read time (see `ActivityLog.feed`). Only the events with no other
/// home on disk get written to activity.jsonl.
struct ActivityEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case workflowRun        // synthesised from a WorkflowRun on disk
        case dayBlock           // a day block started
        case dayRollover        // a new day was seeded from yesterday's shape
        case dayArchive         // what a block held when its day ended
        case office             // arrived on the office network

        var icon: String {
            switch self {
            case .workflowRun:  return "play.circle"
            case .dayBlock:     return "calendar.day.timeline.left"
            case .dayRollover:  return "sunrise"
            case .dayArchive:   return "archivebox"
            case .office:       return "wifi"
            }
        }
    }

    /// How the row reads at a glance — drives its tint, not its meaning.
    enum Outcome: String, Codable {
        case ok, failed, running, info
    }

    var id: String
    var kind: Kind
    var outcome: Outcome
    var title: String
    var detail: String
    var at: Date
    /// Set when the row is clickable: the run it came from, or the day it belongs to.
    var workflowId: String?
    var runId: String?

    init(id: String = UUID().uuidString,
         kind: Kind,
         outcome: Outcome = .info,
         title: String,
         detail: String = "",
         at: Date,
         workflowId: String? = nil,
         runId: String? = nil) {
        self.id = id
        self.kind = kind
        self.outcome = outcome
        self.title = title
        self.detail = detail
        self.at = at
        self.workflowId = workflowId
        self.runId = runId
    }

    /// Where clicking the row goes. Day events land on Day rather than on a specific block —
    /// there's nothing deeper to open.
    var target: CanvasArtifact? {
        switch kind {
        case .workflowRun:
            return runId.map { .workflowRun(id: $0) }
        case .dayBlock, .dayRollover, .office:
            return .day
        case .dayArchive:
            // Nowhere to go — the block it describes no longer exists. The row itself is the
            // record, which is why the log expands it on click instead of navigating.
            return nil
        }
    }
}

extension ActivityEvent {
    /// Fold a persisted run into a feed row.
    init(run: WorkflowRun) {
        let outcome: Outcome
        switch run.status {
        case .done:   outcome = .ok
        case .failed: outcome = .failed
        case .running, .awaitingReview, .pending: outcome = .running
        }

        let doneCount = run.blocks.filter { $0.status == .done }.count
        let failed = run.blocks.first { $0.status == .failed }
        let detail: String
        if let failed {
            detail = "Failed at \(failed.title.isEmpty ? failed.kind.label : failed.title) — \(failed.error ?? "no error text")"
        } else if run.status == .awaitingReview {
            detail = "Waiting on review · \(doneCount)/\(run.blocks.count) blocks"
        } else {
            detail = "\(doneCount)/\(run.blocks.count) blocks"
        }

        self.init(id: "run-\(run.id)",
                  kind: .workflowRun,
                  outcome: outcome,
                  title: run.workflowName,
                  detail: detail,
                  at: run.updatedAt,
                  workflowId: run.workflowId,
                  runId: run.id)
    }
}
