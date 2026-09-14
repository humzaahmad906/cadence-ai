import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var tickets: [Ticket] = []
    @Published var currentSprint: Sprint?
    @Published var digestDraft: String = ""
    @Published var selectedTicketId: String?
    @Published var conversations: [Conversation] = []
    @Published var currentConversationId: UUID?
    @Published var lastRefresh: Date = .distantPast

    /// Current conversation's chat log (computed).
    var chatLog: [ChatEntry] {
        get { currentConversation?.entries ?? [] }
        set {
            guard let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) else { return }
            conversations[idx].entries = newValue
            conversations[idx].updatedAt = Date()
            ChatStore.save(conversations)
        }
    }

    var currentConversation: Conversation? {
        conversations.first { $0.id == currentConversationId }
    }
    @Published var repos: [RepoNode] = []

    // Canvas router
    @Published var currentArtifact: CanvasArtifact = .workflows
    @Published var artifactBack: [CanvasArtifact] = []
    @Published var artifactForward: [CanvasArtifact] = []

    // Ambient strip
    @Published var ambientEvents: [AmbientEvent] = []
    private let ambientCap = 8

    func setArtifact(_ a: CanvasArtifact, recordHistory: Bool = true) {
        guard a != currentArtifact else { return }
        if recordHistory {
            artifactBack.append(currentArtifact)
            artifactForward = []
            if artifactBack.count > 40 { artifactBack.removeFirst() }
        }
        currentArtifact = a
    }

    func goBackArtifact() {
        guard let prev = artifactBack.popLast() else { return }
        artifactForward.append(currentArtifact)
        currentArtifact = prev
    }

    func goForwardArtifact() {
        guard let next = artifactForward.popLast() else { return }
        artifactBack.append(currentArtifact)
        currentArtifact = next
    }

    func addAmbient(_ event: AmbientEvent) {
        ambientEvents.insert(event, at: 0)
        if ambientEvents.count > ambientCap { ambientEvents.removeLast() }
    }

    func dismissAmbient(_ id: UUID) {
        ambientEvents.removeAll { $0.id == id }
    }

    let store = IssueStore()
    let repoRegistry = RepoRegistry()
    let claude = ClaudeBridge()
    let workflowStore = WorkflowStore()
    let dayStore = DayStore()
    let activityLog = ActivityLog()

    // MARK: claude CLI settings (Services/ClaudeSettings.swift)

    @Published var claudeSettings = ClaudeSettings.load()

    /// Persist and push to the bridge, so the next CLI call uses the new model without a relaunch.
    func updateClaudeSettings(_ s: ClaudeSettings) {
        claudeSettings = s
        s.save()
        Task { await claude.apply(s) }
    }

    // MARK: day plan (Models/Day.swift + Services/DayStore.swift)

    /// Drives the menu bar's per-second redraw. Kept in sync here rather than in the view so
    /// it starts and stops with the data, whatever changed it.
    let ticker = SecondTicker()

    @Published var day: DayPlan = DayPlan.seed(date: DayPlan.key(for: Date())) {
        didSet { ticker.setRunning(day.runningBlockId != nil) }
    }
    @Published var dayHistory: [DayPlan] = []

    /// Load today, carrying yesterday's shape forward on the first open of the day.
    func loadDay() {
        let result = dayStore.today()
        day = result.plan
        // A timer left running when the app quit would otherwise bill every hour it was closed.
        let before = day
        day.reconcileTimers()
        if day != before { dayStore.save(day) }
        if let previous = result.rolledFrom { archive(previous) }
        dayHistory = dayStore.recent(limit: 15).filter { $0.date != day.date }
    }

    func saveDay() {
        dayStore.save(day)
    }

    /// Write a finished day into the log. Blocks start empty each morning, so this is the only
    /// record of what was in them — no judgement about which tasks counted as finished, just
    /// what was there and how long the block ran.
    private func archive(_ plan: DayPlan) {
        let at = DayPlan.boundary(after: plan.endOfDay)
        for block in plan.blocks where !block.tasks.isEmpty || block.secondsSpent > 0 {
            let tracked = block.secondsSpent > 0 ? DayBlock.clock(block.secondsSpent) : "not timed"
            let items = block.tasks.map { ($0.done ? "✓ " : "· ") + $0.text }.joined(separator: "   ")
            activityLog.append(ActivityEvent(
                kind: .dayArchive,
                outcome: block.secondsSpent > 0 ? .ok : .info,
                title: "\(block.name) — \(tracked)",
                detail: items.isEmpty ? "nothing listed" : items,
                at: at))
        }
    }
    lazy var runner = WorkflowRunner(appState: self)

    // Composable workflows (block-based). See Models/Workflow.swift + Services/WorkflowRunner.swift.
    @Published var workflows: [Workflow] = []
    @Published var activeRun: WorkflowRun?

    // Debug: single-block run output/state in the builder, keyed by block id.
    @Published var debugOutput: [UUID: String] = [:]
    @Published var debugRunningId: UUID?
    private var debugTask: Task<Void, Never>?

    init() {
        self.conversations = ChatStore.loadConversations()
        if self.conversations.isEmpty {
            let c = Conversation(title: "New chat")
            self.conversations = [c]
            self.currentConversationId = c.id
            ChatStore.save(self.conversations)
        } else {
            self.currentConversationId = self.conversations.last?.id
        }
        // Restore persisted UI state
        let ui = UIStateStore.load()
        self.digestDraft = ui.digestDraft
        self.savedRoute = ui.route
    }

    func newConversation() {
        let c = Conversation(title: "New chat")
        conversations.append(c)
        currentConversationId = c.id
        ChatStore.save(conversations)
    }

    func switchConversation(_ id: UUID) {
        currentConversationId = id
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty { newConversation() }
        else if currentConversationId == id { currentConversationId = conversations.last?.id }
        ChatStore.save(conversations)
    }

    func renameCurrent(to title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) else { return }
        conversations[idx].title = title
        ChatStore.save(conversations)
    }

    @Published var savedRoute: String = "Dashboard"
    @Published var bootstrapError: String?
    @Published var focusedNode: (type: String, id: String)?
    @Published var pendingChatPrompt: String?  // populated when a UI button wants to send a chat message

    // Navigation history stacks
    @Published var navBack: [NavHistoryEntry] = []
    @Published var navForward: [NavHistoryEntry] = []

    // Live agent status (streaming tool call visibility)
    @Published var agentRunning: Bool = false
    @Published var agentCurrentTool: String?
    @Published var agentToolCount: Int = 0
    @Published var agentStartTime: Date?
    @Published var agentToolLog: [String] = []

    /// Set node focus and switch to graph route. Views observe focusedNode + navigate.
    func focus(type: String, id: String) {
        focusedNode = (type, id)
    }

    /// Push current location onto back stack; clears forward stack.
    func pushNav(routeRaw: String) {
        let entry = NavHistoryEntry(
            routeRaw: routeRaw,
            focusedType: focusedNode?.type,
            focusedId: focusedNode?.id
        )
        if let last = navBack.last, last == entry { return }
        navBack.append(entry)
        navForward = []
        if navBack.count > 60 { navBack.removeFirst() }
    }

    func goBack() -> NavHistoryEntry? {
        guard navBack.count >= 2 else { return nil }
        let current = navBack.removeLast()
        navForward.append(current)
        return navBack.last
    }

    func goForward() -> NavHistoryEntry? {
        guard let next = navForward.popLast() else { return nil }
        navBack.append(next)
        return next
    }

    @Published var branchCatalog: [String: BranchCatalog] = [:]  // repoId -> catalog

    /// Load branch list for a repo (cached in branchCatalog).
    @Published var indexingRepoPath: String?
    @Published var exploringRepoId: String?

    /// Register a repo folder in the local registry (no indexing — the agent reads files live).
    @discardableResult
    func indexRepoDirectly(path: String, name: String = "") async -> String? {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "empty path" }
        indexingRepoPath = clean
        defer { indexingRepoPath = nil }
        let node = repoRegistry.add(name: name.isEmpty ? (clean as NSString).lastPathComponent : name, path: clean)
        await refresh()
        addAmbient(AmbientEvent(kind: .info, text: "Registered \(node.name) (\(node.fileCount) files).", at: Date(), target: nil))
        return nil
    }

    func removeRepo(_ repoId: String) async {
        repoRegistry.remove(id: repoId)
        await refresh()
    }

    func loadBranches(for repoId: String) async {
        guard let repo = repos.first(where: { $0.id == repoId }) else {
            branchCatalog[repoId] = BranchCatalog(); return
        }
        let result = repoRegistry.branches(repoPath: repo.path)
        branchCatalog[repoId] = BranchCatalog(current: result.current, branches: result.branches)
    }

    /// Returns absolute paths for a set of repo IDs — used to grant --add-dir access.
    func repoPaths(for repoIds: [String]) -> [String] {
        repos.filter { repoIds.contains($0.id) }.map { $0.path }
    }

    /// Shared "description writer" agent, reused by the wizard AND the workflow `createDescription`
    /// block. Explores the scoped repos and returns (exploration, description) markdown. Manages
    /// the agent status indicators itself.
    func descriptionAgent(taskTitle: String, sprintName: String, repoIds: [String], branches: [String: String] = [:], model: String = "", effort: String = "") async throws -> (exploration: String, description: String) {
        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { repoIds.contains($0.id) }
            .map { r -> String in
                let br = branches[r.id] ?? ""
                return "\(r.id)|\(r.name)|\(r.path)|branch=\(br.isEmpty ? "(default)" : br)"
            }
            .joined(separator: "\n")

        let systemPrompt = """
        You are the Cadence description writer. Given ONE task + tagged repos (paths + branches provided),
        explore the repo with native tools, then write a rich task description grounded in real code.

        You have FULL repo access — Read, Grep, Glob, Bash(git *). YOU decide what to read.

        Return JSON ONLY, no prose outside JSON, no code fences:
        {"exploration":"markdown notes on what you found in the repo — files read, relevant symbols, how the code works today, with exact paths",
         "description":"markdown body with these sections: ## Purpose\\n## Context\\n## Approach\\n## Verification"}

        Rules:
        - `exploration` = your raw findings, saved verbatim to exploration.md for the record.
        - `description` = the polished task description, built from the exploration + the task title.
        - Every claim MUST cite a file you actually read. Reference function/class names by exact identifier.
        - Keep description to 4 sections, under 500 words.
        """

        let userTurn = """
        TASK: \(taskTitle)
        SPRINT: \(sprintName)

        REPOS (paths given so you can Read/Grep/Glob directly):
        \(repoBlock.isEmpty ? "(none)" : repoBlock)
        """

        let obj = try await claude.promptAgentJSONStreaming(
            userMessage: userTurn,
            systemPrompt: systemPrompt,
            onToolUse: { [weak self] name in
                guard let self else { return }
                await MainActor.run { self.agentToolCalled(name) }
            },
            addDirs: repoPaths(for: repoIds),
            model: model,
            effort: effort,
            timeout: 360
        )
        let dict = obj as? [String: Any] ?? [:]
        return (dict["exploration"] as? String ?? "", dict["description"] as? String ?? "")
    }

    /// Shared "solution designer" agent, reused by the wizard AND the workflow `createSolution`
    /// block. Returns (exploration, solution) markdown. Manages the agent status indicators itself.
    func solutionAgent(taskTitle: String, description: String, repoIds: [String], branches: [String: String] = [:], model: String = "", effort: String = "") async throws -> (exploration: String, solution: String) {
        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { repoIds.contains($0.id) }
            .map { r -> String in
                let br = branches[r.id] ?? ""
                return "\(r.id)|\(r.name)|\(r.path)|branch=\(br.isEmpty ? "(default)" : br)"
            }
            .joined(separator: "\n")

        let systemPrompt = """
        You are the Cadence solution designer. Given an approved description + tagged repos (paths + branches),
        explore the repo further and write a concrete implementation plan (the "Solution").

        You have FULL repo access — Read, Grep, Glob, Bash(git log/show/blame/diff). Dig as deep as the task needs.

        Return JSON ONLY:
        {"exploration":"markdown notes on the deeper dig — files/functions read, call sites, constraints, with exact paths + line numbers",
         "solution":"markdown body with these sections: ## Approach\\n## Steps (numbered)\\n## Files to touch (list with reason)\\n## Risks"}

        Rules:
        - `exploration` = raw findings, saved verbatim to solution-exploration.md.
        - `solution` = the actionable plan built from the description + exploration.
        - Cite specific function names + line numbers by reading the files. NO fabrication.
        - Steps must be actionable ("Add fallback in `select_backend()` at `training/dist.py:42`" — not "handle the crash").
        """

        let userTurn = """
        TASK: \(taskTitle)
        DESCRIPTION:
        \(description)

        REPOS (paths given for direct Read/Grep/Glob):
        \(repoBlock.isEmpty ? "(none)" : repoBlock)
        """

        let obj = try await claude.promptAgentJSONStreaming(
            userMessage: userTurn,
            systemPrompt: systemPrompt,
            onToolUse: { [weak self] name in
                guard let self else { return }
                await MainActor.run { self.agentToolCalled(name) }
            },
            addDirs: repoPaths(for: repoIds),
            model: model,
            effort: effort,
            timeout: 420
        )
        let dict = obj as? [String: Any] ?? [:]
        return (dict["exploration"] as? String ?? "", dict["solution"] as? String ?? "")
    }

    // Streaming callbacks used by ClaudeBridge.
    func agentStart() {
        agentRunning = true
        agentCurrentTool = nil
        agentToolCount = 0
        agentToolLog = []
        agentStartTime = Date()
    }
    func agentToolCalled(_ name: String) {
        agentCurrentTool = name
        agentToolCount += 1
        agentToolLog.append(name)
    }
    func agentStop() {
        agentRunning = false
        agentCurrentTool = nil
    }

    func requestChat(_ prompt: String) {
        pendingChatPrompt = prompt
    }

    /// Kick off the critique agent in a fresh conversation.
    func requestCritique() {
        newConversation()
        renameCurrent(to: "Critique · \(shortDate())")
        pendingChatPrompt = Self.critiqueGoal
    }

    private static let critiqueGoal = """
    Run a full workspace critique. The issues live as markdown files — one folder per issue — that you can Read/Grep/Glob directly.

    Inspect:
    1. Read every issue.md. Note ones missing a real description, verification, or estimate. Flag issues whose `updated` frontmatter is >7 days old but still open.
    2. Cross-check exploration.md / solution-exploration.md against the issue.md — is the solution grounded in the exploration?
    3. Flag P0/P1 open issues whose solution section is thin or missing.

    Return your final reply as MARKDOWN structured like:

    # Cadence Workspace Critique — <ISO date>

    ## Summary
    - <one-liner metrics>

    ## Blockers (fix now)
    - <bullet items with ticket/file IDs>

    ## Under-specified tickets
    - <ID> — missing: verification / linked files / estimate. Reason: ...

    ## Stale knowledge
    - <doctrine or ticket links whose code moved>

    ## Coverage gaps
    - <repos, concepts, workflows not represented>

    ## Suggested new tickets (Linear-paste format)
    Each ticket in a code block ready for paste:

    ```
    Title: <one line, ≤80 chars>
    Priority: Urgent | High | Medium | Low
    Estimate: <points 1|2|3|5|8>
    Labels: <comma-separated>
    Description:
    <markdown body — problem, approach, references to file paths + ticket IDs>
    ## Verification
    <how success is measured>
    ```

    ## Next 3 actions (concrete)
    1. ...
    2. ...
    3. ...

    Rules:
    - No fluff. If you have nothing to say in a section, write "(none)".
    - Every claim must cite an issue ID or a file path you actually read.
    - Do NOT propose actions with kind:"propose" — this is a review, not a mutation. Reply only.
    """

    private func shortDate() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    /// Format a ticket as Linear-paste-ready markdown block.
    static func linearMarkdown(for t: Ticket) -> String {
        let linearPriority: String = {
            switch t.priority {
            case .p0: return "Urgent"
            case .p1: return "High"
            case .p2: return "Medium"
            case .p3: return "Medium"
            case .p4: return "Low"
            }
        }()
        var body = ""
        body += "Title: \(t.title)\n"
        body += "Priority: \(linearPriority)\n"
        if t.estimate > 0 { body += "Estimate: \(Int(t.estimate))\n" }
        if !t.assignee.isEmpty { body += "Assignee: \(t.assignee)\n" }
        if !t.labels.isEmpty { body += "Labels: \(t.labels.joined(separator: ", "))\n" }
        body += "\nDescription:\n"
        body += t.description.isEmpty ? "(no description)\n" : "\(t.description)\n"
        if !t.results.isEmpty { body += "\n## Results\n\(t.results)\n" }
        if !t.blockers.isEmpty { body += "\n## Blockers\n\(t.blockers)\n" }
        if !t.verification.isEmpty { body += "\n## Verification\n\(t.verification)\n" }
        if !t.notes.isEmpty { body += "\n## Notes\n\(t.notes)\n" }
        return body
    }

    func copyLinearTicket(_ t: Ticket) {
        let md = Self.linearMarkdown(for: t)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        Notifier.post(title: "Copied to clipboard", body: "Paste into Linear.")
    }

    func bootstrap() async {
        bootstrapError = nil
        seedWorkflowsIfNeeded()
        loadDay()
        await refresh()
        currentArtifact = .workflows
    }

    func persistUIState(route: String) {
        savedRoute = route
        UIStateStore.save(UIState(route: route, digestDraft: digestDraft))
    }

    func persistDigest(_ text: String) {
        digestDraft = text
        UIStateStore.save(UIState(route: savedRoute, digestDraft: text))
    }

    func appendChat(_ entry: ChatEntry) {
        guard let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) else { return }
        conversations[idx].entries.append(entry)
        conversations[idx].updatedAt = Date()
        // Auto-title from first user message
        if conversations[idx].title == "New chat", entry.role == "you" {
            conversations[idx].title = String(entry.text.prefix(60))
        }
        ChatStore.save(conversations)
    }

    func clearChat() {
        guard let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) else { return }
        conversations[idx].entries = []
        ChatStore.save(conversations)
    }

    func refresh() async {
        tickets = store.list()
        repos = repoRegistry.list()
        workflows = workflowStore.list()
        lastRefresh = Date()
    }

    // MARK: workflows

    /// Seed the built-in templates as real, editable workflows on first run.
    func seedWorkflowsIfNeeded() {
        guard workflowStore.list().isEmpty else { return }
        for template in Workflow.templates() {
            try? workflowStore.save(template)
        }
    }

    func loadWorkflows() {
        workflows = workflowStore.list()
    }

    /// Persist a workflow (create or update) and refresh the in-memory list.
    func saveWorkflow(_ workflow: Workflow) {
        var w = workflow
        w.updatedAt = Date()
        do {
            try workflowStore.save(w)
            loadWorkflows()
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Save workflow failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
    }

    /// Create a new workflow from a template (or a blank one) and open the builder.
    func createWorkflow(from template: Workflow) {
        // Fresh identity + timestamps so templates can be instantiated repeatedly.
        var w = template
        w.id = UUID().uuidString
        w.createdAt = Date()
        w.updatedAt = Date()
        saveWorkflow(w)
        setArtifact(.workflowBuilder(id: w.id))
    }

    func createBlankWorkflow() {
        let w = Workflow(name: "New workflow", summary: "", blocks: [], repoIds: [])
        saveWorkflow(w)
        setArtifact(.workflowBuilder(id: w.id))
    }

    func deleteWorkflow(_ id: String) {
        try? workflowStore.delete(id)
        loadWorkflows()
        if case .workflowBuilder(let bid) = currentArtifact, bid == id { setArtifact(.workflows) }
    }

    /// Kick off a workflow run. Navigates to the live run view.
    func runWorkflow(_ id: String, navigate: Bool = true) async {
        guard let wf = workflows.first(where: { $0.id == id }) ?? workflowStore.load(id) else {
            addAmbient(AmbientEvent(kind: .error, text: "Workflow not found.", at: Date(), target: nil))
            return
        }
        await runner.start(workflow: wf, navigate: navigate)
    }

    func resumeReview(approve: Bool, editedOutput: String?) async {
        await runner.resumeReview(approve: approve, editedOutput: editedOutput)
    }

    /// Retry: re-run a block (and everything downstream) within the active run.
    func rerunBlock(_ blockId: UUID) async {
        guard let run = activeRun,
              let wf = workflows.first(where: { $0.id == run.workflowId }) ?? workflowStore.load(run.workflowId)
        else { return }
        await runner.rerun(workflow: wf, from: blockId)
    }

    // MARK: run history

    /// Past runs of a workflow, newest first (persisted under workflows/<id>/runs/).
    func runHistory(_ workflowId: String) -> [WorkflowRun] {
        workflowStore.runs(workflowId: workflowId)
    }

    /// Open a saved run read-only in the run view (renders each block's stored output).
    func openRun(_ run: WorkflowRun) {
        activeRun = run
        setArtifact(.workflowRun(id: run.id))
    }

    // MARK: AI builder

    /// Ask Claude to assemble a workflow graph (blocks + edges) from a plain-language prompt.
    func generateWorkflowGraph(from prompt: String) async -> Workflow? {
        let kinds = WorkflowBlockKind.allCases.map { $0.rawValue }.joined(separator: ", ")
        let ask = """
        Return ONLY JSON for a Cadence workflow graph. Available block kinds: \(kinds).
        Shape: {"name":"...","blocks":[{"kind":"<a kind>","title":"..."}],"edges":[[fromIndex,toIndex]]}
        - blocks: ordered, indexed 0..n; choose kinds that fit the request; the first is usually "input".
        - edges: [from,to] block-index pairs describing data flow.
        Keep it minimal and correct. No prose.

        REQUEST:
        \(prompt)
        """
        do {
            let obj = try await claude.promptJSON(ask, timeout: 120)
            guard let d = obj as? [String: Any], let rawBlocks = d["blocks"] as? [[String: Any]] else { return nil }
            var blocks: [WorkflowBlock] = []
            for rb in rawBlocks {
                guard let ks = rb["kind"] as? String, let kind = WorkflowBlockKind(rawValue: ks) else { continue }
                blocks.append(WorkflowBlock(kind: kind, title: (rb["title"] as? String) ?? kind.label))
            }
            guard !blocks.isEmpty else { return nil }
            var edges: [WorkflowEdge] = []
            if let rawEdges = d["edges"] as? [[Any]] {
                for pair in rawEdges where pair.count == 2 {
                    if let f = (pair[0] as? Int) ?? (pair[0] as? Double).map(Int.init),
                       let t = (pair[1] as? Int) ?? (pair[1] as? Double).map(Int.init),
                       f >= 0, f < blocks.count, t >= 0, t < blocks.count {
                        edges.append(WorkflowEdge(from: blocks[f].id, to: blocks[t].id))
                    }
                }
            }
            return Workflow(name: (d["name"] as? String) ?? "AI workflow", summary: prompt,
                            blocks: blocks, edges: edges)
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "AI builder failed: \(error.localizedDescription)", at: Date(), target: nil))
            return nil
        }
    }

    /// Generate a workflow from a prompt, persist it, and open the builder.
    func createWorkflowFromAI(prompt: String) async {
        guard let wf = await generateWorkflowGraph(from: prompt) else { return }
        saveWorkflow(wf)
        setArtifact(.workflowBuilder(id: wf.id))
    }

    // MARK: code blocks (Generate / Validate / standalone Run)

    /// Agent writes the block's Python from its intent + I/O contract. Returns the code ("" on error).
    func generateCode(for block: WorkflowBlock) async -> String {
        let c = block.config
        let prompt = """
        Write a Python 3 script for a data-pipeline "code block". The script reads the previous block's
        output from STDIN and writes this block's output to STDOUT.

        WHAT IT SHOULD DO:
        \(c.codeIntent.isEmpty ? "(transform the input into the output described below)" : c.codeIntent)

        INPUT (stdin): \(c.inputDesc.isEmpty ? "arbitrary text" : c.inputDesc)
        OUTPUT (stdout): \(c.outputDesc.isEmpty ? "the transformed text" : c.outputDesc)

        Rules:
        - Read stdin with sys.stdin.read() if you need the input.
        - Print ONLY the intended output to stdout.
        - If you produce an image/chart, save it to a file and print that file's absolute path as the
          sole output (a viewer block downstream renders it).
        - Prefer the standard library; if you must import a package, assume it is installed.

        Return JSON: {"code":"<the full python script>"}
        """
        do {
            let obj = try await claude.promptJSON(prompt, timeout: 120)
            if let d = obj as? [String: Any], let code = d["code"] as? String { return code }
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Generate code failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
        return ""
    }

    /// Agent statically checks the code against the I/O contract (no execution). (passed, message).
    func validateCode(_ block: WorkflowBlock) async -> (ok: Bool, message: String) {
        let c = block.config
        guard !c.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "No code to validate.")
        }
        let prompt = """
        You validate a Python "code block" in a data pipeline. It reads stdin and writes stdout.
        Judge ONLY whether the code, as written, would consume the described input and produce the
        described output. Reason about it; do not run it.

        INPUT (stdin): \(c.inputDesc.isEmpty ? "(unspecified)" : c.inputDesc)
        OUTPUT (stdout): \(c.outputDesc.isEmpty ? "(unspecified)" : c.outputDesc)

        CODE:
        ```python
        \(c.code)
        ```

        Return JSON: {"valid": true, "reason": "<one or two sentences>"}  (valid may be true or false)
        """
        do {
            let obj = try await claude.promptJSON(prompt, timeout: 120)
            if let d = obj as? [String: Any] {
                return ((d["valid"] as? Bool) ?? false, (d["reason"] as? String) ?? "")
            }
        } catch {
            return (false, "Validation error: \(error.localizedDescription)")
        }
        return (false, "Validator returned no verdict.")
    }

    /// Builder debug: run ONE block in isolation with `input`, storing output in debugOutput[block.id].
    /// Code blocks stream stdout via CodeRunner; every other kind runs its handler to completion
    /// (agent blocks really call claude — it's debugging). Cancelable via cancelDebugRun().
    func debugRunBlock(_ block: WorkflowBlock, workflow: Workflow, input: String) {
        debugTask?.cancel()
        let id = block.id
        debugOutput[id] = ""
        debugRunningId = id
        debugTask = Task { [weak self] in
            guard let self else { return }
            if block.kind == .code {
                let cfg = block.config
                let cwd = self.repoPaths(for: workflow.repoIds).first
                do {
                    let result = try await CodeRunner.shared.run(
                        interpreter: cfg.interpreter,
                        code: cfg.code,
                        stdin: input,
                        workingDirectory: cwd,
                        timeout: 300,
                        onOutput: { chunk in
                            await MainActor.run { self.debugOutput[id, default: ""] += chunk }
                        }
                    )
                    if result.exitCode != 0 {
                        let err = result.stderr.isEmpty ? "(no stderr)" : result.stderr
                        self.debugOutput[id, default: ""] += "\n\n[exit \(result.exitCode)]\n\(err)"
                    }
                } catch is CancellationError {
                    self.debugOutput[id, default: ""] += "\n\n[canceled]"
                } catch {
                    self.debugOutput[id, default: ""] += "\n\n[error] \(error.localizedDescription)"
                }
            } else {
                let handler = WorkflowBlockRegistry.handler(for: block.kind)
                let ctx = BlockRunContext(appState: self, workflow: workflow, input: input)
                do {
                    self.debugOutput[id] = try await handler.run(block, context: ctx)
                } catch {
                    self.debugOutput[id, default: ""] += "[error] \(error.localizedDescription)"
                }
            }
            self.debugRunningId = nil
        }
    }

    func cancelDebugRun() {
        debugTask?.cancel()
    }

    func moveTicket(_ ticket: Ticket, to status: TicketStatus) async {
        guard ticket.status != status else { return }
        do {
            try store.move(id: ticket.id, to: status)
            await refresh()
        } catch { print("move failed: \(error)") }
    }

    func reprioritize(_ ticket: Ticket, to priority: Priority, reason: String) async {
        guard ticket.priority != priority else { return }
        do {
            try store.reprioritize(id: ticket.id, to: priority)
            await refresh()
        } catch { print("reprioritize failed: \(error)") }
    }

    func addComment(ticketId: String, body: String, attachments: [URL]) async {
        do {
            let paths = attachments.map { AttachmentStore.persist(url: $0, ticketId: ticketId) }
            try store.addComment(id: ticketId, body: body, attachments: paths)
            await refresh()
        } catch { print("comment failed: \(error)") }
    }

    func saveTicket(_ ticket: Ticket) async {
        do {
            try store.save(ticket)
            await refresh()
        } catch { print("save failed: \(error)") }
    }

}

