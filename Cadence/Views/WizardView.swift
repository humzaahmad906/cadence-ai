import SwiftUI

/// Multi-step per-task wizard. Two phases per task: description → solution.
/// Each phase has edit + regenerate + advance. Chat-panel feel.
struct WizardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let w = appState.wizard, let draft = appState.wizardCurrentDraft {
            body(for: w, draft: draft)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.rays").font(.system(size: 36)).foregroundStyle(DS.textTertiary)
            Text("No wizard session").font(DS.Font.headline).foregroundStyle(DS.textSecondary)
            Button { appState.setArtifact(.kickoff) } label: {
                Label("Start a sprint", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func body(for w: WizardSession, draft: TicketDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header(w: w, draft: draft)
                progress(w: w)

                // Panel 1: Description
                descriptionPanel(w: w, draft: draft)

                // Panel 2: Solution (visible once description exists / after continue)
                if w.phase == .solution || !draft.solution.isEmpty {
                    solutionPanel(w: w, draft: draft)
                }

                footer(w: w, draft: draft)
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    // MARK: header

    private func header(w: WizardSession, draft: TicketDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Task \(w.index + 1) of \(w.drafts.count)")
                    .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                Text("·").foregroundStyle(DS.textTertiary)
                Text(w.sprintName).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                Spacer()
                Button { Task { await appState.wizardSkipCurrent() } } label: {
                    Label("Skip", systemImage: "forward.end")
                }.buttonStyle(SecondaryButtonStyle())
                Button { appState.wizardCancel() } label: {
                    Label("Cancel", systemImage: "xmark")
                }.buttonStyle(SecondaryButtonStyle())
            }
            VStack(alignment: .leading, spacing: 3) {
                TextField("Task headline", text: Binding(
                    get: { draft.title },
                    set: { newValue in appState.updateWizardDraft { $0.title = newValue } }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.Font.displayL)
                .lineLimit(1...3)
                Text("Edit the headline, then Regenerate below to redraft the description from it.")
                    .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            }
            HStack(spacing: 6) {
                ForEach(w.repoIds, id: \.self) { rid in
                    if let r = appState.repos.first(where: { $0.id == rid }) {
                        branchChip(repo: r, w: w)
                    }
                }
            }
        }
    }

    private func progress(w: WizardSession) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<w.drafts.count, id: \.self) { i in
                Capsule()
                    .fill(i < w.index ? DS.ok : (i == w.index ? DS.accent : DS.borderSoft))
                    .frame(height: 4)
            }
        }
    }

    // MARK: description panel

    private func descriptionPanel(w: WizardSession, draft: TicketDraft) -> some View {
        AgentPanel(
            icon: "text.alignleft",
            tint: DS.accent,
            title: "Description",
            subtitle: agentSubtitle(phase: .description, w: w),
            running: appState.agentRunning && w.phase == .description,
            currentTool: appState.agentCurrentTool
        ) {
            if draft.description.isEmpty && appState.agentRunning {
                Text("Reading your repos and drafting…").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    .padding(.vertical, DS.space3)
            } else {
                TextEditor(text: Binding(
                    get: { draft.description },
                    set: { new in appState.updateWizardDraft { $0.description = new } }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .background(DS.insetBG)
                .frame(minHeight: 200)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.borderSoft, lineWidth: 1))
            }

            HStack {
                Button { Task { await appState.generateDescriptionForCurrent() } } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }.buttonStyle(SecondaryButtonStyle())
                .disabled(appState.agentRunning)
                Spacer()
                if w.phase == .description {
                    Button {
                        Task { await appState.wizardContinueToSolution() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Continue to solution")
                            Image(systemName: "arrow.down")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.description.isEmpty || appState.agentRunning)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    // MARK: solution panel

    private func solutionPanel(w: WizardSession, draft: TicketDraft) -> some View {
        AgentPanel(
            icon: "wand.and.stars",
            tint: DS.purple,
            title: "Solution",
            subtitle: agentSubtitle(phase: .solution, w: w),
            running: appState.agentRunning && w.phase == .solution,
            currentTool: appState.agentCurrentTool
        ) {
            if draft.solution.isEmpty && appState.agentRunning {
                Text("Reading files, planning the change…").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    .padding(.vertical, DS.space3)
            } else {
                TextEditor(text: Binding(
                    get: { draft.solution },
                    set: { new in appState.updateWizardDraft { $0.solution = new } }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .background(DS.insetBG)
                .frame(minHeight: 220)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.borderSoft, lineWidth: 1))
            }

            HStack {
                Button { appState.wizardBackToDescription() } label: {
                    Label("Back to description", systemImage: "arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button { Task { await appState.generateSolutionForCurrent() } } label: {
                    Label("Regenerate solution", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.agentRunning)
                Spacer()
                Button {
                    Task { await appState.wizardCommitAndAdvance() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text(w.index + 1 == w.drafts.count ? "Create & finish" : "Create & next task")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft.solution.isEmpty || appState.agentRunning)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    // MARK: footer

    private func footer(w: WizardSession, draft: TicketDraft) -> some View {
        HStack {
            HStack(spacing: 4) {
                Text("Ticket ID:").font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                Text(draft.id).font(DS.Font.mono).foregroundStyle(DS.textSecondary)
            }
            Spacer()
            HStack {
                Picker("Priority", selection: Binding(
                    get: { draft.priority },
                    set: { p in appState.updateWizardDraft { $0.priority = p } }
                )) {
                    ForEach(Priority.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 150)
                HStack(spacing: 4) {
                    Text("Est").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                    TextField("h", value: Binding(
                        get: { draft.estimate },
                        set: { e in appState.updateWizardDraft { $0.estimate = e } }
                    ), format: .number).frame(width: 50)
                }
            }
        }
        .padding(.top, DS.space2)
    }

    private func branchChip(repo: RepoNode, w: WizardSession) -> some View {
        let branch = w.branch(forRepo: repo.id, taskIdx: w.index)
        let catalog = appState.branchCatalog[repo.id] ?? BranchCatalog()
        return Menu {
            if catalog.branches.isEmpty {
                Button("Load branches") {
                    Task { await appState.loadBranches(for: repo.id) }
                }
            } else {
                ForEach(catalog.branches, id: \.self) { b in
                    Button(b) {
                        appState.setWizardTaskBranch(taskIdx: w.index, repoId: repo.id, branch: b)
                    }
                }
                Divider()
                Button("Regenerate description with new branch") {
                    Task { await appState.generateDescriptionForCurrent() }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.caption2).foregroundStyle(DS.warn)
                Text(repo.name).font(DS.Font.micro)
                Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(DS.textTertiary)
                Text(branch.isEmpty ? "(default)" : branch).font(DS.Font.mono).foregroundStyle(DS.textPrimary)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(DS.subtleFill))
        }
        .menuStyle(.borderlessButton)
        .onAppear {
            if catalog.branches.isEmpty {
                Task { await appState.loadBranches(for: repo.id) }
            }
        }
    }

    private func agentSubtitle(phase: WizardSession.Phase, w: WizardSession) -> String {
        if appState.agentRunning && w.phase == phase {
            let tool = appState.agentCurrentTool ?? "thinking"
            return "Agent: \(tool) · \(appState.agentToolCount) call\(appState.agentToolCount == 1 ? "" : "s")"
        }
        return "Editable. Regenerate anytime."
    }
}

/// Chat-panel-style container for an agent-authored artifact + controls.
private struct AgentPanel<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let running: Bool
    let currentTool: String?
    @ViewBuilder let content: Content

    var body: some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space3) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15))
                    Text(title).font(DS.Font.title)
                    if running {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Text(subtitle).font(DS.Font.micro).foregroundStyle(DS.textSecondary)
                }
                content
            }
        }
    }
}
