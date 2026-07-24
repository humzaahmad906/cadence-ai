import Foundation

/// Pluggable block execution. Each `WorkflowBlockKind` is backed by a `WorkflowBlockHandler`
/// resolved through `WorkflowBlockRegistry`. Adding a new block kind is a small, localized change:
///   1. add a case to `WorkflowBlockKind` (Models/Workflow.swift),
///   2. add a handler type + one line in `WorkflowBlockRegistry` (this file),
///   3. add a config editor case in `WorkflowBuilderView`.
/// The engine (`WorkflowRunner`) never switches over kinds — it just asks the registry for a handler.

/// Everything a handler needs at run time.
@MainActor
struct BlockRunContext {
    let appState: AppState
    let workflow: Workflow
    /// Output of the previous block (empty for the first block).
    let input: String
}

/// One block kind's behaviour.
@MainActor
protocol WorkflowBlockHandler {
    /// When true, the runner marks the block `awaitingReview` after `run` produces its output and
    /// waits for the user (manualReview). Most handlers run straight through.
    var awaitsUserAfterRun: Bool { get }
    /// Execute the block and return the output carried into the next block.
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String
}

extension WorkflowBlockHandler {
    var awaitsUserAfterRun: Bool { false }
}

/// The single point of block-kind → handler dispatch.
@MainActor
enum WorkflowBlockRegistry {
    static func handler(for kind: WorkflowBlockKind) -> WorkflowBlockHandler {
        switch kind {
        case .input:             return InputBlockHandler()
        case .agentPrompt:       return AgentPromptHandler()
        case .createTickets:     return CreateTicketsHandler()
        case .manualReview:      return ManualReviewHandler()
        case .summarize:         return SummarizeHandler()
        case .createDescription: return CreateDescriptionHandler()
        case .createSolution:    return CreateSolutionHandler()
        case .viewer:            return ViewerHandler()
        case .docQA:             return DocQAHandler()
        case .repoReport:        return RepoReportHandler()
        case .code:              return CodeBlockHandler()
        }
    }
}

// MARK: - Shared agent plumbing

/// The generic agent invocation shared by `agentPrompt` and its presets (`docQA`, `repoReport`).
/// This makes the "generic agent block + named presets" relationship explicit.
@MainActor
enum AgentBlockKit {
    /// Run the Claude agent with `--add-dir` scoping over the workflow's repos + the issues folder
    /// (+ any `extraDirs`). When `expectJSON` is false, the agent is asked for a {"output": "..."}
    /// envelope and only the string is returned; when true, the raw JSON is returned verbatim.
    static func runAgent(_ context: BlockRunContext,
                         systemPrompt: String,
                         userMessage: String,
                         expectJSON: Bool,
                         repoIds: [String],
                         model: String = "",
                         effort: String = "",
                         extraDirs: [String] = []) async throws -> String {
        let appState = context.appState
        appState.agentStart()
        defer { appState.agentStop() }

        let sys = expectJSON
            ? systemPrompt
            : systemPrompt + "\n\nReturn JSON ONLY, no prose, no code fences: {\"output\": \"<your markdown result>\"}"

        var dirs = appState.repoPaths(for: repoIds)
        dirs.append(CadencePaths.issuesDir.path)
        dirs.append(contentsOf: extraDirs.filter { !$0.isEmpty })

        let obj = try await appState.claude.promptAgentJSONStreaming(
            userMessage: userMessage,
            systemPrompt: sys,
            onToolUse: { [appState] name in await appState.agentToolCalled(name) },
            addDirs: dirs,
            model: model,
            effort: effort,
            timeout: 360
        )

        if expectJSON { return stringify(obj) }
        if let dict = obj as? [String: Any], let out = dict["output"] as? String { return out }
        return stringify(obj)
    }

    static func fill(_ template: String, input: String, repoBlock: String) -> String {
        template
            .replacingOccurrences(of: "{{input}}", with: input)
            .replacingOccurrences(of: "{{repos}}", with: repoBlock.isEmpty ? "(none)" : repoBlock)
    }

