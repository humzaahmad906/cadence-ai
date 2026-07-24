import Foundation

/// A composable, block-based workflow. Generalizes the hardcoded kickoff→split→wizard
/// pipeline into an ordered list of reusable steps ("blocks") that pass output → input.
///
/// Persisted one folder per workflow under AppSupport/workflows/<ID>/workflow.json;
/// runs land in runs/<runID>.json. Mirrors IssueStore's pure-filesystem style.

// MARK: - Block kinds

/// The kind of a workflow block. Config lives on `WorkflowBlock.config` (a flat struct,
/// so the whole thing serializes cleanly the way IssueStore's Codable models do).
///
/// Blocks are pluggable: each kind is backed by a `WorkflowBlockHandler` resolved through
/// `WorkflowBlockRegistry` (see Services/WorkflowBlocks.swift). Several kinds are deliberately
/// thin *presets* of the generic `agentPrompt` block (a preset system prompt + a fixed shape) —
/// `docQA` and `repoReport` are exactly that, and `createDescription`/`createSolution` reuse the
/// wizard's existing description/solution agents verbatim. To add a new kind: add a case here,
/// a handler + registry line in WorkflowBlocks.swift, and a config editor in WorkflowBuilderView.
enum WorkflowBlockKind: String, Codable, CaseIterable, Identifiable {
    // Generic building blocks
    case agentPrompt        // run a Claude agent over scoped repos, capture output
    case createTickets      // parse structured agent JSON into tickets, commit via AgentDispatcher
    case manualReview       // pause for user approval / edit before continuing
    case summarize          // fold the running output into a markdown summary (optionally the digest)

    // Wizard-reuse blocks (share AppState.descriptionAgent / solutionAgent with the wizard)
    case createDescription  // write a task description from a title, grounded in the scoped repos
    case createSolution     // write an implementation plan from the incoming description

    // Display + inspection blocks
    case viewer             // read-only render of a target (doc / ticket / repo summary / prev output)
    case docQA              // agent preset: answer a question about a doc/markdown source
    case repoReport         // agent preset: summarize repo activity via git log/show/diff/blame

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agentPrompt:       return "Agent prompt"
        case .createTickets:     return "Create tickets"
        case .manualReview:      return "Manual review"
        case .summarize:         return "Summarize"
        case .createDescription: return "Create description"
        case .createSolution:    return "Create solution"
        case .viewer:            return "Viewer"
        case .docQA:             return "Doc Q&A"
        case .repoReport:        return "Repo report"
        }
    }

    var icon: String {
        switch self {
        case .agentPrompt:       return "sparkles"
        case .createTickets:     return "plus.rectangle.on.rectangle"
        case .manualReview:      return "hand.raised"
        case .summarize:         return "text.append"
        case .createDescription: return "doc.text"
        case .createSolution:    return "list.number"
        case .viewer:            return "eye"
        case .docQA:             return "questionmark.bubble"
        case .repoReport:        return "chart.bar.doc.horizontal"
        }
    }

    var blurb: String {
        switch self {
        case .agentPrompt:       return "Run the Claude agent over the workflow's repos and capture its output."
        case .createTickets:     return "Parse the previous block's JSON into tickets and save them."
        case .manualReview:      return "Pause so you can approve or edit before the run continues."
        case .summarize:         return "Fold the running output into a markdown summary."
        case .createDescription: return "Wizard description writer: turn the incoming task title into a grounded description."
        case .createSolution:    return "Wizard solution designer: turn the incoming description into an implementation plan."
        case .viewer:            return "Read-only display of a doc, ticket, repo summary, or the previous block's output."
        case .docQA:             return "Ask a question about a document (or repo docs) and get a cited answer."
        case .repoReport:        return "Summarize recent repo activity (commits, branches, churn) via git."
        }
    }

    /// Whether this block, as the first in a run, consumes the run's initial input (so the user
    /// should be prompted for a starting value before the run begins).
    var consumesInitialInput: Bool {
        switch self {
        case .createDescription, .agentPrompt, .createTickets: return true
        case .createSolution, .manualReview, .summarize, .viewer, .docQA, .repoReport: return false
        }
    }
}

/// What a `viewer` block renders.
enum ViewerTarget: String, Codable, CaseIterable, Identifiable {
    case previousOutput
    case ticket
    case repoSummary
    case doc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .previousOutput: return "Previous output"
        case .ticket:         return "Ticket"
        case .repoSummary:    return "Repo summary"
        case .doc:            return "Document"
        }
    }
}