struct ChatEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let role: String
    let text: String
    let at: Date
}

struct Conversation: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var entries: [ChatEntry]

    init(id: UUID = UUID(), title: String = "New chat", createdAt: Date = Date(), updatedAt: Date = Date(), entries: [ChatEntry] = []) {
        self.id = id; self.title = title
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.entries = entries
    }
}

struct UIState: Codable {
    var route: String = "Dashboard"
    var digestDraft: String = ""
}

enum UIStateStore {
    static var url: URL { CadencePaths.appSupport.appendingPathComponent("ui_state.json") }
    static func load() -> UIState {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(UIState.self, from: data) else { return UIState() }
        return s
    }
    static func save(_ state: UIState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum ChatStore {
    static var chatsFile: URL { CadencePaths.appSupport.appendingPathComponent("chats.json") }
    static var legacyFile: URL { CadencePaths.appSupport.appendingPathComponent("chat.json") }

    static func loadConversations() -> [Conversation] {
        if let data = try? Data(contentsOf: chatsFile),
           let convs = try? JSONDecoder().decode([Conversation].self, from: data) {
            return convs
        }
        // migrate legacy single-chat file
        if let data = try? Data(contentsOf: legacyFile),
           let entries = try? JSONDecoder().decode([ChatEntry].self, from: data),
           !entries.isEmpty {
            let title = entries.first(where: { $0.role == "you" })?.text.prefix(60).description ?? "Migrated chat"
            return [Conversation(title: title, entries: entries)]
        }
        return []
    }

    static func save(_ convs: [Conversation]) {
        guard let data = try? JSONEncoder().encode(convs) else { return }
        try? data.write(to: chatsFile, options: .atomic)
    }
}

// Navigation history entry for back/forward.
struct NavHistoryEntry: Equatable {
    let routeRaw: String
    let focusedType: String?
    let focusedId: String?
}

/// One editable ticket draft awaiting user approval.
struct TicketDraft: Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var priority: Priority = .p3
    var estimate: Double = 0
    var assignee: String = ""
    var labels: [String] = []
    var project: String?
    var sprint: String?
    var linkedFiles: [LinkedFileHint] = []
    var linkedFunctionalities: [String] = []
    var attachedRepoIds: [String] = []  // repos the user picked for enrichment context
    var solution: String = ""            // implementation plan produced during wizard's solution phase
    /// Per-task file scope: files agent identified as relevant, user can prune.
    /// Description + solution agents operate ONLY within this scope.
    var scopedFiles: [ScopedFile] = []
    var enriched: Bool { !linkedFiles.isEmpty || !linkedFunctionalities.isEmpty }
}

struct ScopedFile: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var reason: String
    var included: Bool = true
}