    static func repoDescription(_ appState: AppState, repoIds: [String]) -> String {
        appState.repos.filter { repoIds.contains($0.id) }
            .map { "\($0.id)|\($0.name)|\($0.path)" }
            .joined(separator: "\n")
    }

    /// Render an arbitrary JSON value back to a pretty string for downstream blocks / display.
    static func stringify(_ obj: Any) -> String {
        if let s = obj as? String { return s }
        if JSONSerialization.isValidJSONObject(obj),
           let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(obj)"
    }

    /// The first non-empty line, stripped of a leading markdown heading marker.
    static func firstLine(_ text: String) -> String {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            return line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Generic handlers

/// Seeds the pipeline: emits its configured text verbatim, ignoring any incoming input.
struct InputBlockHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        block.config.inputText
    }
}

struct AgentPromptHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let repoIds = block.config.useRepos ? context.workflow.repoIds : []
        let repoBlock = AgentBlockKit.repoDescription(context.appState, repoIds: repoIds)
        let userMessage = AgentBlockKit.fill(block.config.promptTemplate, input: context.input, repoBlock: repoBlock)
        return try await AgentBlockKit.runAgent(context,
                                                systemPrompt: block.config.systemPrompt,
                                                userMessage: userMessage,
                                                expectJSON: block.config.expectJSON,
                                                repoIds: repoIds,
                                                model: block.config.model,
                                                effort: block.config.effort)
    }
}

struct SummarizeHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let appState = context.appState
        appState.agentStart()
        defer { appState.agentStop() }

        let heading = block.config.heading.isEmpty ? "Summary" : block.config.heading
        let template = block.config.promptTemplate.isEmpty
            ? "Summarize the following into a concise markdown summary using short bullet points:\n\n{{input}}"
            : block.config.promptTemplate
        let promptText = AgentBlockKit.fill(template, input: context.input, repoBlock: "")

        let raw = try await appState.claude.prompt(promptText, model: block.config.model, effort: block.config.effort, timeout: 180)
        let result = "# \(heading)\n\n\(raw.trimmingCharacters(in: .whitespacesAndNewlines))"
        if block.config.persistAsDigest { appState.persistDigest(result) }
        return result
    }
}

struct ManualReviewHandler: WorkflowBlockHandler {
    var awaitsUserAfterRun: Bool { true }
    /// Pass the incoming payload straight through — the run pauses so the user can edit it.
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        context.input
    }
}

struct CreateTicketsHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let appState = context.appState
        let items = try Self.parseTicketItems(from: context.input)
        guard !items.isEmpty else { return "No tickets found in the previous block's output." }

        let numbering = Self.ticketNumbering(appState)
        let prefix = numbering.prefix
        var nextN = numbering.next
        var created: [String] = []
        var failures: [String] = []

        for item in items {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { continue }
            let id = "\(prefix)-\(nextN)"
            nextN += 1

            let action = AgentAction.addTicket(
                id: id,
                title: title,
                priority: (item["priority"] as? String) ?? block.config.defaultPriority,
                status: (item["status"] as? String) ?? block.config.defaultStatus,
                estimate: (item["estimate"] as? Double) ?? Double(item["estimate"] as? Int ?? 0),
                assignee: item["assignee"] as? String ?? "",
                labels: (item["labels"] as? [String]) ?? [],
                project: item["project"] as? String,
                sprint: appState.currentSprint?.id,
                description: item["description"] as? String ?? ""
            )
            if let err = await AgentDispatcher.apply(action, appState: appState) {
                failures.append("\(id): \(err)")
            } else {
                created.append("\(id) — \(title)")
            }
        }

        await appState.refresh()

        var out = "Created \(created.count) ticket\(created.count == 1 ? "" : "s"):\n"
        out += created.map { "- \($0)" }.joined(separator: "\n")
        if !failures.isEmpty {
            out += "\n\nFailed:\n" + failures.map { "- \($0)" }.joined(separator: "\n")
        }
        return out
    }

    /// Pull an array of ticket dictionaries out of an agent's JSON output, tolerating the
    /// {"tickets":[...]}, {"tasks":[...]} and {"drafts":[...]} shapes (or a bare array).
    private static func parseTicketItems(from input: String) throws -> [[String: Any]] {
        let cleaned = ClaudeBridge.extractJSON(from: input)
        guard let data = cleaned.data(using: .utf8) else { throw ClaudeError.badJSON(input) }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if let arr = obj as? [[String: Any]] { return arr }
        if let dict = obj as? [String: Any] {
            for key in ["tickets", "tasks", "drafts"] {
                if let arr = dict[key] as? [[String: Any]] { return arr }
            }
        }
        return []
    }

    /// Prefix + next number for generated ticket IDs, matching the wizard's scheme.
    private static func ticketNumbering(_ appState: AppState) -> (prefix: String, next: Int) {
        let ids = appState.tickets.map { $0.id }
        let prefixes = ids.compactMap { id -> String? in
            let comps = id.split(separator: "-")
            return comps.count == 2 ? String(comps[0]) : nil
        }
        let prefix = Set(prefixes).count == 1 ? (prefixes.first ?? "CAD") : "CAD"
        let maxN = ids.compactMap { id -> Int? in
            let comps = id.split(separator: "-")
            guard comps.count == 2, let n = Int(comps[1]) else { return nil }
            return n
        }.max() ?? 0
        return (prefix, maxN + 1)
    }
}