/// Kind-specific configuration. All fields optional/defaulted so the struct serializes
/// flatly and forward-compatibly. Templates may reference {{input}} (previous block output)
/// and {{repos}} (a description of the scoped repos) inside prompt templates.
struct WorkflowBlockConfig: Codable, Hashable {
    /// agentPrompt: appended system prompt describing the agent's job.
    var systemPrompt: String = ""
    /// agentPrompt / summarize: user-message template. Supports {{input}} and {{repos}}.
    var promptTemplate: String = ""
    /// agentPrompt: when true the agent returns arbitrary JSON (passed on verbatim, e.g. for
    /// createTickets). When false the agent is asked for {"output": "..."} and only the string
    /// is carried forward.
    var expectJSON: Bool = false
    /// createTickets: default priority applied when the agent omits one.
    var defaultPriority: String = "P3"
    /// createTickets: default status for created tickets.
    var defaultStatus: String = "Backlog"
    /// manualReview: guidance shown above the editable output.
    var reviewInstructions: String = ""
    /// summarize: heading prepended to the produced markdown.
    var heading: String = "Summary"
    /// summarize: when true the result is persisted through AppState.persistDigest (the digest path).
    var persistAsDigest: Bool = false
    /// viewer: which artifact to render (raw value of ViewerTarget).
    var viewerTarget: String = ViewerTarget.previousOutput.rawValue
    /// viewer(ticket): the ticket id to display.
    var ticketId: String = ""
    /// viewer(doc) / docQA: absolute path of a markdown/doc file to read.
    var docPath: String = ""
    /// docQA: the question to ask about the doc/repo material.
    var question: String = ""
    /// repoReport: the window to report on (a git ref, date, or free phrase like "the last 2 weeks").
    var sinceRef: String = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case systemPrompt, promptTemplate, expectJSON, defaultPriority, defaultStatus
        case reviewInstructions, heading, persistAsDigest, viewerTarget, ticketId
        case docPath, question, sinceRef
    }
}

// Hand-written decoding so older/newer JSON (missing or extra keys) decodes gracefully;
// encoding stays synthesized against the same CodingKeys. See L1 in the review.
extension WorkflowBlockConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        systemPrompt       = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? systemPrompt
        promptTemplate     = try c.decodeIfPresent(String.self, forKey: .promptTemplate) ?? promptTemplate
        expectJSON         = try c.decodeIfPresent(Bool.self, forKey: .expectJSON) ?? expectJSON
        defaultPriority    = try c.decodeIfPresent(String.self, forKey: .defaultPriority) ?? defaultPriority
        defaultStatus      = try c.decodeIfPresent(String.self, forKey: .defaultStatus) ?? defaultStatus
        reviewInstructions = try c.decodeIfPresent(String.self, forKey: .reviewInstructions) ?? reviewInstructions
        heading            = try c.decodeIfPresent(String.self, forKey: .heading) ?? heading
        persistAsDigest    = try c.decodeIfPresent(Bool.self, forKey: .persistAsDigest) ?? persistAsDigest
        viewerTarget       = try c.decodeIfPresent(String.self, forKey: .viewerTarget) ?? viewerTarget
        ticketId           = try c.decodeIfPresent(String.self, forKey: .ticketId) ?? ticketId
        docPath            = try c.decodeIfPresent(String.self, forKey: .docPath) ?? docPath
        question           = try c.decodeIfPresent(String.self, forKey: .question) ?? question
        sinceRef           = try c.decodeIfPresent(String.self, forKey: .sinceRef) ?? sinceRef
    }
}

/// One ordered step in a workflow.
struct WorkflowBlock: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: WorkflowBlockKind
    var title: String
    var config: WorkflowBlockConfig

    init(id: UUID = UUID(), kind: WorkflowBlockKind, title: String, config: WorkflowBlockConfig = WorkflowBlockConfig()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.config = config
    }
}

// MARK: - Workflow

struct Workflow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var summary: String
    var blocks: [WorkflowBlock]
    var repoIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         name: String,
         summary: String = "",
         blocks: [WorkflowBlock] = [],
         repoIds: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.blocks = blocks
        self.repoIds = repoIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Whether a run should prompt the user for a starting input — true when the first block
    /// consumes the run's initial input.
    var firstBlockConsumesInput: Bool {
        blocks.first?.kind.consumesInitialInput ?? false
    }
}

// MARK: - Run state

enum BlockRunStatus: String, Codable {
    case pending, running, awaitingReview, done, failed, skipped
}

enum RunStatus: String, Codable {
    case pending, running, awaitingReview, done, failed
}

