import SwiftUI

/// Signature flow: kickoff produced N drafts. Per draft, user picks repos to attach,
/// clicks Enrich → agent uses those repos to populate a rich description + file/functionality links,
/// then Approve commits the ticket + all its links in one unit.
struct DraftReviewStackView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header
                if drafts.isEmpty {
                    empty
                } else {
                    ForEach(drafts) { d in
                        DraftCard(draft: d)
                    }
                    bulkFooter
                }
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review drafts").font(DS.Font.displayL)
                Text("\(drafts.count) draft\(drafts.count == 1 ? "" : "s") from your kickoff. Attach repos per draft, enrich, then approve.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
            }
            Spacer()
            Button {
                appState.setArtifact(.kickoff)
            } label: { Label("Back to start", systemImage: "sparkles") }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var empty: some View {
        Card {
            HStack(spacing: DS.space3) {
                Image(systemName: "square.stack").foregroundStyle(DS.textTertiary).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text("No drafts pending").font(DS.Font.headline)
                    Text("Head to Start, dump your sprint, and drafts land here.")
                        .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Button { appState.setArtifact(.kickoff) } label: { Label("Start", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var bulkFooter: some View {
        Card {
            HStack {
                Text("\(drafts.filter { $0.enriched }.count) of \(drafts.count) enriched.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                Spacer()
                Button {
                    Task {
                        for d in drafts where d.enriched {
                            await appState.approveDraft(d)
                        }
                    }
                } label: {
                    Label("Approve all enriched", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(drafts.filter { $0.enriched }.isEmpty)
                Button {
                    appState.pendingDrafts.removeAll()
                    appState.setArtifact(.kickoff)
                } label: { Label("Discard all", systemImage: "trash") }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var drafts: [TicketDraft] {
        appState.pendingDrafts
    }
}

private struct DraftCard: View {
    @EnvironmentObject var appState: AppState
    let draft: TicketDraft
    @State private var localTitle: String = ""
    @State private var localDesc: String = ""
    @State private var localPriority: Priority = .p3
    @State private var localEstimate: Double = 0
    @State private var selectedRepos: Set<String> = []
    @State private var enriching = false

    var body: some View {
        Card(padding: DS.space5) {
            VStack(alignment: .leading, spacing: DS.space4) {
                cardHeader
                titleField
                metaRow
                descriptionSection
                if !draft.attachedRepoIds.isEmpty || draft.enriched {
                    linksSection
                }
                Divider().overlay(DS.borderSoft)
                repoAttachment
                actionRow
            }
        }
        .onAppear { hydrate() }
        .onChange(of: draft.id) { _, _ in hydrate() }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Chip(draft.enriched ? "ENRICHED" : "DRAFT",
                 tint: draft.enriched ? DS.ok : DS.accent)
            Text(draft.id).font(DS.Font.mono).foregroundStyle(DS.textSecondary)
            Spacer()
            Button { appState.rejectDraft(draft) } label: { Label("Discard", systemImage: "xmark") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var titleField: some View {
        TextField("Title", text: $localTitle).textFieldStyle(.plain).font(DS.Font.title)
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            Picker("Priority", selection: $localPriority) {
                ForEach(Priority.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .frame(width: 170)
            HStack {
                Text("Estimate").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                TextField("h", value: $localEstimate, format: .number).frame(width: 60)
            }
            Spacer()
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            TextEditor(text: $localDesc)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(DS.insetBG)
                .frame(minHeight: 110)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.border, lineWidth: 1))
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draft.linkedFunctionalities.isEmpty {
                HStack(alignment: .top) {
                    Text("Functionality").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                        .frame(width: 100, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(draft.linkedFunctionalities, id: \.self) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "cube.transparent").foregroundStyle(DS.purple).font(.caption)
                                Text(f).font(DS.Font.body)
                            }
                        }
                    }
                }
            }
            if !draft.linkedFiles.isEmpty {
                HStack(alignment: .top) {
                    Text("Files").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                        .frame(width: 100, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(draft.linkedFiles, id: \.query) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").foregroundStyle(DS.ok).font(.caption)
                                Text(f.query).font(DS.Font.mono)
                                if !f.note.isEmpty {
                                    Text("· \(f.note)").font(DS.Font.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var repoAttachment: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attach repos for enrichment").font(DS.Font.callout).foregroundStyle(DS.textSecondary)
                Spacer()
                if appState.repos.isEmpty {
                    Text("No repos indexed — ask agent to index one first.")
                        .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                }
            }
            if !appState.repos.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(appState.repos) { r in
                        Button { toggle(r.id) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: selectedRepos.contains(r.id) ? "checkmark.circle.fill" : "folder")
                                    .foregroundStyle(selectedRepos.contains(r.id) ? DS.accent : DS.textTertiary)
                                    .font(.caption)
                                Text(r.name).font(DS.Font.caption)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                                    .fill(selectedRepos.contains(r.id) ? DS.accentSoft : DS.insetBG)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                                    .stroke(selectedRepos.contains(r.id) ? DS.accent.opacity(0.4) : DS.borderSoft, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if enriching || (appState.agentRunning && draft.attachedRepoIds.isEmpty && !selectedRepos.isEmpty) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(appState.agentCurrentTool.map { "Calling \($0)" } ?? "Enriching…")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
            Button {
                Task {
                    enriching = true
                    // save current edits before enrichment overwrites
                    persistLocalEdits()
                    await appState.enrichDraft(currentDraft(), withRepoIds: Array(selectedRepos))
                    enriching = false
                }
            } label: {
                Label(draft.enriched ? "Re-enrich" : "Enrich with repos",
                      systemImage: "sparkles.rectangle.stack")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(selectedRepos.isEmpty || enriching)
            Button {
                persistLocalEdits()
                Task { await appState.approveDraft(currentDraft()) }
            } label: {
                Label(draft.enriched ? "Approve" : "Approve anyway",
                      systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func hydrate() {
        localTitle = draft.title
        localDesc = draft.description
        localPriority = draft.priority
        localEstimate = draft.estimate
        selectedRepos = Set(draft.attachedRepoIds)
    }

    private func persistLocalEdits() {
        if let idx = appState.pendingDrafts.firstIndex(where: { $0.id == draft.id }) {
            appState.pendingDrafts[idx].title = localTitle
            appState.pendingDrafts[idx].description = localDesc
            appState.pendingDrafts[idx].priority = localPriority
            appState.pendingDrafts[idx].estimate = localEstimate
        }
    }

    private func currentDraft() -> TicketDraft {
        var d = draft
        d.title = localTitle
        d.description = localDesc
        d.priority = localPriority
        d.estimate = localEstimate
        return d
    }

    private func toggle(_ id: String) {
        if selectedRepos.contains(id) { selectedRepos.remove(id) }
        else { selectedRepos.insert(id) }
    }
}

/// Small flow-layout: wraps children onto rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var w: CGFloat = 0, h: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if w + s.width > maxW {
                h += rowH + spacing
                w = 0; rowH = 0
            }
            w += s.width + spacing
            rowH = max(rowH, s.height)
        }
        h += rowH
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
