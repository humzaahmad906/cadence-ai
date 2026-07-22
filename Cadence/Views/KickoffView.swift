import SwiftUI

/// Step 1 of the wizard flow. User provides sprint name, picks repos, lists task titles.
/// Submit → agent generates description for task 1 → canvas advances to .wizard.
struct KickoffView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speech = SpeechRecognizer()

    @State private var sprintName: String = ""
    @State private var selectedRepos: Set<String> = []
    @State private var branchPerRepo: [String: String] = [:]  // repoId -> selected branch
    @State private var sprintDescription: String = ""
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space6) {
                headline
                sprintField
                repoPicker
                tasksField
                submitRow
                if !appState.tickets.isEmpty || !appState.repos.isEmpty {
                    Divider().overlay(DS.borderSoft).padding(.top, DS.space3)
                    summaryRow
                }
            }
            .padding(DS.space6)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
        .onChange(of: speech.transcript) { _, new in
            if !new.isEmpty { sprintDescription = sprintDescription.isEmpty ? new : sprintDescription + " " + new }
        }
        .onAppear {
            Task { await speech.requestAuth() }
            if sprintName.isEmpty, let s = appState.currentSprint { sprintName = s.name }
            descriptionFocused = true
        }
        .onDisappear { speech.stop() }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(DS.accent).font(.system(size: 22))
                Text("Plan a sprint").font(DS.Font.displayL)
            }
            Text("Name the sprint, pick the repo(s) + branches, describe the sprint in your own words. Cadence splits it into tasks grounded in the repo — you review the split, then run the wizard task-by-task.")
                .font(DS.Font.body).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sprintField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sprint name").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            TextField("e.g. Sprint 14 — mac stability", text: $sprintName)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.cardBG)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius, style: .continuous).stroke(DS.border, lineWidth: 1)
                )
        }
    }

    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Repos for context").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                Spacer()
                Button {
                    pickAndIndexRepo()
                } label: {
                    Label(appState.indexingRepoPath == nil ? "Index a repo…" : "Indexing…",
                          systemImage: "folder.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.indexingRepoPath != nil)
            }
            if let path = appState.indexingRepoPath {
                Card(padding: DS.space3) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Indexing \(path)…").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    }
                }
            }
            if appState.repos.isEmpty && appState.indexingRepoPath == nil {
                Card(padding: DS.space3) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(DS.textTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No repos indexed yet").font(DS.Font.body).foregroundStyle(DS.textPrimary)
                            Text("Click Index a repo above, or ask the chat to index one.")
                                .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
            if !appState.repos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 6) {
                        ForEach(appState.repos) { r in
                            repoChip(r)
                        }
                    }
                    // Branch pickers for each selected repo
                    if !selectedRepos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default branch per repo").font(DS.Font.micro).foregroundStyle(DS.textTertiary)
                            ForEach(appState.repos.filter { selectedRepos.contains($0.id) }) { r in
                                branchPicker(for: r)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func pickAndIndexRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a git repo to index"
        panel.prompt = "Index"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let name = url.lastPathComponent
                _ = await appState.indexRepoDirectly(path: url.path, name: name)
                // auto-select the newly indexed repo
                if let r = appState.repos.first(where: { $0.path == url.path }) {
                    selectedRepos.insert(r.id)
                    await appState.loadBranches(for: r.id)
                }
            }
        }
    }

    private var tasksField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sprint description").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                Spacer()
                Text("free-form prose · agent splits into tasks").font(DS.Font.caption).foregroundStyle(DS.textTertiary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $sprintDescription)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .background(DS.cardBG)
                    .focused($descriptionFocused)
                    .padding(10)
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                            .stroke(descriptionFocused ? DS.accent.opacity(0.5) : DS.border, lineWidth: 1)
                    )
                if sprintDescription.isEmpty {
                    Text("Describe what you plan to do this sprint in whatever detail you have. Example: 'This sprint we're stabilising the Mac backend — the NCCL crash needs a gloo fallback, the uploader keeps dying on flaky wifi and needs retry with backoff, the graph explorer is unusable when repos have more than 500 files, and the helper socket is unauthenticated on shared machines.'")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, 16).padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(DS.textTertiary).font(.caption)
                Text("Agent reads your repo(s) while splitting so proposed task titles ground in real code.")
                    .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private var submitRow: some View {
        HStack(spacing: 10) {
            Button { Task { await speech.toggle() } } label: {
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 15))
                    .foregroundStyle(speech.isListening ? DS.danger : DS.textSecondary)
            }
            .buttonStyle(.borderless)
            if speech.isListening {
                HStack(spacing: 4) {
                    Circle().fill(DS.danger).frame(width: 6, height: 6)
                    Text("Listening").font(DS.Font.micro).foregroundStyle(DS.textSecondary)
                }
            }
            if appState.agentRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(appState.agentCurrentTool.map { "Splitting · \($0)" } ?? "Splitting…")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text("\(wordCount) word\(wordCount == 1 ? "" : "s") · \(selectedRepos.count) repo\(selectedRepos.count == 1 ? "" : "s")")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                    if selectedRepos.isEmpty {
                        Text("· agent will split on prose only")
                            .font(DS.Font.caption).foregroundStyle(DS.warn)
                    }
                }
            }
            Spacer()
            Button {
                Task {
                    var branches: [String: String] = [:]
                    for rid in selectedRepos {
                        if let b = branchPerRepo[rid], !b.isEmpty {
                            branches[rid] = b
                        } else if let c = appState.branchCatalog[rid], !c.current.isEmpty {
                            branches[rid] = c.current
                        }
                    }
                    await appState.submitSprintKickoff(
                        sprintName: sprintName,
                        sprintDescription: sprintDescription,
                        repoIds: Array(selectedRepos),
                        defaultBranches: branches
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Split into tasks")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(sprintDescription.trimmingCharacters(in: .whitespaces).isEmpty || appState.agentRunning)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 20) {
            summaryCell("Tickets", "\(appState.tickets.count)", icon: "list.bullet.rectangle")
            summaryCell("Repos", "\(appState.repos.count)", icon: "folder")
            Spacer()
            if !appState.tickets.isEmpty {
                Button { appState.setArtifact(.sprintStatus) } label: {
                    Label("Sprint status", systemImage: "flag.checkered")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button { appState.setArtifact(.kanban) } label: {
                    Label("Kanban", systemImage: "rectangle.split.3x1")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func summaryCell(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(DS.textTertiary).font(.callout)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(DS.Font.headline)
                Text(label).font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func repoChip(_ r: RepoNode) -> some View {
        let selected = selectedRepos.contains(r.id)
        let stale = r.fileCount == 0
        HStack(spacing: 6) {
            Button {
                if !stale {
                    toggleRepo(r.id)
                    if selectedRepos.contains(r.id) {
                        Task { await appState.loadBranches(for: r.id) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: stale ? "exclamationmark.triangle.fill" : (selected ? "checkmark.circle.fill" : "folder"))
                        .foregroundStyle(stale ? DS.warn : (selected ? DS.accent : DS.textTertiary))
                        .font(.callout)
                    Text(r.name).font(DS.Font.body)
                    Text(stale ? "(not indexed)" : "(\(r.fileCount) files)")
                        .font(DS.Font.caption).foregroundStyle(stale ? DS.warn : DS.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(stale)
            Menu {
                Button {
                    Task { await appState.removeRepo(r.id) }
                } label: { Label("Remove repo", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.caption).foregroundStyle(DS.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 16)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .fill(selected ? DS.accentSoft : DS.cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .stroke(stale ? DS.warn.opacity(0.5) : (selected ? DS.accent.opacity(0.4) : DS.border), lineWidth: 1)
        )
    }

    private func branchPicker(for r: RepoNode) -> some View {
        let catalog = appState.branchCatalog[r.id] ?? BranchCatalog()
        let selected = branchPerRepo[r.id] ?? catalog.current
        return HStack(spacing: 8) {
            Image(systemName: "folder").font(.caption2).foregroundStyle(DS.warn)
            Text(r.name).font(DS.Font.caption).foregroundStyle(DS.textSecondary).frame(width: 140, alignment: .leading)
            Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(DS.textTertiary)
            Menu {
                if catalog.branches.isEmpty {
                    Text("Loading branches…")
                }
                ForEach(catalog.branches, id: \.self) { b in
                    Button(b) { branchPerRepo[r.id] = b }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selected.isEmpty ? "(select)" : selected)
                        .font(DS.Font.mono).foregroundStyle(DS.textPrimary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.insetBG))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 240, alignment: .leading)
            Spacer()
        }
    }

    private var wordCount: Int {
        sprintDescription.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func toggleRepo(_ id: String) {
        if selectedRepos.contains(id) { selectedRepos.remove(id) }
        else { selectedRepos.insert(id) }
    }
}