/// Per-block execution record inside a run. `id` mirrors the source block's id.
struct BlockRunState: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: WorkflowBlockKind
    var title: String
    /// The source block's configuration, carried into the run so the run view can render the
    /// configured behaviour (e.g. manualReview's `reviewInstructions`).
    var config: WorkflowBlockConfig
    var status: BlockRunStatus
    var output: String
    var error: String?
    var startedAt: Date?
    var finishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, config, status, output, error, startedAt, finishedAt
    }
}

// Hand-written decoding for forward/backward-compat (config is a newer field); the memberwise
// init stays available because this initializer lives in an extension.
extension BlockRunState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind       = try c.decodeIfPresent(WorkflowBlockKind.self, forKey: .kind) ?? .agentPrompt
        title      = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        config     = try c.decodeIfPresent(WorkflowBlockConfig.self, forKey: .config) ?? WorkflowBlockConfig()
        status     = try c.decodeIfPresent(BlockRunStatus.self, forKey: .status) ?? .pending
        output     = try c.decodeIfPresent(String.self, forKey: .output) ?? ""
        error      = try c.decodeIfPresent(String.self, forKey: .error)
        startedAt  = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}

/// A single execution of a workflow. Persisted under workflows/<workflowID>/runs/<runID>.json.
struct WorkflowRun: Codable, Identifiable, Hashable {
    var id: String
    var workflowId: String
    var workflowName: String
    var status: RunStatus
    var blocks: [BlockRunState]
    var currentIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(workflow: Workflow) {
        self.id = UUID().uuidString
        self.workflowId = workflow.id
        self.workflowName = workflow.name
        self.status = .pending
        self.blocks = workflow.blocks.map {
            BlockRunState(id: $0.id, kind: $0.kind, title: $0.title, config: $0.config,
                          status: .pending, output: "", error: nil,
                          startedAt: nil, finishedAt: nil)
        }
        self.currentIndex = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, workflowId, workflowName, status, blocks, currentIndex, createdAt, updatedAt
    }
}

// Hand-written decoding so a run persisted by an older/newer build decodes gracefully.
extension WorkflowRun {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        workflowId   = try c.decodeIfPresent(String.self, forKey: .workflowId) ?? ""
        workflowName = try c.decodeIfPresent(String.self, forKey: .workflowName) ?? ""
        status       = try c.decodeIfPresent(RunStatus.self, forKey: .status) ?? .pending
        blocks       = try c.decodeIfPresent([BlockRunState].self, forKey: .blocks) ?? []
        currentIndex = try c.decodeIfPresent(Int.self, forKey: .currentIndex) ?? 0
        createdAt    = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt    = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Built-in templates

extension Workflow {
    /// Every ready-made workflow offered under "New from template".
    static func templates() -> [Workflow] {
        [sprintKickoffTemplate(), taskSpecTemplate(), dailyDigestTemplate(), bugTriageTemplate(), repoReportTemplate()]
    }

    /// Showcases the wizard-reuse chain: a task title → Create Description → Create Solution,
    /// paused for review at the end. Uses the exact description/solution agents the wizard runs.
    static func taskSpecTemplate() -> Workflow {
        Workflow(
            name: "Task Spec (Description → Solution)",
            summary: "Turn a task title into a grounded description, then an implementation plan, then review.",
            blocks: [
                WorkflowBlock(kind: .createDescription, title: "Create description"),
                WorkflowBlock(kind: .createSolution, title: "Create solution"),
                WorkflowBlock(kind: .manualReview, title: "Review spec", config: {
                    var c = WorkflowBlockConfig()
                    c.reviewInstructions = "Review the description + solution. Edit if needed."
                    return c
                }()),
            ]
        )
    }

    /// A single repoReport block — summarize recent repo activity via git.
    static func repoReportTemplate() -> Workflow {
        Workflow(
            name: "Repo Report",
            summary: "Summarize recent commits, active branches, and churn in the scoped repos.",
            blocks: [
                WorkflowBlock(kind: .repoReport, title: "Repo activity report", config: {
                    var c = WorkflowBlockConfig()
                    c.sinceRef = "the last 2 weeks"
                    return c
                }()),
            ]
        )
    }

