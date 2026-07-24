import SwiftUI
import Foundation

/// Right-panel debugger for Debug mode. Read-only: it reflects `appState.activeRun`
/// and never mutates state.
///
/// Layout mirrors the design handoff (`mockups/02-debug.png`):
/// - a header row (live status dot + text, and a right-aligned "N/M done"),
/// - an I/O card for the current block (title + status pill, then dark INPUT / OUTPUT
///   panels rendered in a monospaced neon-on-black terminal style),
/// - a scrollable RUN LOG built from every block in order, each with a status icon,
///   the block title, and a trailing duration once the block has finished.
struct DebugPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let run = appState.activeRun {
                content(run)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.cardBG)
    }

    // MARK: - Populated panel

    private func content(_ run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            header(run)
            if let block = currentBlock(run) {
                ioCard(block)
            }
            runLog(run)
        }
        .padding(DS.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private func header(_ run: WorkflowRun) -> some View {
        let executing = isExecuting(run)
        return HStack(spacing: DS.space2) {
            StatusDot(tint: statusTint(run), glow: executing)
            Text(statusText(run))
                .font(DS.Font.headline)
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.space2)
            HStack(spacing: 4) {
                Text("\(doneCount(run))/\(run.blocks.count)")
                    .font(DS.Font.mono)
                Text("done")
                    .font(DS.Font.caption)
            }
            .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: I/O card

    private func ioCard(_ block: BlockRunState) -> some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space3) {
                HStack(spacing: DS.space2) {
                    Text(title(block))
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.space2)
                    Chip(pillLabel(block.status), tint: pillTint(block.status))
                }
                ioPanel(label: "INPUT", text: block.input, tint: .cyan)
                ioPanel(label: "OUTPUT", text: block.output, tint: .green)
            }
        }
    }

    /// A dark, terminal-style panel: uppercase section label above a black rounded rect
    /// holding the text in a monospaced neon tint. Scrolls internally, capped at ~120pt.
    private func ioPanel(label: String, text: String, tint: Color) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        return VStack(alignment: .leading, spacing: DS.space1) {
            sectionLabel(label)
            ScrollView {
                Text(isEmpty ? "no \(label.lowercased()) yet" : text)
                    .font(DS.Font.mono)
                    .foregroundStyle(isEmpty ? Color.white.opacity(0.28) : tint.opacity(0.95))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.space3)
            }
            .frame(maxHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
        }
    }

    // MARK: Run log

    private func runLog(_ run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            sectionLabel("RUN LOG")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(run.blocks.enumerated()), id: \.element.id) { idx, block in
                        if idx > 0 {
                            Rectangle().fill(DS.borderSoft).frame(height: 1)
                        }
                        logRow(block)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func logRow(_ block: BlockRunState) -> some View {
        HStack(spacing: DS.space2) {
            logIcon(block.status)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)
            Text(title(block))
                .font(DS.Font.body)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.space2)
            if let dur = durationString(block) {
                Text(dur)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.space2)
    }

    @ViewBuilder
    private func logIcon(_ status: BlockRunStatus) -> some View {
        switch status {
        case .running:        Image(systemName: "play.fill").foregroundStyle(DS.accent)
        case .done:           Image(systemName: "checkmark").foregroundStyle(DS.ok)
        case .failed:         Image(systemName: "xmark.octagon").foregroundStyle(DS.danger)
        case .awaitingReview: Image(systemName: "hand.raised.fill").foregroundStyle(DS.warn)
        case .skipped:        Image(systemName: "minus").foregroundStyle(DS.textTertiary)
        case .pending:        Image(systemName: "circle").foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: DS.space3) {
            Image(systemName: "play.circle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(DS.textTertiary)
            Text("No active run")
                .font(DS.Font.headline)
                .foregroundStyle(DS.textSecondary)
            Text("Press Run to execute this workflow.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.space6)
    }

    // MARK: Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.micro)
            .fontWeight(.semibold)
            .tracking(0.5)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Derivations (pure, read-only)

    private func title(_ block: BlockRunState) -> String {
        block.title.isEmpty ? block.kind.label : block.title
    }

    private func isExecuting(_ run: WorkflowRun) -> Bool {
        run.blocks.contains { $0.status == .running }
    }

    private func doneCount(_ run: WorkflowRun) -> Int {
        run.blocks.filter { $0.status == .done }.count
    }

    /// The block the I/O card focuses on: the running one, else the last completed, else the first.
    private func currentBlock(_ run: WorkflowRun) -> BlockRunState? {
        if let running = run.blocks.first(where: { $0.status == .running }) { return running }
        if let lastDone = run.blocks.last(where: { $0.status == .done }) { return lastDone }
        return run.blocks.first
    }

    private func statusText(_ run: WorkflowRun) -> String {
        if isExecuting(run) { return "Executing…" }
        if run.status == .done { return "Run complete" }
        switch run.status {
        case .pending:        return "Pending"
        case .running:        return "Running…"
        case .awaitingReview: return "Awaiting review"
        case .failed:         return "Run failed"
        case .done:           return "Run complete"
        }
    }

    private func statusTint(_ run: WorkflowRun) -> Color {
        if isExecuting(run) { return DS.accent }
        switch run.status {
        case .done:           return DS.ok
        case .failed:         return DS.danger
        case .awaitingReview: return DS.warn
        case .running:        return DS.accent
        case .pending:        return DS.textTertiary
        }
    }

    private func pillLabel(_ status: BlockRunStatus) -> String {
        switch status {
        case .pending:        return "PENDING"
        case .running:        return "RUNNING"
        case .awaitingReview: return "REVIEW"
        case .done:           return "DONE"
        case .failed:         return "FAILED"
        case .skipped:        return "SKIPPED"
        }
    }

    private func pillTint(_ status: BlockRunStatus) -> Color {
        switch status {
        case .running:           return DS.accent
        case .done:              return DS.ok
        case .failed:            return DS.danger
        case .awaitingReview:    return DS.warn
        case .pending, .skipped: return DS.textTertiary
        }
    }

    /// Elapsed time for a finished block, formatted like the mockup ("3ms", "3.4s").
    private func durationString(_ block: BlockRunState) -> String? {
        guard let start = block.startedAt, let end = block.finishedAt else { return nil }
        let ms = end.timeIntervalSince(start) * 1000
        guard ms >= 0 else { return nil }
        if ms < 1000 {
            return "\(Int(ms.rounded()))ms"
        }
        return String(format: "%.1fs", ms / 1000)
    }
}