// MARK: - Wizard-reuse handlers

/// Reuses `AppState.descriptionAgent` — the exact agent the wizard runs. Input is a task title
/// (the first line of the incoming payload). Output is `# <title>` + the description, so a
/// following `createSolution` block can recover both.
struct CreateDescriptionHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let title = AgentBlockKit.firstLine(context.input)
        guard !title.isEmpty else { return "No task title supplied to Create Description." }
        let result = try await context.appState.descriptionAgent(
            taskTitle: title, sprintName: context.workflow.name,
            repoIds: block.config.useRepos ? context.workflow.repoIds : [],
            model: block.config.model, effort: block.config.effort)
        let desc = result.description.isEmpty ? "_(no description produced)_" : result.description
        return "# \(title)\n\n\(desc)"
    }
}

/// Reuses `AppState.solutionAgent`. Input is the description block's output (`# title` + body);
/// output appends a `## Solution` section so the full spec flows onward.
struct CreateSolutionHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let title = AgentBlockKit.firstLine(context.input)
        let result = try await context.appState.solutionAgent(
            taskTitle: title.isEmpty ? "Task" : title,
            description: context.input,
            repoIds: block.config.useRepos ? context.workflow.repoIds : [],
            model: block.config.model, effort: block.config.effort)
        let sol = result.solution.isEmpty ? "_(no solution produced)_" : result.solution
        return "\(context.input)\n\n## Solution\n\n\(sol)"
    }
}

// MARK: - Display + inspection handlers

