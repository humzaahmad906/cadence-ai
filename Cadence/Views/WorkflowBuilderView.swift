import SwiftUI

/// Compose / reorder / edit the blocks of a single workflow.
struct WorkflowBuilderView: View {
    @EnvironmentObject var appState: AppState
    let workflowId: String

    @State private var draft: Workflow?
    @State private var loaded = false
    @State private var selectedBlockId: UUID?
    @State private var mode: Mode = .build
    @State private var aiOpen = false
    @State private var reviewText = ""

    enum Mode { case build, debug }

    var body: some View {
        Group {
            if draft != nil { editor } else { notFound }
        }
        .onAppear(perform: load)
        .overlay {
            if aiOpen { AIBuilderView(onClose: { aiOpen = false }) }
        }
    }

    private func load() {
        guard !loaded else { return }
        var d = appState.workflows.first(where: { $0.id == workflowId }) ?? appState.workflowStore.load(workflowId)
        if d != nil, d!.edges.isEmpty, d!.blocks.count > 1 {   // migrate un-wired → linear chain
            for i in 0..<(d!.blocks.count - 1) {
                d!.edges.append(WorkflowEdge(from: d!.blocks[i].id, to: d!.blocks[i + 1].id))
            }
        }
        draft = d
        loaded = true
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 30)).foregroundStyle(DS.textTertiary)
            Text("Workflow not found").foregroundStyle(DS.textSecondary)
            Button { appState.setArtifact(.workflows) } label: {
                Label("Back to workflows", systemImage: "flowchart")
            }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                leftRail
                    .frame(width: 250)
                    .background(DS.sidebarBG)
                    .overlay(Rectangle().fill(DS.border).frame(width: 1), alignment: .trailing)
                WorkflowCanvasView(workflow: draftBinding, selectedBlockId: $selectedBlockId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightPanel
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .background(DS.cardBG)
                    .overlay(Rectangle().fill(DS.border).frame(width: 1), alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.contentBG)
    }

    private var draftBinding: Binding<Workflow> {
        Binding(get: { draft ?? Workflow(name: "") }, set: { draft = $0 })
    }

    private var selectedIndex: Int? {
        guard let id = selectedBlockId else { return nil }
        return draft?.blocks.firstIndex(where: { $0.id == id })
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: DS.space3) {
            Button { save(); appState.setArtifact(.workflows) } label: {
                Label("Workflows", systemImage: "arrow.left")
            }.buttonStyle(SecondaryButtonStyle())
            if let name = draft?.name, !name.isEmpty { Chip(name, tint: DS.accent, filled: false) }
            Spacer()
            Picker("", selection: $mode) {
                Text("Build").tag(Mode.build)
                Text("Debug").tag(Mode.debug)
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()
            Spacer()
            if mode == .build {
                Button { aiOpen = true } label: { Label("AI builder", systemImage: "sparkles") }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button { appState.activeRun = nil } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button {
                save()
                Task { await appState.runWorkflow(workflowId, navigate: false); mode = .debug }
            } label: { Label("Run", systemImage: "play.fill") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((draft?.blocks.isEmpty ?? true) || appState.agentRunning)
        }
        .padding(DS.space3)
        .background(DS.cardBG)
        .overlay(Rectangle().fill(DS.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: left rail (workflows + block palette)

    private var leftRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                VStack(alignment: .leading, spacing: DS.space2) {
                    Text("WORKFLOWS").font(DS.Font.micro.weight(.bold)).tracking(0.6).foregroundStyle(DS.textTertiary)
                    ForEach(appState.workflows) { wf in
                        Button { save(); appState.setArtifact(.workflowBuilder(id: wf.id)) } label: {
                            HStack(spacing: 8) {
                                StatusDot(tint: wf.id == workflowId ? DS.accent : DS.textTertiary)
                                Text(wf.name).font(DS.Font.body)
                                    .foregroundStyle(wf.id == workflowId ? DS.accent : DS.textPrimary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: DS.radius).fill(wf.id == workflowId ? DS.accentSoft : Color.clear))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Divider().overlay(DS.borderSoft)
                BlockPaletteView(onAdd: { addBlock($0) })
            }
            .padding(DS.space3)
        }
    }

    // MARK: right panel (inspector in Build, debugger in Debug)

    @ViewBuilder
    private var rightPanel: some View {
        if mode == .debug {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space3) {
                    DebugPanelView()
                    reviewControls
                }
                .padding(DS.space3)
            }
        } else {
            ScrollView { buildInspector.padding(DS.space4) }
        }
    }

    @ViewBuilder
    private var buildInspector: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let idx = selectedIndex {
                HStack {
                    Text("Block").font(DS.Font.title)
                    Spacer()
                    Button { selectedBlockId = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).foregroundStyle(DS.textTertiary)
                }
                BlockEditor(
                    block: blockBinding(idx),
                    index: idx,
                    count: draft?.blocks.count ?? 0,
                    workflow: draft ?? Workflow(name: ""),
                    debugMode: true,
                    onMoveUp: { move(idx, by: -1) },
                    onMoveDown: { move(idx, by: 1) },
                    onDelete: { removeBlock(idx); selectedBlockId = nil }
                )
            } else {
                Text("Build your workflow").font(DS.Font.title)
                Text("Add blocks from the palette, then drag a node's output port to another node's input to connect them. Click a node to configure it. Switch to Debug to run it.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
                metaCard
                repoPicker
            }
        }
    }

    /// Approve / reject controls shown in Debug mode when the run pauses on a review block.
    @ViewBuilder
    private var reviewControls: some View {
        if let run = appState.activeRun, run.status == .awaitingReview, run.currentIndex < run.blocks.count {
            VStack(alignment: .leading, spacing: DS.space2) {
                Text("Review — edit if needed, then approve to continue.")
                    .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                TextEditor(text: $reviewText)
                    .font(DS.Font.mono).scrollContentBackground(.hidden)
                    .frame(minHeight: 120).padding(8)
                    .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                    .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.border, lineWidth: 1))
                HStack {
                    Button(role: .destructive) { Task { await appState.resumeReview(approve: false, editedOutput: nil) } } label: {
                        Label("Reject", systemImage: "xmark")
                    }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button { Task { await appState.resumeReview(approve: true, editedOutput: reviewText) } } label: {
                        Label("Approve & continue", systemImage: "checkmark")
                    }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .onAppear { reviewText = run.blocks[run.currentIndex].output }
        }
    }

    private var metaCard: some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                    TextField("Workflow name", text: bind(\.name))
                        .textFieldStyle(.plain).font(DS.Font.headline)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                    TextField("What this workflow does", text: bind(\.summary))
                        .textFieldStyle(.plain).font(DS.Font.body)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                }
            }
        }
    }

    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scoped repos").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            if appState.repos.isEmpty {
                Text("No repos indexed. Index one from Start to give agent blocks repo access.")
                    .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.repos) { r in
                        repoChip(r)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func repoChip(_ r: RepoNode) -> some View {
        let selected = draft?.repoIds.contains(r.id) ?? false
        Button { toggleRepo(r.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "folder")
                    .foregroundStyle(selected ? DS.accent : DS.textTertiary).font(.callout)
                Text(r.name).font(DS.Font.body)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(selected ? DS.accentSoft : DS.cardBG))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .stroke(selected ? DS.accent.opacity(0.4) : DS.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: mutation

    private func bind(_ keyPath: WritableKeyPath<Workflow, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { if draft != nil { draft![keyPath: keyPath] = $0 } }
        )
    }

    private func blockBinding(_ idx: Int) -> Binding<WorkflowBlock> {
        Binding(
            get: { draft?.blocks[idx] ?? WorkflowBlock(kind: .agentPrompt, title: "") },
            set: { if draft != nil, idx < draft!.blocks.count { draft!.blocks[idx] = $0 } }
        )
    }

    private func toggleRepo(_ id: String) {
        guard draft != nil else { return }
        if let i = draft!.repoIds.firstIndex(of: id) { draft!.repoIds.remove(at: i) }
        else { draft!.repoIds.append(id) }
    }

    private func addBlock(_ kind: WorkflowBlockKind) {
        guard draft != nil else { return }
        let block = WorkflowBlock(kind: kind, title: kind.label)
        draft!.blocks.append(block)
        selectedBlockId = block.id
    }

    private func removeBlock(_ idx: Int) {
        guard draft != nil, idx < draft!.blocks.count else { return }
        draft!.blocks.remove(at: idx)
    }

    private func move(_ idx: Int, by offset: Int) {
        guard draft != nil else { return }
        let target = idx + offset
        guard idx >= 0, target >= 0, idx < draft!.blocks.count, target < draft!.blocks.count else { return }
        draft!.blocks.swapAt(idx, target)
    }

    private func save() {
        guard let d = draft else { return }
        appState.saveWorkflow(d)
    }
}

// MARK: - Block editor

private struct BlockEditor: View {
    @EnvironmentObject var appState: AppState
    @Binding var block: WorkflowBlock
    let index: Int
    let count: Int
    let workflow: Workflow
    let debugMode: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var validateMsg = ""
    @State private var thinking = false
    @State private var debugInput = ""

    var body: some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space3) {
                HStack(spacing: DS.space2) {
                    Image(systemName: block.kind.icon).foregroundStyle(DS.accent)
                    Text("\(index + 1).").font(DS.Font.headline).foregroundStyle(DS.textTertiary)
                    TextField("Block title", text: $block.title)
                        .textFieldStyle(.plain).font(DS.Font.headline)
                    Spacer()
                    Chip(block.kind.label, tint: DS.purple, filled: false)
                    Button(action: onMoveUp) { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless).disabled(index == 0).foregroundStyle(DS.textTertiary)
                    Button(action: onMoveDown) { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless).disabled(index == count - 1).foregroundStyle(DS.textTertiary)
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(DS.textTertiary)
                }
                Text(block.kind.blurb).font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                Divider().overlay(DS.borderSoft)
                config
                portsEditor
                if debugMode { debugSection }
            }
        }
    }

    @ViewBuilder
    private var portsEditor: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DS.space2) {
                portList(title: "Inputs", ports: $block.config.inputPorts, defaultName: "input")
                portList(title: "Outputs", ports: $block.config.outputPorts, defaultName: "output")
                Text("Wire edges on the canvas between ports. Agent prompts read each input as {{name}}; multiple outputs = the block emits JSON keyed by these names.")
                    .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            }
            .padding(.top, 4)
        } label: {
            Label("Ports", systemImage: "point.3.connected.trianglepath.dotted").font(DS.Font.caption)
        }
    }

    private func portList(title: String, ports: Binding<[String]>, defaultName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            if ports.wrappedValue.isEmpty {
                Text("1 default port (\(defaultName))").font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            }
            ForEach(ports.wrappedValue.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    TextField("port name", text: Binding(
                        get: { i < ports.wrappedValue.count ? ports.wrappedValue[i] : "" },
                        set: { if i < ports.wrappedValue.count { ports.wrappedValue[i] = $0 } }
                    ))
                    .textFieldStyle(.plain).font(DS.Font.body)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                    Button { if i < ports.wrappedValue.count { ports.wrappedValue.remove(at: i) } } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless).foregroundStyle(DS.textTertiary)
                }
            }
            Button { ports.wrappedValue.append("\(defaultName)\(ports.wrappedValue.count + 1)") } label: {
                Label("Add port", systemImage: "plus")
            }.buttonStyle(.borderless).font(DS.Font.caption)
        }
    }

    @ViewBuilder
    private var config: some View {
        switch block.kind {
        case .input:
            labeledEditor("Input text — becomes the first block's output", text: $block.config.inputText, minHeight: 90)
        case .agentPrompt:
            labeledEditor("System prompt", text: $block.config.systemPrompt, minHeight: 90)
            labeledEditor("Prompt template · {{input}}, {{repos}}", text: $block.config.promptTemplate, minHeight: 70)
            Toggle("Agent returns structured JSON (feed to Create tickets)", isOn: $block.config.expectJSON)
                .font(DS.Font.caption)
            agentControls
        case .createTickets:
            HStack(spacing: DS.space4) {
                labeledMenu("Default priority", selection: $block.config.defaultPriority, options: Priority.allCases.map { $0.rawValue })
                labeledMenu("Default status", selection: $block.config.defaultStatus, options: TicketStatus.allCases.map { $0.rawValue })
            }
            Text("Parses the previous block's JSON ({\"tickets\":[…]}) and saves each as a ticket.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
        case .manualReview:
            labeledField("Review instructions", text: $block.config.reviewInstructions)
        case .summarize:
            labeledField("Heading", text: $block.config.heading)
            labeledEditor("Prompt template · {{input}}", text: $block.config.promptTemplate, minHeight: 70)
            Toggle("Persist result as the daily digest", isOn: $block.config.persistAsDigest)
                .font(DS.Font.caption)
            agentControls
        case .createDescription:
            Text("Runs the wizard's description writer on the incoming task title, scoped to this workflow's repos. Its output feeds Create solution.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            agentControls
        case .createSolution:
            Text("Runs the wizard's solution designer on the incoming description, appending a Solution section.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            agentControls
        case .viewer:
            labeledMenu("Show", selection: $block.config.viewerTarget, options: ViewerTarget.allCases.map { $0.rawValue })
            if block.config.viewerTarget == ViewerTarget.ticket.rawValue {
                labeledField("Ticket ID", text: $block.config.ticketId)
            }
            if block.config.viewerTarget == ViewerTarget.doc.rawValue {
                labeledField("Document path", text: $block.config.docPath)
            }
        case .docQA:
            labeledField("Question", text: $block.config.question)
            labeledField("Document path (optional)", text: $block.config.docPath)
            Text("Answers the question about the previous block's output (a created doc) and/or the doc path, with repo access.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            agentControls
        case .repoReport:
            labeledField("Since (git ref or window, optional)", text: $block.config.sinceRef)
            Text("Summarizes recent activity across this workflow's repos using git log/show/diff/blame.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            agentControls
        case .code:
            codeConfig
        }
    }

    /// Generic per-block debug runner (all kinds except code, which has its own Run above).
    @ViewBuilder
    private var debugSection: some View {
        if block.kind != .code {
            Divider().overlay(DS.borderSoft)
            Text("Debug — run just this block").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            labeledEditor("Debug input (stands in for the previous block's output)", text: $debugInput, minHeight: 60)
            HStack(spacing: DS.space3) {
                if appState.debugRunningId == block.id {
                    Button { appState.cancelDebugRun() } label: { Label("Cancel", systemImage: "stop.fill") }
                        .buttonStyle(.borderless).foregroundStyle(DS.danger)
                    ProgressView().controlSize(.small)
                } else {
                    Button { appState.debugRunBlock(block, workflow: workflow, input: debugInput) } label: {
                        Label("Run block", systemImage: "play.fill")
                    }.buttonStyle(.borderless)
                }
                Spacer()
            }
            if let out = appState.debugOutput[block.id], !out.isEmpty {
                ScrollView {
                    OutputContent(text: out, prose: block.kind != .createTickets)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .padding(DS.space2)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
            }
        }
    }

    /// Model / effort / repo-access controls shown on every agent-backed block.
    @ViewBuilder
    private var agentControls: some View {
        HStack(alignment: .top, spacing: DS.space4) {
            choiceMenu("Model", $block.config.model,
                       [("", "Default"), ("opus", "opus"), ("sonnet", "sonnet"), ("haiku", "haiku")])
            choiceMenu("Effort (research depth)", $block.config.effort,
                       [("", "Default"), ("low", "low"), ("medium", "medium"), ("high", "high"), ("max", "max")])
        }
        Toggle("Give this block access to the workflow's repos", isOn: $block.config.useRepos)
            .font(DS.Font.caption)
    }

    /// A menu whose stored value differs from its display label (so "" shows as "Default").
    @ViewBuilder
    private func choiceMenu(_ label: String, _ selection: Binding<String>, _ choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            Menu {
                ForEach(choices, id: \.0) { value, name in
                    Button(name) { selection.wrappedValue = value }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(choices.first(where: { $0.0 == selection.wrappedValue })?.1 ?? "Default")
                        .font(DS.Font.body).foregroundStyle(DS.textPrimary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { block.config.code },
            set: { block.config.code = $0; block.config.validated = false }  // edits invalidate the check
        )
    }

    @ViewBuilder
    private var codeConfig: some View {
        HStack(alignment: .top, spacing: DS.space4) {
            labeledField("Input (stdin)", text: $block.config.inputDesc)
            labeledField("Output (stdout)", text: $block.config.outputDesc)
        }
        labeledField("Interpreter", text: $block.config.interpreter)
        labeledField("What it should do (for Generate)", text: $block.config.codeIntent)
        labeledEditor("Python · reads stdin, writes stdout", text: codeBinding, minHeight: 140)

        HStack(spacing: DS.space3) {
            Button {
                Task {
                    thinking = true
                    let code = await appState.generateCode(for: block)
                    thinking = false
                    if !code.isEmpty { block.config.code = code; block.config.validated = false; validateMsg = "" }
                }
            } label: { Label("Generate", systemImage: "sparkles") }
                .buttonStyle(.borderless).disabled(thinking)

            Button {
                Task {
                    thinking = true
                    let r = await appState.validateCode(block)
                    thinking = false
                    block.config.validated = r.ok
                    validateMsg = r.message
                }
            } label: { Label("Validate", systemImage: "checkmark.seal") }
                .buttonStyle(.borderless).disabled(block.config.code.isEmpty || thinking)

            if appState.debugRunningId == block.id {
                Button { appState.cancelDebugRun() } label: { Label("Cancel", systemImage: "stop.fill") }
                    .buttonStyle(.borderless).foregroundStyle(DS.danger)
            } else {
                Button { appState.debugRunBlock(block, workflow: workflow, input: block.config.sampleInput) } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.borderless).disabled(block.config.code.isEmpty)
            }

            if thinking { ProgressView().controlSize(.small) }
            Spacer()
            if block.config.validated {
                Label("validated", systemImage: "checkmark.seal.fill")
                    .font(DS.Font.micro).foregroundStyle(DS.ok)
            }
        }

        if !validateMsg.isEmpty {
            Text(validateMsg).font(DS.Font.micro)
                .foregroundStyle(block.config.validated ? DS.textSecondary : DS.warn)
        }

        labeledField("Sample stdin (for Run)", text: $block.config.sampleInput)

        if let out = appState.debugOutput[block.id], !out.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run output").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                ScrollView {
                    OutputContent(text: out, prose: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .padding(DS.space2)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            TextField(label, text: text)
                .textFieldStyle(.plain).font(DS.Font.body)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
        }
    }

    private func labeledEditor(_ label: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            TextEditor(text: text)
                .font(DS.Font.mono)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.border, lineWidth: 1))
        }
    }

    private func labeledMenu(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection.wrappedValue = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue).font(DS.Font.body).foregroundStyle(DS.textPrimary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
