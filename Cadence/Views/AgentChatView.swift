import SwiftUI

/// New chat pane: shows conversation + proposed-actions panel when Claude wants to mutate.
struct AgentChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speech = SpeechRecognizer()
    @State private var input: String = ""
    @State private var busy = false
    @State private var pendingTurn: ProposedTurn?
    @State private var selectedActions: Set<AgentAction> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.border)
            conversation
                .frame(maxHeight: .infinity)
            if pendingTurn != nil {
                Divider().overlay(DS.border)
                proposalPanel
                    .frame(maxHeight: 320)
                    .background(DS.sidebarBG)
            }
            Divider().overlay(DS.border)
            composer
        }
        .background(DS.contentBG)
        .onChange(of: speech.transcript) { _, new in if !new.isEmpty { input = new } }
        .onChange(of: appState.pendingChatPrompt) { _, new in
            if let p = new, !p.isEmpty {
                input = p
                appState.pendingChatPrompt = nil
                Task { await send() }
            }
        }
        .onAppear { Task { await speech.requestAuth() } }
        .onDisappear { speech.stop() }
    }

    // MARK: header — chat picker + new chat
    @State private var showChatList = false
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(DS.accent)
                Button {
                    showChatList.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.currentConversation?.title ?? "New chat")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: showChatList ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    appState.newConversation()
                    showChatList = false
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .buttonStyle(.borderless)
                .help("New chat")
            }
            .padding(DS.space3)
            if showChatList { chatListDropdown }
            if appState.agentRunning { agentStatusBar }
        }
    }

    private var chatListDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(DS.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.conversations.reversed()) { c in
                        HStack(spacing: 8) {
                            Image(systemName: c.id == appState.currentConversationId ? "checkmark.circle.fill" : "bubble.left")
                                .foregroundStyle(c.id == appState.currentConversationId ? DS.accent : .secondary)
                                .font(.caption)
                            Text(c.title).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text(shortRelative(c.updatedAt)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Button {
                                appState.deleteConversation(c.id)
                            } label: { Image(systemName: "trash").font(.caption) }
                            .buttonStyle(.borderless)
                            .opacity(0.6)
                        }
                        .padding(.horizontal, DS.space3)
                        .padding(.vertical, 6)
                        .background(c.id == appState.currentConversationId ? DS.accentSoft : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.switchConversation(c.id)
                            showChatList = false
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            Divider().overlay(DS.border)
        }
    }

    private var agentStatusBar: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(DS.accent)
            let elapsed = appState.agentStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
            if let tool = appState.agentCurrentTool {
                Text("Calling ").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(tool).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(DS.accent)
            } else {
                Text("Thinking…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(appState.agentToolCount) call\(appState.agentToolCount == 1 ? "" : "s") · \(elapsed)s")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.space3).padding(.vertical, 6)
        .background(DS.accentSoft)
    }

    private func shortRelative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    // MARK: conversation
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space3) {
                    if appState.chatLog.isEmpty {
                        emptyState
                    }
                    ForEach(appState.chatLog) { e in
                        chatBubble(e).id(e.id)
                    }
                    if let err = errorMessage {
                        Text(err).font(.system(size: 12)).foregroundStyle(DS.danger).padding(.horizontal, DS.space4)
                    }
                }
                .padding(.vertical, DS.space4)
            }
            .onChange(of: appState.chatLog.count) { _, _ in
                if let last = appState.chatLog.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try:").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(examplePrompts, id: \.self) { p in
                Button {
                    input = p
                } label: {
                    HStack {
                        Image(systemName: "text.cursor").foregroundStyle(DS.accent)
                        Text(p).font(.system(size: 12)).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(DS.space3)
                    .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.subtleFill))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.space4)
    }

    private let examplePrompts: [String] = [
        "Add ticket 'wire up Slack webhook' as P2, assign to me, in current sprint.",
        "Move PXLV-3 to In Progress.",
        "PXLV-12 is P0 now — cisco blocker.",
        "Comment on PXLV-5: 'blocked on infra team ticket #7811'.",
        "Add sprint 'S12' starting 2026-08-03, 2 weeks.",
    ]

    private func chatBubble(_ e: ChatEntry) -> some View {
        let mine = e.role == "you"
        return HStack(alignment: .top, spacing: DS.space3) {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                Text(mine ? "You" : "Cadence")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mine ? DS.accent : DS.purple)
                Text(e.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .foregroundStyle(mine ? .white : DS.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                            .fill(mine ? AnyShapeStyle(DS.accentGradient) : AnyShapeStyle(DS.cardBG))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                            .stroke(mine ? Color.clear : DS.border, lineWidth: 1)
                    )
                    .cardShadow(mine ? 2 : 1)
                    .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
            }
            if !mine { Spacer(minLength: 40) }
        }
        .padding(.horizontal, DS.space4)
    }

    // MARK: proposal panel
    private var proposalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.accent)
                Text("Proposed changes").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(selectedActions.count)/\(pendingTurn?.actions.count ?? 0) selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(DS.space3)
            Divider().overlay(DS.border)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.space2) {
                    ForEach(pendingTurn?.actions ?? []) { action in
                        actionRow(action)
                    }
                }
                .padding(DS.space3)
            }

            Divider().overlay(DS.border)
            HStack(spacing: 8) {
                Button {
                    pendingTurn = nil
                    selectedActions = []
                } label: {
                    Text("Reject").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)

                Button {
                    Task { await applySelected() }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.small).tint(.white) }
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Apply \(selectedActions.count)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedActions.isEmpty || busy)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(DS.space3)
        }
    }

    private func actionRow(_ action: AgentAction) -> some View {
        let isOn = selectedActions.contains(action)
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { selectedActions.insert(action) } else { selectedActions.remove(action) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(action.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(action.isDestructive ? DS.danger : .primary)
                if action.isDestructive {
                    Text("Destructive — off by default.").font(.system(size: 10)).foregroundStyle(DS.danger)
                }
            }
            Spacer()
        }
        .padding(DS.space2)
        .background(RoundedRectangle(cornerRadius: 6).fill(DS.subtleFill))
    }

    // MARK: composer
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if speech.isListening {
                HStack(spacing: 6) {
                    Circle().fill(DS.danger).frame(width: 8, height: 8).opacity(0.7)
                    Text("Listening… \(speech.transcript.isEmpty ? "(say something)" : "")")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, DS.space4)
                .padding(.top, 6)
            }
            HStack(spacing: 8) {
                Button { Task { await speech.toggle() } } label: {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(speech.isListening ? DS.danger : .primary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)

                TextField("Ask, dictate, or command…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                            .fill(DS.cardBG)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                            .stroke(DS.border, lineWidth: 1)
                    )
                    .onSubmit { Task { await send() } }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(DS.accent)
                }
                .buttonStyle(.borderless)
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(DS.space3)
        }
    }

    // MARK: send + apply
    private func send() async {
        let msg = input.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        input = ""
        speech.stop()
        errorMessage = nil
        busy = true
        defer { busy = false }
        appState.appendChat(ChatEntry(role: "you", text: msg, at: Date()))

        // Include last 20 chat turns (excluding the just-appended user message which is passed separately)
        let history = appState.chatLog.dropLast().suffix(20).map { e in
            "\(e.role.uppercased()): \(e.text)"
        }.joined(separator: "\n---\n")

        let issuesPath = CadencePaths.issuesDir.path
        let systemPrompt = """
        You are the Cadence sprint assistant. Issues are stored as markdown files — one folder per issue —
        under \(issuesPath) (issue.md = frontmatter + ## Description + ## Solution; exploration.md; solution-exploration.md).
        You have native tools: Read, Grep, Glob, Bash(git *). Read those files directly to research before proposing.
        The user's current issues are listed in the message below. Never fabricate IDs. If uncertain, ask via reply.

        Final message MUST be raw JSON, no prose, no code fences. One of:
          {"kind":"reply","text":"..."}
          {"kind":"propose","reply":"one-line summary","actions":[{"kind":"...","args":{...}}, ...]}

        Available action kinds (these are the ONLY ones):
        add_ticket {id, title, priority(P0-P4), status, estimate, assignee, labels[], sprint, description}
        update_ticket {id, fields{...}}
        move_ticket {id, to_status(Backlog|Todo|"In Progress"|"In Review"|Done)}
        reprioritize {id, to_priority, reason}
        add_comment {ticket_id, body}
        delete_ticket {id}

        Ticket ID convention: PROJ-N (reuse the existing prefix if evident, else CAD-N where N = max existing + 1).
        """

        let ticketList = appState.tickets.map {
            "\($0.id) [\($0.priority.rawValue)] \($0.status.rawValue) — \($0.title)"
        }.joined(separator: "\n")

        let userTurn = """
        CURRENT ISSUES:
        \(ticketList.isEmpty ? "(none)" : ticketList)

        CONVERSATION HISTORY (oldest → newest):
        \(history.isEmpty ? "(first turn)" : history)

        NEW USER MESSAGE:
        \(msg)
        """

        appState.agentStart()
        defer { appState.agentStop() }
        do {
            let onTool: @Sendable (String) async -> Void = { name in
                await MainActor.run { appState.agentToolCalled(name) }
            }
            let dirs = [issuesPath] + appState.repos.map { $0.path }
            let obj = try await appState.claude.promptAgentJSONStreaming(
                userMessage: userTurn,
                systemPrompt: systemPrompt,
                onToolUse: onTool,
                addDirs: dirs,
                timeout: 300
            )
            guard let d = obj as? [String: Any] else { throw AgentError.badArg("no JSON dict") }
            let kind = d["kind"] as? String ?? "reply"
            if kind == "propose" {
                let raw = (d["actions"] as? [[String: Any]]) ?? []
                let actions = raw.compactMap(AgentAction.fromJSON)
                let reply = d["reply"] as? String ?? "Proposed \(actions.count) action(s)."
                appState.appendChat(ChatEntry(role: "claude", text: reply, at: Date()))
                if actions.isEmpty {
                    appState.appendChat(ChatEntry(role: "claude", text: "(no valid actions parsed)", at: Date()))
                } else {
                    pendingTurn = ProposedTurn(userMessage: msg, claudeReply: reply, actions: actions, at: Date())
                    selectedActions = Set(actions.filter { !$0.isDestructive })
                }
            } else {
                let text = d["text"] as? String ?? "(empty)"
                appState.appendChat(ChatEntry(role: "claude", text: text, at: Date()))
            }
        } catch {
            errorMessage = error.localizedDescription
            appState.appendChat(ChatEntry(role: "claude", text: "Error: \(error.localizedDescription)", at: Date()))
        }
    }

    private func applySelected() async {
        guard let turn = pendingTurn else { return }
        busy = true
        defer { busy = false }
        var report: [String] = []
        for action in turn.actions where selectedActions.contains(action) {
            if let err = await AgentDispatcher.apply(action, appState: appState) {
                report.append("✗ \(action.summary) — \(err)")
            } else {
                report.append("✓ \(action.summary)")
            }
        }
        appState.appendChat(ChatEntry(role: "claude", text: report.joined(separator: "\n"), at: Date()))
        pendingTurn = nil
        selectedActions = []
    }
}
