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
    // Source
    case input              // seed the pipeline with typed text (becomes the first block's input)

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

    // Code
    case code               // run a (Python) script that transforms the previous block's output

    var id: String { rawValue }

    var label: String {
        switch self {
        case .input:             return "Input"
        case .agentPrompt:       return "Agent prompt"
        case .createTickets:     return "Create tickets"
        case .manualReview:      return "Manual review"
        case .summarize:         return "Summarize"
        case .createDescription: return "Create description"
        case .createSolution:    return "Create solution"
        case .viewer:            return "Viewer"
        case .docQA:             return "Doc Q&A"
        case .repoReport:        return "Repo report"
        case .code:              return "Code"
        }
    }

    var icon: String {
        switch self {
        case .input:             return "text.cursor"
        case .agentPrompt:       return "sparkles"
        case .createTickets:     return "plus.rectangle.on.rectangle"
        case .manualReview:      return "hand.raised"
        case .summarize:         return "text.append"
        case .createDescription: return "doc.text"
        case .createSolution:    return "list.number"
        case .viewer:            return "eye"
        case .docQA:             return "questionmark.bubble"
        case .repoReport:        return "chart.bar.doc.horizontal"
        case .code:              return "curlybraces"
        }
    }

    var blurb: String {
        switch self {
        case .input:             return "Seed the run with typed text — it becomes the first block's input."
        case .agentPrompt:       return "Run the Claude agent over the workflow's repos and capture its output."
        case .createTickets:     return "Parse the previous block's JSON into tickets and save them."
        case .manualReview:      return "Pause so you can approve or edit before the run continues."
        case .summarize:         return "Fold the running output into a markdown summary."
        case .createDescription: return "Wizard description writer: turn the incoming task title into a grounded description."
        case .createSolution:    return "Wizard solution designer: turn the incoming description into an implementation plan."
        case .viewer:            return "Read-only display of a doc, ticket, repo summary, or the previous block's output."
        case .docQA:             return "Ask a question about a document (or repo docs) and get a cited answer."
        case .repoReport:        return "Summarize recent repo activity (commits, branches, churn) via git."
        case .code:              return "Run a Python script that transforms the previous block's output. Generate it with the agent, or paste your own and validate it."
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

/// A directed connection between two blocks, port to port. Enables fan-out / fan-in —
/// multiple named inputs and outputs — beyond the old linear chain. Empty port = the block's
/// single default port.
struct WorkflowEdge: Codable, Hashable, Identifiable {
    var id: UUID
    var from: UUID
    var to: UUID
    var fromPort: String
    var toPort: String
    init(id: UUID = UUID(), from: UUID, to: UUID, fromPort: String = "", toPort: String = "") {
        self.id = id; self.from = from; self.to = to; self.fromPort = fromPort; self.toPort = toPort
    }
    private enum CodingKeys: String, CodingKey { case id, from, to, fromPort, toPort }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        fromPort = (try? c.decode(String.self, forKey: .fromPort)) ?? ""
        toPort = (try? c.decode(String.self, forKey: .toPort)) ?? ""
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

    // code: a script step. stdin = previous block's output; stdout = this block's output.
    /// code: the script body (Python for v1).
    var code: String = ""
    /// code: interpreter to run it with. A bare name (e.g. "python3") resolves on PATH via /usr/bin/env;
    /// an absolute path (e.g. a venv's python) runs directly.
    var interpreter: String = "python3"
    /// code: human description of the input this block expects — drives Generate + Validate.
    var inputDesc: String = ""
    /// code: human description of the output this block should emit — drives Generate + Validate.
    var outputDesc: String = ""
    /// code: what the block should do; the agent turns this into code in Generate mode.
    var codeIntent: String = ""
    /// code: sample stdin for the builder's standalone Run button. Ignored during a workflow run,
    /// where the previous block's real output is stdin.
    var sampleInput: String = ""
    /// code: true once the agent's Validate check passes; reset whenever the code/contract changes.
    var validated: Bool = false

    /// input: literal text this block emits, seeding the pipeline. Ignores stdin.
    var inputText: String = ""
    /// agent blocks: whether this block gets the workflow's scoped repos (--add-dir). Default on.
    var useRepos: Bool = true
    /// agent blocks: model alias passed to the claude CLI (--model). Empty = CLI default.
    var model: String = ""
    /// agent blocks: effort level passed to the claude CLI (--effort). Empty = CLI default.
    var effort: String = ""

    /// canvas: node position.
    var x: Double = 0
    var y: Double = 0
    /// ports: named input ports (empty → implicit ["input"]); output ports (empty → ["output"];
    /// for multiple outputs the block emits a JSON object whose keys are these names).
    var inputPorts: [String] = []
    var outputPorts: [String] = []

    init() {}

    // Custom decoder so new fields are forward/backward compatible: a workflow.json written by an
    // older build (missing a key) still loads, using the property default instead of throwing.
    private enum CodingKeys: String, CodingKey {
        case systemPrompt, promptTemplate, expectJSON, defaultPriority, defaultStatus
        case reviewInstructions, heading, persistAsDigest, viewerTarget, ticketId
        case docPath, question, sinceRef
        case code, interpreter, inputDesc, outputDesc, codeIntent, sampleInput, validated
        case inputText, useRepos, model, effort
        case x, y, inputPorts, outputPorts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys, _ d: String = "") -> String { (try? c.decode(String.self, forKey: k)) ?? d }
        func bool(_ k: CodingKeys, _ d: Bool = false) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? d }
        systemPrompt = str(.systemPrompt)
        promptTemplate = str(.promptTemplate)
        expectJSON = bool(.expectJSON)
        defaultPriority = str(.defaultPriority, "P3")
        defaultStatus = str(.defaultStatus, "Backlog")
        reviewInstructions = str(.reviewInstructions)
        heading = str(.heading, "Summary")
        persistAsDigest = bool(.persistAsDigest)
        viewerTarget = str(.viewerTarget, ViewerTarget.previousOutput.rawValue)
        ticketId = str(.ticketId)
        docPath = str(.docPath)
        question = str(.question)
        sinceRef = str(.sinceRef)
        code = str(.code)
        interpreter = str(.interpreter, "python3")
        inputDesc = str(.inputDesc)
        outputDesc = str(.outputDesc)
        codeIntent = str(.codeIntent)
        sampleInput = str(.sampleInput)
        validated = bool(.validated)
        inputText = str(.inputText)
        useRepos = bool(.useRepos, true)
        model = str(.model)
        effort = str(.effort)
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        inputPorts = (try? c.decode([String].self, forKey: .inputPorts)) ?? []
        outputPorts = (try? c.decode([String].self, forKey: .outputPorts)) ?? []
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

extension WorkflowBlock {
    /// Effective ports — a block with none declared has a single default input/output port.
    var inputPorts: [String] { config.inputPorts.isEmpty ? ["input"] : config.inputPorts }
    var outputPorts: [String] { config.outputPorts.isEmpty ? ["output"] : config.outputPorts }
}

// MARK: - Workflow

struct Workflow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var summary: String
    var blocks: [WorkflowBlock]
    var repoIds: [String]
    var edges: [WorkflowEdge]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         name: String,
         summary: String = "",
         blocks: [WorkflowBlock] = [],
         repoIds: [String] = [],
         edges: [WorkflowEdge] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.blocks = blocks
        self.repoIds = repoIds
        self.edges = edges
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Tolerant decoder so adding fields (e.g. edges) doesn't break workflow.json written by
    // an older build.
    private enum CodingKeys: String, CodingKey {
        case id, name, summary, blocks, repoIds, edges, createdAt, updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Workflow"
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        blocks = (try? c.decode([WorkflowBlock].self, forKey: .blocks)) ?? []
        repoIds = (try? c.decode([String].self, forKey: .repoIds)) ?? []
        edges = (try? c.decode([WorkflowEdge].self, forKey: .edges)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
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
    var status: BlockRunStatus
    var output: String
    var input: String
    var error: String?
    var startedAt: Date?
    var finishedAt: Date?

    init(id: UUID, kind: WorkflowBlockKind, title: String, status: BlockRunStatus,
         output: String, input: String = "", error: String? = nil,
         startedAt: Date? = nil, finishedAt: Date? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.status = status
        self.output = output; self.input = input; self.error = error
        self.startedAt = startedAt; self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, status, output, input, error, startedAt, finishedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(WorkflowBlockKind.self, forKey: .kind)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        status = (try? c.decode(BlockRunStatus.self, forKey: .status)) ?? .pending
        output = (try? c.decode(String.self, forKey: .output)) ?? ""
        input = (try? c.decode(String.self, forKey: .input)) ?? ""
        error = try? c.decode(String.self, forKey: .error)
        startedAt = try? c.decode(Date.self, forKey: .startedAt)
        finishedAt = try? c.decode(Date.self, forKey: .finishedAt)
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
            BlockRunState(id: $0.id, kind: $0.kind, title: $0.title,
                          status: .pending, output: "", error: nil,
                          startedAt: nil, finishedAt: nil)
        }
        self.currentIndex = 0
        self.createdAt = Date()
        self.updatedAt = Date()
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