struct LinkedFileHint: Hashable {
    var query: String
    var note: String
}

struct WizardSession {
    var sprintName: String
    var repoIds: [String]
    var drafts: [TicketDraft]
    var index: Int
    var phase: Phase
    /// Default branch per repo, set at kickoff. Wizard tasks inherit unless overridden per task.
    var defaultBranches: [String: String] = [:]  // repoId -> branch name
    /// Per-task branch overrides. If missing, falls back to defaultBranches.
    var taskBranches: [Int: [String: String]] = [:]  // taskIdx -> repoId -> branch

    enum Phase { case description, solution }

    var current: TicketDraft? {
        guard index < drafts.count else { return nil }
        return drafts[index]
    }

    /// Effective branch for a repo at a given task index.
    func branch(forRepo repoId: String, taskIdx: Int) -> String {
        if let b = taskBranches[taskIdx]?[repoId], !b.isEmpty { return b }
        return defaultBranches[repoId] ?? ""
    }

    static func shortDate() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// Cached branch list per repo. Keyed by repoId.
struct BranchCatalog {
    var current: String = ""
    var branches: [String] = []
}

/// One task proposed by the split agent. User can edit before wizard.
struct ProposedTask: Identifiable, Hashable {
    let id: UUID = UUID()
    var title: String
    var hint: String
    var priority: Priority = .p3
    var estimate: Double = 0
}

/// Staging area between kickoff submit and wizard start.
struct SplitStaging {
    var sprintName: String
    var sprintDescription: String
    var repoIds: [String]
    var defaultBranches: [String: String]
    var tasks: [ProposedTask]
}
