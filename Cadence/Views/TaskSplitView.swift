import SwiftUI

/// Shown between kickoff and wizard: agent's proposed task split.
/// User can edit titles, priorities, estimates, remove/add/reorder, then proceed to wizard.
struct TaskSplitView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let staging = appState.splitStaging {
            body(for: staging)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 30)).foregroundStyle(DS.textTertiary)
            Text("No split in progress").foregroundStyle(DS.textSecondary)
            Button { appState.setArtifact(.kickoff) } label: {
                Label("Back to start", systemImage: "sparkles")
            }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func body(for s: SplitStaging) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header(s: s)
                sprintCard(s: s)
                tasksSection(s: s)
                footer(s: s)
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    private func header(s: SplitStaging) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Review split").font(DS.Font.displayL)
                Spacer()
                Button { appState.setArtifact(.kickoff) } label: {
                    Label("Back to kickoff", systemImage: "arrow.left")
                }.buttonStyle(SecondaryButtonStyle())
            }
            Text("\(s.tasks.count) task\(s.tasks.count == 1 ? "" : "s") drafted from your sprint description. Edit before running the wizard.")
                .font(DS.Font.body).foregroundStyle(DS.textSecondary)
        }
    }

    private func sprintCard(s: SplitStaging) -> some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered").foregroundStyle(DS.accent).font(.callout)
                    Text(s.sprintName.isEmpty ? "(unnamed sprint)" : s.sprintName).font(DS.Font.headline)
                    Spacer()
                    ForEach(s.repoIds, id: \.self) { rid in
                        if let r = appState.repos.first(where: { $0.id == rid }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder").font(.caption2).foregroundStyle(DS.warn)
                                Text(r.name).font(DS.Font.micro)
                                let br = s.defaultBranches[rid] ?? ""
                                if !br.isEmpty {
                                    Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(DS.textTertiary)
                                    Text(br).font(DS.Font.mono).foregroundStyle(DS.textPrimary)
                                }
                            }
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(DS.subtleFill))
                        }
                    }
                }
                Text(s.sprintDescription)
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }
        }
    }

    private func tasksSection(s: SplitStaging) -> some View {
        VStack(alignment: .leading, spacing: DS.space3) {
            HStack {
                Text("Proposed tasks").font(DS.Font.title)
                Spacer()
                Button {
                    Task { await appState.regenerateSplit() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.agentRunning)
                Button { appState.splitAddEmptyTask() } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            ForEach(Array(s.tasks.enumerated()), id: \.element.id) { idx, task in
                TaskRow(index: idx, task: task)
            }
            if s.tasks.isEmpty {
                Card {
                    HStack {
                        Image(systemName: "questionmark.circle").foregroundStyle(DS.textTertiary)
                        Text("No tasks. Add manually or regenerate.").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
    }

    private func footer(s: SplitStaging) -> some View {
        HStack {
            Text("\(nonEmptyCount(s)) valid task\(nonEmptyCount(s) == 1 ? "" : "s") will feed the wizard.")
                .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            Spacer()
            Button {
                appState.splitStaging = nil
                appState.setArtifact(.kickoff)
            } label: {
                Label("Discard", systemImage: "trash")
            }
            .buttonStyle(SecondaryButtonStyle())
            Button {
                Task { await appState.splitProceedToWizard() }
            } label: {
                HStack(spacing: 6) {
                    Text("Proceed to wizard")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(nonEmptyCount(s) == 0)
        }
    }

    private func nonEmptyCount(_ s: SplitStaging) -> Int {
        s.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

private struct TaskRow: View {
    @EnvironmentObject var appState: AppState
    let index: Int
    let task: ProposedTask
    @State private var title: String = ""
    @State private var hint: String = ""

    var body: some View {
        Card(padding: DS.space4) {
            HStack(alignment: .top, spacing: DS.space3) {
                Text("\(index + 1).").font(DS.Font.headline).foregroundStyle(DS.textTertiary).frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Task title", text: $title)
                        .textFieldStyle(.plain)
                        .font(DS.Font.headline)
                        .onSubmit { commit() }
                    TextField("Hint / rationale", text: $hint)
                        .textFieldStyle(.plain)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .onSubmit { commit() }
                }
                Spacer()
                priorityMenu
                Button { appState.splitRemoveTask(at: index) } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DS.textTertiary)
            }
        }
        .onAppear { title = task.title; hint = task.hint }
        .onChange(of: title) { _, _ in commit() }
        .onChange(of: hint) { _, _ in commit() }
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(Priority.allCases) { p in
                Button(p.rawValue) { appState.splitUpdateTask(index) { $0.priority = p } }
            }
        } label: {
            Chip(task.priority.rawValue, tint: priorityTint(task.priority))
        }
        .menuStyle(.borderlessButton)
    }

    private func commit() {
        appState.splitUpdateTask(index) { t in
            t.title = title
            t.hint = hint
        }
    }

    private func priorityTint(_ p: Priority) -> Color {
        switch p {
        case .p0: return DS.danger
        case .p1: return DS.warn
        case .p2: return .yellow
        case .p3: return DS.accent
        case .p4: return DS.textTertiary
        }
    }
}