    /// Composed re-imagining of the built-in kickoff→split→wizard pipeline: split a sprint
    /// dump into tasks, let the user review, then create the tickets. Complements (does not
    /// replace) the dedicated wizard flow.
    static func sprintKickoffTemplate() -> Workflow {
        Workflow(
            name: "Sprint Kickoff",
            summary: "Split a sprint description into atomic tasks, review them, then create tickets.",
            blocks: [
                WorkflowBlock(kind: .agentPrompt, title: "Split sprint into tasks", config: {
                    var c = WorkflowBlockConfig()
                    c.expectJSON = true
                    c.systemPrompt = """
                    You are the Cadence sprint splitter. Given a sprint description + scoped repos (paths provided),
                    split the sprint into atomic tasks (one concrete deliverable each). You have FULL repo access —
                    Read, Grep, Glob, Bash(git *). Explore before answering.

                    Return JSON ONLY, no prose, no code fences:
                    {"tickets":[{"title":"...","description":"one-paragraph rationale citing a real file/symbol","priority":"P0-P4","estimate":0,"labels":[]}]}

                    Rules:
                    - Titles ≤ 80 chars, imperative, atomic.
                    - Every description must cite a file/symbol you actually read. Never fabricate paths.
                    - Priority default P3 unless the description signals urgency.
                    """
                    c.promptTemplate = """
                    SPRINT DESCRIPTION:
                    {{input}}

                    REPOS FOR CONTEXT:
                    {{repos}}
                    """
                    return c
                }()),
                WorkflowBlock(kind: .manualReview, title: "Review proposed tasks", config: {
                    var c = WorkflowBlockConfig()
                    c.reviewInstructions = "Review (and optionally edit) the proposed tasks JSON before tickets are created."
                    return c
                }()),
                WorkflowBlock(kind: .createTickets, title: "Create tickets", config: WorkflowBlockConfig()),
            ]
        )
    }

    /// agentPrompt → summarize workflow that fills the daily digest. The summarize block
    /// persists through AppState.persistDigest (the existing digest path).
    static func dailyDigestTemplate() -> Workflow {
        Workflow(
            name: "Daily Digest",
            summary: "Review recent ticket activity and draft a Slack-ready standup digest.",
            blocks: [
                WorkflowBlock(kind: .agentPrompt, title: "Gather ticket activity", config: {
                    var c = WorkflowBlockConfig()
                    c.expectJSON = false
                    c.systemPrompt = """
                    You are the Cadence digest reporter. Read the Cadence issues folder (one markdown file per
                    issue under issues/<ID>/issue.md) with your native Read/Grep/Glob tools. Summarize the current
                    state of work: what is In Progress, what moved to Done recently, what is blocked, and any P0/P1
                    open items. Cite ticket IDs and titles you actually read. Do NOT fabricate.
                    """
                    c.promptTemplate = """
                    Produce a concise markdown summary of current ticket activity for today's standup.
                    Group into ## In progress, ## Recently done, ## Blocked, ## Needs attention.
                    """
                    return c
                }()),
                WorkflowBlock(kind: .summarize, title: "Draft standup digest", config: {
                    var c = WorkflowBlockConfig()
                    c.heading = "Daily Standup Digest"
                    c.persistAsDigest = true
                    c.promptTemplate = """
                    Rewrite the following into a crisp, Slack-ready standup digest. Keep it skimmable with short
                    bullet points under clear headings. Lead with anything urgent. Content:

                    {{input}}
                    """
                    return c
                }()),
            ]
        )
    }

    /// agentPrompt over a repo → createTickets. Turns a bug scan into filed tickets.
    static func bugTriageTemplate() -> Workflow {
        Workflow(
            name: "Bug Triage",
            summary: "Scan a repo for likely bugs / tech debt and file them as tickets.",
            blocks: [
                WorkflowBlock(kind: .agentPrompt, title: "Scan repo for issues", config: {
                    var c = WorkflowBlockConfig()
                    c.expectJSON = true
                    c.systemPrompt = """
                    You are the Cadence bug triager. Explore the scoped repos with Read, Grep, Glob, Bash(git *)
                    and identify concrete bugs, correctness risks, or high-value tech debt. Prefer things you can
                    point at in real code.

                    Return JSON ONLY, no prose, no code fences:
                    {"tickets":[{"title":"...","description":"what's wrong + where (cite file:line) + suggested fix","priority":"P0-P4","estimate":0,"labels":["bug"]}]}

                    Rules:
                    - Only report issues grounded in code you actually read; cite exact paths.
                    - Titles ≤ 80 chars, imperative. Priority reflects real severity.
                    """
                    c.promptTemplate = """
                    Focus: {{input}}

                    REPOS TO SCAN:
                    {{repos}}
                    """
                    return c
                }()),
                WorkflowBlock(kind: .createTickets, title: "File bug tickets", config: {
                    var c = WorkflowBlockConfig()
                    c.defaultStatus = "Backlog"
                    return c
                }()),
            ]
        )
    }
}
