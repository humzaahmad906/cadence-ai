import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var tickets: [Ticket] = []
    @Published var currentSprint: Sprint?
    @Published var projects: [Project] = []
    @Published var showPasteSprint = false
    @Published var showDigestPreview = false
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
    @Published var currentArtifact: CanvasArtifact = .kickoff
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

    // Pending drafts (signature flow A)
    @Published var pendingDrafts: [TicketDraft] = []

    // Wizard session (multi-step task workflow)
    @Published var wizard: WizardSession?
    @Published var branchCatalog: [String: BranchCatalog] = [:]  // repoId -> catalog

    // Task-split staging (between kickoff and wizard)
    @Published var splitStaging: SplitStaging?

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

    func setWizardTaskBranch(taskIdx: Int, repoId: String, branch: String) {
        guard var w = wizard else { return }
        var perTask = w.taskBranches[taskIdx] ?? [:]
        perTask[repoId] = branch
        w.taskBranches[taskIdx] = perTask
        wizard = w
    }

    func setWizardDefaultBranch(repoId: String, branch: String) {
        guard var w = wizard else { return }
        w.defaultBranches[repoId] = branch
        wizard = w
    }

    /// Returns absolute paths for a set of repo IDs — used to grant --add-dir access.
    private func repoPaths(for repoIds: [String]) -> [String] {
        repos.filter { repoIds.contains($0.id) }.map { $0.path }
    }

    /// Kickoff: user provides sprint description + repos. Agent splits into task drafts.
    /// Advances canvas to .taskSplit where user can review/edit before wizard.
    func submitSprintKickoff(sprintName: String, sprintDescription: String, repoIds: [String], defaultBranches: [String: String]) async {
        let desc = sprintDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return }

        appendChat(ChatEntry(role: "you", text: "SPRINT KICKOFF: \(desc)", at: Date()))

        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { repoIds.contains($0.id) }
            .map { r -> String in
                let br = defaultBranches[r.id] ?? ""
                return "\(r.id)|\(r.name)|\(r.path)|branch=\(br.isEmpty ? "(HEAD)" : br)"
            }
            .joined(separator: "\n")

        let systemPrompt = """
        You are the Cadence sprint splitter. Given a user's free-form sprint description + one or more repos (paths provided),
        split the sprint into atomic tasks (one concrete deliverable each).

        You have FULL repo access. Explore freely with native tools:
        Read any file, Grep for patterns, Glob for paths, Bash(git *) for history.
        You decide what to explore. Grepping README.md, key entry points, and top-level directories often gives fast structure.

        Return JSON ONLY, no prose, no code fences:
        {"tasks":[{"title":"...","hint":"one-line rationale citing a file/symbol","priority":"P0-P4","estimate":0}]}

        Rules:
        - Titles ≤ 80 chars, imperative form, atomic (one deliverable each).
        - hint = one-line rationale grounded in real code (mention a file/symbol/functionality — cite by real path).
        - Priority default P3 unless the dump signals urgency.
        - Number of tasks: infer from the description — could be 1 to 12.
        - Never fabricate file/function names — only cite what you actually read.
        """

        let userTurn = """
        SPRINT: \(sprintName.isEmpty ? "(unnamed)" : sprintName)

        USER DESCRIPTION:
        \(desc)

        REPOS FOR CONTEXT:
        \(repoBlock.isEmpty ? "(none)" : repoBlock)
        """

        do {
            let obj = try await claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: { [weak self] name in
                    guard let self else { return }
                    await MainActor.run { self.agentToolCalled(name) }
                },
                addDirs: repoPaths(for: repoIds),
                timeout: 300
            )
            guard let dict = obj as? [String: Any],
                  let arr = dict["tasks"] as? [[String: Any]] else {
                appendChat(ChatEntry(role: "claude", text: "Split parse failed. Try refining the description.", at: Date()))
                return
            }
            var proposed: [ProposedTask] = []
            for r in arr {
                guard let title = r["title"] as? String else { continue }
                var p = ProposedTask(title: title, hint: r["hint"] as? String ?? "")
                if let ps = r["priority"] as? String, let pr = Priority(rawValue: ps) { p.priority = pr }
                if let e = r["estimate"] as? Double { p.estimate = e }
                else if let e = r["estimate"] as? Int { p.estimate = Double(e) }
                proposed.append(p)
            }
            splitStaging = SplitStaging(
                sprintName: sprintName,
                sprintDescription: desc,
                repoIds: repoIds,
                defaultBranches: defaultBranches,
                tasks: proposed
            )
            appendChat(ChatEntry(role: "claude", text: "Split into \(proposed.count) task\(proposed.count == 1 ? "" : "s"). Review before running the wizard.", at: Date()))
            setArtifact(.taskSplit)
        } catch {
            appendChat(ChatEntry(role: "claude", text: "Split error: \(error.localizedDescription)", at: Date()))
        }
    }

    func regenerateSplit() async {
        guard let s = splitStaging else { return }
        await submitSprintKickoff(
            sprintName: s.sprintName,
            sprintDescription: s.sprintDescription,
            repoIds: s.repoIds,
            defaultBranches: s.defaultBranches
        )
    }

    func splitAddEmptyTask() {
        guard var s = splitStaging else { return }
        s.tasks.append(ProposedTask(title: "", hint: ""))
        splitStaging = s
    }

    func splitRemoveTask(at idx: Int) {
        guard var s = splitStaging, idx < s.tasks.count else { return }
        s.tasks.remove(at: idx)
        splitStaging = s
    }

    func splitMoveTask(from src: Int, to dst: Int) {
        guard var s = splitStaging, src < s.tasks.count, dst <= s.tasks.count, src != dst else { return }
        let item = s.tasks.remove(at: src)
        let insertAt = dst > src ? dst - 1 : dst
        s.tasks.insert(item, at: min(insertAt, s.tasks.count))
        splitStaging = s
    }

    func splitUpdateTask(_ idx: Int, _ mutate: (inout ProposedTask) -> Void) {
        guard var s = splitStaging, idx < s.tasks.count else { return }
        mutate(&s.tasks[idx])
        splitStaging = s
    }

    /// User confirmed the split. Kick off the wizard proper.
    func splitProceedToWizard() async {
        guard let s = splitStaging else { return }
        let titles = s.tasks.map { $0.title.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !titles.isEmpty else { return }
        splitStaging = nil
        await startWizard(
            sprintName: s.sprintName,
            repoIds: s.repoIds,
            defaultBranches: s.defaultBranches,
            taskTitles: titles
        )
    }

    /// Kick off the wizard with sprint name, repo IDs, default branches per repo, and task titles.
    /// Advances canvas to .wizard on task 1's description phase.
    func startWizard(sprintName: String, repoIds: [String], defaultBranches: [String: String] = [:], taskTitles: [String]) async {
        let cleanTitles = taskTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanTitles.isEmpty else { return }

        // Generate ticket IDs based on existing + prefix
        let existingIds = tickets.map { $0.id }
        let prefix = detectPrefix() ?? "CAD"
        var maxN = existingIds.compactMap { id -> Int? in
            let comps = id.split(separator: "-")
            guard comps.count == 2, let n = Int(comps[1]) else { return nil }
            return n
        }.max() ?? 0

        var drafts: [TicketDraft] = []
        for title in cleanTitles {
            maxN += 1
            var d = TicketDraft(id: "\(prefix)-\(maxN)", title: title, description: "")
            d.attachedRepoIds = repoIds
            d.sprint = currentSprint?.id
            drafts.append(d)
        }

        wizard = WizardSession(
            sprintName: sprintName.isEmpty ? "Sprint \(WizardSession.shortDate())" : sprintName,
            repoIds: repoIds,
            drafts: drafts,
            index: 0,
            phase: .description,
            defaultBranches: defaultBranches
        )
        setArtifact(.wizard)
        // Agent has full repo access; jump straight to description generation.
        await generateDescriptionForCurrent()
    }

    private func detectPrefix() -> String? {
        // Look at existing tickets — if they share a prefix like "PXLV-", reuse.
        let prefixes = tickets.compactMap { t -> String? in
            let comps = t.id.split(separator: "-")
            return comps.count == 2 ? String(comps[0]) : nil
        }
        return Set(prefixes).count == 1 ? prefixes.first : nil
    }

    var wizardCurrentDraft: TicketDraft? {
        guard let w = wizard, w.index < w.drafts.count else { return nil }
        return w.drafts[w.index]
    }

    func updateWizardDraft(_ mutate: (inout TicketDraft) -> Void) {
        guard var w = wizard, w.index < w.drafts.count else { return }
        mutate(&w.drafts[w.index])
        wizard = w
    }

    func generateDescriptionForCurrent() async {
        guard let w = wizard, w.index < w.drafts.count else { return }
        let draft = w.drafts[w.index]
        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { w.repoIds.contains($0.id) }
            .map { r -> String in
                let br = w.branch(forRepo: r.id, taskIdx: w.index)
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
        TASK: \(draft.title)
        SPRINT: \(w.sprintName)

        REPOS (paths given so you can Read/Grep/Glob directly):
        \(repoBlock)
        """

        do {
            let obj = try await claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: { [weak self] name in
                    guard let self else { return }
                    await MainActor.run { self.agentToolCalled(name) }
                },
                addDirs: repoPaths(for: w.repoIds),
                timeout: 360
            )
            if let dict = obj as? [String: Any] {
                if let desc = dict["description"] as? String {
                    updateWizardDraft { $0.description = desc }
                }
                if let exploration = dict["exploration"] as? String {
                    store.writeExploration(id: draft.id, phase: "description", markdown: exploration)
                }
            }
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Description failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
    }

    func generateSolutionForCurrent() async {
        guard let w = wizard, w.index < w.drafts.count else { return }
        let draft = w.drafts[w.index]
        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { w.repoIds.contains($0.id) }
            .map { r -> String in
                let br = w.branch(forRepo: r.id, taskIdx: w.index)
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
        TASK: \(draft.title)
        DESCRIPTION:
        \(draft.description)

        REPOS (paths given for direct Read/Grep/Glob):
        \(repoBlock)
        """

        do {
            let obj = try await claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: { [weak self] name in
                    guard let self else { return }
                    await MainActor.run { self.agentToolCalled(name) }
                },
                addDirs: repoPaths(for: w.repoIds),
                timeout: 420
            )
            guard let dict = obj as? [String: Any] else { return }
            if let s = dict["solution"] as? String {
                updateWizardDraft { $0.solution = s }
            }
            if let exploration = dict["exploration"] as? String {
                store.writeExploration(id: draft.id, phase: "solution", markdown: exploration)
            }
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Solution failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
    }

    /// Advance from description phase to solution phase; auto-generate solution.
    func wizardContinueToSolution() async {
        guard var w = wizard else { return }
        w.phase = .solution
        wizard = w
        await generateSolutionForCurrent()
    }

    /// Go back from solution to description (edit description again).
    func wizardBackToDescription() {
        guard var w = wizard else { return }
        w.phase = .description
        wizard = w
    }

    /// Commit current draft as a real Ticket + links, then advance to next task.
    func wizardCommitAndAdvance() async {
        guard var w = wizard, w.index < w.drafts.count else { return }
        let d = w.drafts[w.index]

        // Assemble issue.md body: ## Description + ## Solution
        var body = "## Description\n\n\(d.description)"
        if !d.solution.isEmpty {
            body += "\n\n## Solution\n\n\(d.solution)"
        }

        let ticket = Ticket(
            id: d.id, title: d.title, description: body,
            status: .backlog, priority: d.priority,
            estimate: d.estimate, assignee: d.assignee, labels: d.labels,
            project: d.project, sprint: d.sprint ?? currentSprint?.id,
            results: "", blockers: "", verification: "", notes: "", timeLog: "",
            created: "", updated: ""
        )

        let firstRepo = d.attachedRepoIds.first ?? ""
        let branch = firstRepo.isEmpty ? "" : w.branch(forRepo: firstRepo, taskIdx: w.index)
        do {
            try store.save(ticket, repo: firstRepo, branch: branch)
            addAmbient(AmbientEvent(kind: .info, text: "Created \(d.id) — \(d.title)", at: Date(), target: .ticketDetail(id: d.id)))
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Commit \(d.id) failed: \(error.localizedDescription)", at: Date(), target: nil))
            return
        }

        // Advance
        w.index += 1
        w.phase = .description
        wizard = w
        await refresh()

        if w.index >= w.drafts.count {
            // Done
            wizard = nil
            setArtifact(.kanban)
        } else {
            await generateDescriptionForCurrent()
        }
    }

    /// Skip current task without creating a ticket. Advance to next.
    func wizardSkipCurrent() async {
        guard var w = wizard else { return }
        w.index += 1
        w.phase = .description
        wizard = w
        if w.index >= w.drafts.count {
            wizard = nil
            setArtifact(.kanban)
        } else {
            await generateDescriptionForCurrent()
        }
    }

    func wizardCancel() {
        wizard = nil
        setArtifact(.kickoff)
    }

    func addPendingDraft(_ d: TicketDraft) {
        pendingDrafts.append(d)
    }

    func rejectDraft(_ d: TicketDraft) {
        pendingDrafts.removeAll { $0.id == d.id }
    }

    func approveDraft(_ d: TicketDraft) async {
        let ticket = Ticket(
            id: d.id, title: d.title, description: d.description,
            status: .backlog, priority: d.priority,
            estimate: d.estimate, assignee: d.assignee, labels: d.labels,
            project: d.project, sprint: d.sprint ?? currentSprint?.id,
            results: "", blockers: "", verification: "", notes: "", timeLog: "",
            created: "", updated: ""
        )
        do {
            try store.save(ticket, repo: d.attachedRepoIds.first ?? "", branch: "")
            pendingDrafts.removeAll { $0.id == d.id }
            await refresh()
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Draft \(d.id) failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
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
        do {
            bootstrapError = nil
            await refresh()
            // Pick landing artifact based on state
            if !pendingDrafts.isEmpty {
                currentArtifact = .draftStack
            } else if tickets.isEmpty {
                currentArtifact = .kickoff
            } else {
                currentArtifact = .sprintStatus
            }
        } catch {
            bootstrapError = "Load failed: \(error.localizedDescription)."
            print("bootstrap failed: \(error)")
        }
    }

    // MARK: kickoff pipeline

    @Published var kickoffBusy: Bool = false

    /// User dumped a sprint intent. Agent splits it into draft tickets.
    /// Drafts are minimal (title + priority + rough description); enrichment per-draft comes later.
    func submitKickoff(text: String) async {
        let dump = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dump.isEmpty else { return }

        // Log the kickoff into current chat so the conversation shows what happened
        appendChat(ChatEntry(role: "you", text: dump, at: Date()))

        kickoffBusy = true
        agentStart()
        defer { kickoffBusy = false; agentStop() }

        let existingIds = tickets.map { $0.id }
        let repoDump = repos.map { "\($0.id)|\($0.name)|\($0.path)" }.joined(separator: "\n")

        let systemPrompt = """
        You are the Cadence sprint kickoff agent. Split the user's dump into distinct ticket drafts.

        Rules:
        - Return JSON ONLY, no prose outside JSON, no code fences.
        - Shape: {"drafts":[{"id":"PROJ-N","title":"...","description":"initial rough description","priority":"P0|P1|P2|P3|P4","estimate":0,"labels":[]}]}
        - Generate ticket IDs using an evident project prefix if one is implied, else CAD-N. N MUST be unique and higher than any existing ID.
        - Existing ticket IDs to avoid: \(existingIds.joined(separator: ", "))
        - Titles: ≤80 chars, imperative form, no ticket-ID prefix.
        - description: 1-3 sentence rough draft — later steps will enrich with repo context.
        - Priority default P3 unless the dump signals urgency.
        - Estimate 0 unless clearly stated.
        - Aim for atomic tickets: one concrete outcome per draft.
        """

        let userTurn = """
        USER DUMP:
        \(dump)

        REPOS AVAILABLE FOR LATER CONTEXT (do NOT link yet — that's a later step):
        \(repoDump.isEmpty ? "(none indexed)" : repoDump)
        """

        do {
            let obj = try await claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: { [weak self] name in
                    guard let self else { return }
                    await MainActor.run { self.agentToolCalled(name) }
                },
                timeout: 180
            )
            guard let dict = obj as? [String: Any],
                  let arr = dict["drafts"] as? [[String: Any]] else {
                appendChat(ChatEntry(role: "claude", text: "Kickoff parse failed. Try again with a clearer dump.", at: Date()))
                return
            }
            var newDrafts: [TicketDraft] = []
            for r in arr {
                guard let id = r["id"] as? String, let title = r["title"] as? String else { continue }
                var d = TicketDraft(id: id, title: title, description: r["description"] as? String ?? "")
                if let ps = r["priority"] as? String, let p = Priority(rawValue: ps) { d.priority = p }
                if let e = r["estimate"] as? Double { d.estimate = e }
                else if let e = r["estimate"] as? Int { d.estimate = Double(e) }
                if let l = r["labels"] as? [String] { d.labels = l }
                d.sprint = currentSprint?.id
                newDrafts.append(d)
            }
            pendingDrafts = newDrafts
            appendChat(ChatEntry(role: "claude", text: "Drafted \(newDrafts.count) ticket(s). Review, attach repos per ticket, then approve.", at: Date()))
            setArtifact(.draftStack)
        } catch {
            appendChat(ChatEntry(role: "claude", text: "Kickoff error: \(error.localizedDescription)", at: Date()))
        }
    }

    /// Enrich one draft using selected repos: agent reads files, expands description + verification,
    /// proposes file links + functionality links. Returns the enriched draft (still pending).
    func enrichDraft(_ draft: TicketDraft, withRepoIds repoIds: [String]) async {
        guard !repoIds.isEmpty else { return }
        agentStart()
        defer { agentStop() }

        let repoBlock = repos.filter { repoIds.contains($0.id) }.map { r in
            "\(r.id)|\(r.name)|\(r.path)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are the Cadence draft enrichment agent. Given ONE ticket draft + one or more tagged repos,
        explore the repo with native tools (Read, Grep, Glob, Bash(git *)) to enrich it into a rich draft.

        Rules:
        - Only reference files you actually read. No fabrication.
        - Return JSON ONLY (no prose, no fences), shape:
          {"draft":{"id":"...","title":"...","description":"...","priority":"P0-P4","estimate":N,"labels":[]}}
        - description MUST be markdown with sections: ## Purpose\\n## Approach\\n## Verification\\n## Notes
        """

        let userTurn = """
        DRAFT:
        id: \(draft.id)
        title: \(draft.title)
        current_description: \(draft.description)

        REPOS TO CONSIDER:
        \(repoBlock)
        """

        do {
            let obj = try await claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: { [weak self] name in
                    guard let self else { return }
                    await MainActor.run { self.agentToolCalled(name) }
                },
                addDirs: repoPaths(for: repoIds),
                timeout: 240
            )
            guard let dict = obj as? [String: Any] else { return }
            var updated = draft
            if let d = dict["draft"] as? [String: Any] {
                if let s = d["description"] as? String { updated.description = s }
                if let s = d["title"] as? String { updated.title = s }
                if let ps = d["priority"] as? String, let p = Priority(rawValue: ps) { updated.priority = p }
                if let e = d["estimate"] as? Double { updated.estimate = e }
                else if let e = d["estimate"] as? Int { updated.estimate = Double(e) }
                if let l = d["labels"] as? [String] { updated.labels = l }
            }
            updated.attachedRepoIds = repoIds
            if let idx = pendingDrafts.firstIndex(where: { $0.id == draft.id }) {
                pendingDrafts[idx] = updated
            }
        } catch {
            addAmbient(AmbientEvent(kind: .error, text: "Enrich \(draft.id) failed: \(error.localizedDescription)", at: Date(), target: nil))
        }
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
        lastRefresh = Date()
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

    /// Digest is not available in the file-based build yet.
    func generateDigestDraft() async {
        persistDigest("Daily digest — coming soon.")
        showDigestPreview = true
    }

    func copyDigestNow() async {
        if digestDraft.isEmpty { await generateDigestDraft() }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(digestDraft, forType: .string)
        Notifier.post(title: "Digest copied", body: "Paste into Slack.")
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
