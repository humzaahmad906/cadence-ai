import SwiftUI

/// Compose / reorder / edit the blocks of a single workflow.
struct WorkflowBuilderView: View {
    @EnvironmentObject var appState: AppState
    let workflowId: String

    @State private var draft: Workflow?
    @State private var loaded = false
    @State private var showStartInput = false

    var body: some View {
        Group {
            if let _ = draft {
                editor
            } else {
                notFound
            }
        }
        .sheet(isPresented: $showStartInput) {
            WorkflowStartInputSheet(workflowName: draft?.name ?? "workflow") { input in
                Task { await appState.runWorkflow(workflowId, initialInput: input) }
            }
        }
        .onAppear {
            if !loaded {
                draft = appState.workflows.first(where: { $0.id == workflowId }) ?? appState.workflowStore.load(workflowId)
                loaded = true
            }
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header
                metaCard
                repoPicker
                blocksSection
                addBlockRow
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    private var header: some View {
        HStack {
            Button { appState.setArtifact(.workflows) } label: {
                Label("Workflows", systemImage: "arrow.left")
            }.buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(SecondaryButtonStyle())
            Button { save(); startRun() } label: {
                Label("Save & run", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((draft?.blocks.isEmpty ?? true) || appState.agentRunning)
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

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: DS.space3) {
            Text("Blocks").font(DS.Font.title)
            if let d = draft, d.blocks.isEmpty {
                Card {
                    Text("No blocks yet. Add one below.").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                }
            }
            ForEach(Array((draft?.blocks ?? []).enumerated()), id: \.element.id) { idx, _ in
                BlockEditor(
                    block: blockBinding(idx),
                    index: idx,
                    count: draft?.blocks.count ?? 0,
                    onMoveUp: { move(idx, by: -1) },
                    onMoveDown: { move(idx, by: 1) },
                    onDelete: { removeBlock(idx) }
                )
            }
        }
    }

    private var addBlockRow: some View {
        Menu {
            ForEach(WorkflowBlockKind.allCases) { kind in
                Button {
                    addBlock(kind)
                } label: {
                    Label(kind.label, systemImage: kind.icon)
                }
            }
        } label: {
            Label("Add block", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).stroke(DS.border, lineWidth: 1))
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
            get: {
                guard let d = draft, idx >= 0, idx < d.blocks.count else {
                    return WorkflowBlock(kind: .agentPrompt, title: "")
                }
                return d.blocks[idx]
            },
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
        draft!.blocks.append(WorkflowBlock(kind: kind, title: kind.label))
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

    /// Prompt for a starting input first when the first block consumes it; otherwise run directly.
    private func startRun() {
        if draft?.firstBlockConsumesInput ?? false {
            showStartInput = true
        } else {
            Task { await appState.runWorkflow(workflowId) }
        }
    }
}

// MARK: - Block editor

private struct BlockEditor: View {
    @Binding var block: WorkflowBlock
    let index: Int
    let count: Int
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

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
            }
        }
    }

    @ViewBuilder
    private var config: some View {
        switch block.kind {
        case .agentPrompt:
            labeledEditor("System prompt", text: $block.config.systemPrompt, minHeight: 90)
            labeledEditor("Prompt template · {{input}}, {{repos}}", text: $block.config.promptTemplate, minHeight: 70)
            Toggle("Agent returns structured JSON (feed to Create tickets)", isOn: $block.config.expectJSON)
                .font(DS.Font.caption)
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
        case .createDescription:
            Text("Runs the wizard's description writer on the incoming task title, scoped to this workflow's repos. Its output feeds Create solution.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
        case .createSolution:
            Text("Runs the wizard's solution designer on the incoming description, appending a Solution section.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
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
        case .repoReport:
            labeledField("Since (git ref or window, optional)", text: $block.config.sinceRef)
            Text("Summarizes recent activity across this workflow's repos using git log/show/diff/blame.")
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
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