/// Read-only render of a target. No mutation; produces markdown the run view displays.
struct ViewerHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let appState = context.appState
        switch ViewerTarget(rawValue: block.config.viewerTarget) ?? .previousOutput {
        case .previousOutput:
            return context.input.isEmpty ? "_(nothing to display yet)_" : context.input
        case .ticket:
            let id = block.config.ticketId.trimmingCharacters(in: .whitespaces)
            if let t = appState.tickets.first(where: { $0.id == id }) ?? appState.store.load(id) {
                return AppState.linearMarkdown(for: t)
            }
            return "Ticket \(id.isEmpty ? "(none selected)" : id) not found."
        case .repoSummary:
            return Self.repoSummary(appState, repoIds: context.workflow.repoIds)
        case .doc:
            let path = block.config.docPath.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return "# \((path as NSString).lastPathComponent)\n\n\(text)"
            }
            return context.input.isEmpty ? "No document selected." : context.input
        }
    }

    private static func repoSummary(_ appState: AppState, repoIds: [String]) -> String {
        let scoped = appState.repos.filter { repoIds.contains($0.id) }
        guard !scoped.isEmpty else { return "# Repo summary\n\n_No repos scoped to this workflow._" }
        var lines = ["# Repo summary", ""]
        for r in scoped {
            let git = appState.repoRegistry.branches(repoPath: r.path)
            lines.append("## \(r.name)")
            lines.append("- Path: `\(r.path)`")
            lines.append("- Files: \(r.fileCount)")
            if !git.current.isEmpty { lines.append("- Current branch: `\(git.current)`") }
            if !git.branches.isEmpty { lines.append("- Branches: \(git.branches.map { "`\($0)`" }.joined(separator: ", "))") }
            if !r.headSha.isEmpty { lines.append("- HEAD: `\(r.headSha.prefix(12))`") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Agent preset: answer a configured question about the incoming doc + any repo docs.
struct DocQAHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let question = block.config.question.trimmingCharacters(in: .whitespaces)
        let systemPrompt = """
        You answer questions about documentation. Use the provided document/markdown and any repo files
        (Read/Grep/Glob) to answer precisely. Cite the source (file path / section). If the answer isn't in
        the material, say so plainly — do not fabricate.
        """
        let userMessage = """
        DOCUMENT / CONTEXT:
        \(context.input.isEmpty ? "(use the repo files and any doc path provided)" : context.input)

        QUESTION:
        \(question.isEmpty ? "Summarize the key points and anything a reader should know." : question)
        """
        return try await AgentBlockKit.runAgent(context,
                                                systemPrompt: systemPrompt,
                                                userMessage: userMessage,
                                                expectJSON: false,
                                                repoIds: block.config.useRepos ? context.workflow.repoIds : [],
                                                model: block.config.model,
                                                effort: block.config.effort,
                                                extraDirs: [block.config.docPath])
    }
}

/// Agent preset: summarize repo activity via git. Relies on the git Bash tools ClaudeBridge allows.
struct RepoReportHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let since = block.config.sinceRef.isEmpty ? "the last 2 weeks" : block.config.sinceRef
        let repoIds = block.config.useRepos ? context.workflow.repoIds : []
        let repoBlock = AgentBlockKit.repoDescription(context.appState, repoIds: repoIds)
        let systemPrompt = """
        You are the Cadence repo reporter. Use Bash(git log:*), Bash(git show:*), Bash(git diff:*),
        Bash(git blame:*) plus Read/Grep/Glob to summarize development activity in the scoped repos:
        recent commits, active branches, notable churn (files changed a lot), and what changed since
        \(since). Ground every claim in real git output — do not invent commits or authors.

        Produce a skimmable markdown report with sections:
        ## Recent commits
        ## Active branches
        ## Churn
        ## Highlights
        """
        let userMessage = """
        Report window: since \(since).

        REPOS:
        \(repoBlock.isEmpty ? "(none scoped — report that no repos are attached)" : repoBlock)
        """
        return try await AgentBlockKit.runAgent(context,
                                                systemPrompt: systemPrompt,
                                                userMessage: userMessage,
                                                expectJSON: false,
                                                repoIds: repoIds,
                                                model: block.config.model,
                                                effort: block.config.effort)
    }
}

// MARK: - Code handler

/// Runs the block's script (Python by default). The previous block's output is piped to stdin;
/// the script's stdout becomes this block's output. A non-zero exit fails the block, surfacing
/// stderr. The working directory is the first scoped repo, so scripts can read repo files.
struct CodeBlockHandler: WorkflowBlockHandler {
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String {
        let cwd = context.appState.repoPaths(for: context.workflow.repoIds).first
        let result = try await CodeRunner.shared.run(
            interpreter: block.config.interpreter,
            code: block.config.code,
            stdin: context.input,
            workingDirectory: cwd,
            timeout: 300
        )
        if result.exitCode != 0 {
            throw CodeRunError.nonZero(exit: result.exitCode, stderr: result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .newlines)
    }
}
