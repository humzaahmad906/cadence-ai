import SwiftUI

/// Default canvas artifact: risk-first sprint status. Combines KPIs + risk surfacing +
/// agent-suggested "what to do next" into one page.
struct SprintStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header
                kpiRow
                riskSection
                nextActionsHint
                Divider().overlay(DS.borderSoft)
                secondaryGrid
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.space4) {
            VStack(alignment: .leading, spacing: 4) {
                if let s = appState.currentSprint {
                    Text(s.name).font(DS.Font.displayL)
                    HStack(spacing: 6) {
                        StatusDot(tint: sprintTint(s.daysLeft), glow: s.daysLeft <= 3)
                        Text("\(s.daysLeft) days left · \(s.startDate) → \(s.endDate)")
                            .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                    }
                } else {
                    Text("No active sprint").font(DS.Font.displayL)
                    Text("Ask the agent: 'start a new sprint' or paste with ⇧⌘V.")
                        .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
            if let s = appState.currentSprint {
                ProgressView(value: sprintProgress(s))
                    .tint(DS.accent)
                    .frame(width: 220)
            }
        }
    }

    // MARK: KPIs

    private var kpiRow: some View {
        HStack(spacing: DS.space4) {
            kpi("Open", value: "\(open)", tint: DS.accent, icon: "circle.dashed")
            kpi("Done", value: "\(done)", tint: DS.ok, icon: "checkmark.circle.fill")
            kpi("Blocked", value: "\(blocked)", tint: DS.warn, icon: "exclamationmark.triangle.fill")
            kpi("P0/P1 open", value: "\(urgentOpen)", tint: DS.danger, icon: "flame.fill")
        }
    }

    private func kpi(_ label: String, value: String, tint: Color, icon: String) -> some View {
        Card(padding: DS.space4) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(DS.Font.display)
                    Text(label).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
                Spacer()
            }
        }
    }

    // MARK: risk

    private var riskSection: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.space3) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(DS.danger)
                    Text("Risk").font(DS.Font.title)
                    Spacer()
                    Text("\(totalRiskCount) items").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
                if totalRiskCount == 0 {
                    Text("Sprint looks clean. No blockers, no idle work.")
                        .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                } else {
                    if !blockedTickets.isEmpty {
                        riskGroup("Blocked", items: blockedTickets.map { ticketLine($0) }, tint: DS.warn)
                    }
                    if !urgentTickets.isEmpty {
                        riskGroup("Urgent open (P0/P1)", items: urgentTickets.map { ticketLine($0) }, tint: DS.danger)
                    }
                    if !idleTickets.isEmpty {
                        riskGroup("Idle > 2 days in progress", items: idleTickets.map { ticketLine($0) }, tint: DS.warn)
                    }
                }
            }
        }
    }

    private func riskGroup(_ title: String, items: [RiskLine], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).font(DS.Font.callout).foregroundStyle(DS.textSecondary)
            }
            .padding(.top, 6)
            ForEach(items) { item in
                Button {
                    if let a = item.target { appState.setArtifact(a) }
                } label: {
                    HStack(spacing: 8) {
                        if let id = item.leadingId {
                            Text(id).font(DS.Font.mono).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                        }
                        Text(item.body).font(DS.Font.body).lineLimit(1)
                        Spacer()
                        if let trailing = item.trailing {
                            Text(trailing).font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DS.textTertiary)
                    }
                    .padding(.horizontal, DS.space3).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.insetBG))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: next actions

    private var nextActionsHint: some View {
        Card {
            HStack(alignment: .top, spacing: DS.space3) {
                Image(systemName: "sparkles").foregroundStyle(DS.accent).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested next actions").font(DS.Font.headline)
                    Text(nextActionText).font(DS.Font.body).foregroundStyle(DS.textPrimary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            appState.requestChat("Look at the risk section on the sprint status. Propose concrete next actions to reduce the risk — one action per risk item. Cite ticket IDs from list_tickets.")
                        } label: {
                            Label("Ask agent to plan", systemImage: "wand.and.rays")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button {
                            appState.requestCritique()
                        } label: {
                            Label("Run full critique", systemImage: "magnifyingglass.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }

    private var nextActionText: String {
        if let p0 = urgentTickets.first(where: { $0.priority == .p0 && !$0.blockers.isEmpty }) {
            return "\(p0.id) is P0 and blocked. Unblock that first — that's what's actually stopping the sprint."
        }
        if let stuck = idleTickets.first {
            return "\(stuck.id) has been in progress > 2 days. Move it or split it."
        }
        if let anyUrgent = urgentTickets.first {
            return "\(anyUrgent.id) is your highest-priority open work. Focus there."
        }
        if let s = appState.currentSprint, s.daysLeft <= 3, done < appState.tickets.count / 2 {
            return "\(s.daysLeft)d left and < 50% done. Ask the agent to descope."
        }
        if appState.tickets.isEmpty {
            return "No tickets yet. Dump a sprint into chat and let the agent draft them."
        }
        return "Nothing on fire. Pick from the top of the backlog."
    }

    // MARK: secondary — tagged repos
    private var secondaryGrid: some View {
        Card { reposCardBody }.frame(maxWidth: .infinity)
    }

    private var reposCardBody: some View {
        VStack(alignment: .leading, spacing: DS.space3) {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(DS.warn)
                Text("Repos").font(DS.Font.title)
                Spacer()
            }
            if appState.repos.isEmpty {
                Text("None registered. Add one from the Start screen.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
            } else {
                ForEach(Array(appState.repos.prefix(5))) { r in
                    HStack(spacing: 8) {
                        StatusDot(tint: DS.warn)
                        Text(r.name).font(DS.Font.body).fontWeight(.medium)
                        Spacer()
                        Text("\(r.fileCount) files · \(r.headSha.prefix(7))")
                            .font(DS.Font.mono).foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: derived

    private var open: Int { appState.tickets.filter { $0.status != .done }.count }
    private var done: Int { appState.tickets.filter { $0.status == .done }.count }
    private var blocked: Int { appState.tickets.filter { !$0.blockers.isEmpty }.count }
    private var urgentOpen: Int { appState.tickets.filter { $0.priority.urgent && $0.status != .done }.count }
    private var blockedTickets: [Ticket] {
        appState.tickets.filter { !$0.blockers.isEmpty }.sorted { $0.priority.rank < $1.priority.rank }.prefix(5).map { $0 }
    }
    private var urgentTickets: [Ticket] {
        appState.tickets.filter { $0.priority.urgent && $0.status != .done }.sorted { $0.priority.rank < $1.priority.rank }.prefix(5).map { $0 }
    }
    private var idleTickets: [Ticket] {
        let cutoff = Date().addingTimeInterval(-2 * 24 * 3600)
        let iso = ISO8601DateFormatter()
        return appState.tickets.filter {
            $0.status == .inProgress && (iso.date(from: $0.updated) ?? .distantPast) < cutoff
        }.prefix(5).map { $0 }
    }
    private var totalRiskCount: Int {
        blockedTickets.count + urgentTickets.count + idleTickets.count
    }

    private struct RiskLine: Identifiable {
        let id = UUID()
        let leadingId: String?
        let body: String
        let trailing: String?
        let target: CanvasArtifact?
    }
    private func ticketLine(_ t: Ticket) -> RiskLine {
        RiskLine(leadingId: t.id, body: t.title,
                 trailing: "[\(t.priority.rawValue)] \(t.status.rawValue)",
                 target: .ticketDetail(id: t.id))
    }
    private func sprintProgress(_ s: Sprint) -> Double {
        guard let start = s.startDateObj, let end = s.endDateObj, end > start else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    private func sprintTint(_ daysLeft: Int) -> Color {
        if daysLeft <= 3 { return DS.danger }
        if daysLeft <= 5 { return DS.warn }
        return DS.ok
    }
}
